import AVFoundation
import CoreMIDI
import Foundation
import OSLog

struct LiveMIDINote: Identifiable, Equatable, Sendable {
    let number: UInt8
    let velocity: UInt8
    let channel: UInt8
    var id: Int { Int(channel) * 128 + Int(number) }
}

enum MIDIMessage: Equatable, Sendable {
    case noteOn(UInt8, UInt8, UInt8)
    case noteOff(UInt8, UInt8)
    case control(UInt8, UInt8, UInt8)
    case pitchBend(UInt16, UInt8)
}

enum MIDIMessageParser {
    static func messages(in bytes: [UInt8]) -> [MIDIMessage] {
        var result: [MIDIMessage] = []
        var runningStatus: UInt8?
        var index = 0
        while index < bytes.count {
            if bytes[index] & 0x80 != 0 {
                guard bytes[index] < 0xF0 else { index += 1; runningStatus = nil; continue }
                runningStatus = bytes[index]
                index += 1
            }
            guard let status = runningStatus else { index += 1; continue }
            let kind = status & 0xF0
            let length = kind == 0xC0 || kind == 0xD0 ? 1 : 2
            guard index + length <= bytes.count else { break }
            let first = bytes[index]
            let second = length == 2 ? bytes[index + 1] : 0
            guard first < 0x80, second < 0x80 else { runningStatus = nil; continue }
            index += length
            let channel = status & 0x0F
            switch kind {
            case 0x80: result.append(.noteOff(first, channel))
            case 0x90: result.append(second == 0 ? .noteOff(first, channel) : .noteOn(first, second, channel))
            case 0xB0: result.append(.control(first, second, channel))
            case 0xE0: result.append(.pitchBend(UInt16(first) | UInt16(second) << 7, channel))
            default: break
            }
        }
        return result
    }

}

@MainActor
final class MIDIService: ObservableObject {
    static let shared = MIDIService()

    @Published private(set) var sourceNames: [String] = []
    @Published private(set) var notes: [LiveMIDINote] = []
    @Published private(set) var activeSessionID: UUID?
    @Published private(set) var errorMessage: String?

    nonisolated(unsafe) private static let notify: MIDINotifyBlock = { _ in
        Task { @MainActor in shared.refresh() }
    }
    nonisolated(unsafe) static let read: MIDIReadBlock = { list, _ in
        let messages = packetMessages(in: list)
        Task { @MainActor in shared.receive(messages) }
    }

    private static let logger = Logger(subsystem: "de.xviz.Chordflow", category: "midi")
    private let engine = AVAudioEngine()
    private let sampler = AVAudioUnitSampler()
    private var client = MIDIClientRef()
    private var port = MIDIPortRef()
    private var endpoints: [MIDIEndpointRef] = []
    private var notesByID: [Int: LiveMIDINote] = [:]
    private var started = false
    private var preparedAudio = false

    private init() {
        engine.attach(sampler)
        engine.connect(sampler, to: engine.mainMixerNode, format: nil)
    }

    func start() {
        if started { refresh(); return }
        guard MIDIClientCreateWithBlock("Chordflow MIDI" as CFString, &client, Self.notify) == noErr,
              MIDIInputPortCreateWithBlock(client, "Chordflow Input" as CFString, &port, Self.read) == noErr else {
            report("CoreMIDI konnte nicht gestartet werden.")
            return
        }
        started = true
        refresh()
    }

    @discardableResult
    func activate(_ sessionID: UUID, reportsMissingInput: Bool = false) -> Bool {
        if activeSessionID == sessionID { return true }
        if !started || sourceNames.isEmpty { start() }
        guard !sourceNames.isEmpty else {
            if reportsMissingInput { report("Kein MIDI-Eingang gefunden.") }
            return false
        }
        do {
            try prepareAudio()
            stopNotes()
            activeSessionID = sessionID
            errorMessage = nil
            return true
        } catch {
            report("Klangerzeugung konnte nicht gestartet werden: \(error.localizedDescription)")
            return false
        }
    }

    func deactivate(_ sessionID: UUID) {
        guard activeSessionID == sessionID else { return }
        stopNotes()
        activeSessionID = nil
    }

    func isActive(_ sessionID: UUID) -> Bool { activeSessionID == sessionID }

    private func refresh() {
        endpoints.forEach { MIDIPortDisconnectSource(port, $0) }
        endpoints = []
        var names: [String] = []
        for index in 0..<MIDIGetNumberOfSources() {
            let endpoint = MIDIGetSource(index)
            guard endpoint != 0, MIDIPortConnectSource(port, endpoint, nil) == noErr else { continue }
            endpoints.append(endpoint)
            names.append(Self.name(of: endpoint) ?? "MIDI-Eingang \(index + 1)")
        }
        sourceNames = names
        Self.logger.info("MIDI-Eingänge: \(names.joined(separator: ", "), privacy: .public)")
        if names.isEmpty, activeSessionID != nil {
            stopNotes()
            activeSessionID = nil
            report("Der aktive MIDI-Eingang wurde getrennt.")
        }
    }

    private func prepareAudio() throws {
        if !preparedAudio {
            let bank = URL(fileURLWithPath: "/System/Library/Components/CoreAudio.component/Contents/Resources/gs_instruments.dls")
            try sampler.loadSoundBankInstrument(at: bank, program: 0, bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB), bankLSB: UInt8(kAUSampler_DefaultBankLSB))
            preparedAudio = true
        }
        guard !engine.isRunning else { return }
        engine.prepare()
        try engine.start()
    }

    private func receive(_ messages: [MIDIMessage]) {
        guard activeSessionID != nil else { return }
        for message in messages {
            switch message {
            case .noteOn(let note, let velocity, let channel):
                sampler.startNote(note, withVelocity: velocity, onChannel: channel)
                let value = LiveMIDINote(number: note, velocity: velocity, channel: channel)
                notesByID[value.id] = value
            case .noteOff(let note, let channel):
                sampler.stopNote(note, onChannel: channel)
                notesByID[Int(channel) * 128 + Int(note)] = nil
            case .control(let number, let value, let channel): sampler.sendController(number, withValue: value, onChannel: channel)
            case .pitchBend(let value, let channel): sampler.sendPitchBend(value, onChannel: channel)
            }
        }
        notes = notesByID.values.sorted { $0.number < $1.number }
    }

    private func stopNotes() {
        for channel in UInt8(0)...15 { sampler.sendController(123, withValue: 0, onChannel: channel) }
        notesByID = [:]
        notes = []
    }

    private func report(_ text: String) {
        Self.logger.error("\(text, privacy: .public)")
        errorMessage = text
    }

    nonisolated static func packetMessages(in list: UnsafePointer<MIDIPacketList>) -> [MIDIMessage] {
        withUnsafePointer(to: list.pointee.packet) { first in
            var packet = UnsafeMutablePointer(mutating: first)
            var result: [MIDIMessage] = []
            for index in 0..<list.pointee.numPackets {
                let bytes = withUnsafeBytes(of: packet.pointee.data) { Array($0.prefix(Int(packet.pointee.length))) }
                result += MIDIMessageParser.messages(in: bytes)
                if index + 1 < list.pointee.numPackets { packet = MIDIPacketNext(packet) }
            }
            return result
        }
    }

    nonisolated private static func name(of endpoint: MIDIEndpointRef) -> String? {
        var value: Unmanaged<CFString>?
        guard MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }
}

enum MusicNames {
    static func note(_ midi: UInt8) -> String {
        let names = ["C", "C♯", "D", "E♭", "E", "F", "F♯", "G", "A♭", "A", "B♭", "H"]
        return "\(names[Int(midi) % 12])\(Int(midi) / 12 - 1)"
    }
}
