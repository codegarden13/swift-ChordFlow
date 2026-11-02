import CoreMIDI
import MIDILiveKit
import MusicTheoryKit

typealias LiveMIDINote = MIDILiveNote
typealias MIDIService = MIDILiveService

enum MIDIMessage: Equatable, Sendable {
    case noteOn(UInt8, UInt8, UInt8)
    case noteOff(UInt8, UInt8)
    case control(UInt8, UInt8, UInt8)
    case pitchBend(UInt16, UInt8)

    init(_ message: MIDIChannelMessage) {
        switch message {
        case .noteOn(let note, let velocity, let channel): self = .noteOn(note, velocity, channel)
        case .noteOff(let note, let channel): self = .noteOff(note, channel)
        case .control(let number, let value, let channel): self = .control(number, value, channel)
        case .pitchBend(let value, let channel): self = .pitchBend(value, channel)
        }
    }
}

enum MIDIMessageParser {
    static func messages(in bytes: [UInt8]) -> [MIDIMessage] {
        MIDIChannelMessageParser.messages(in: bytes).map(MIDIMessage.init)
    }
}

extension MIDILiveService {
    var notes: [MIDILiveNote] { activeNotes }
    func activate(_ sessionID: UUID, reportsMissingInput: Bool = false) -> Bool {
        activate(sessionID: sessionID, reportsMissingInput: reportsMissingInput)
    }
    func isActive(_ sessionID: UUID) -> Bool { isActive(sessionID: sessionID) }
    func deactivate(_ sessionID: UUID) { deactivate(sessionID: sessionID) }
    nonisolated static func packetMessages(in list: UnsafePointer<MIDIPacketList>) -> [MIDIMessage] {
        messages(in: list).map(MIDIMessage.init)
    }
}

enum MusicNames {
    static func note(_ midi: UInt8) -> String {
        MusicTheoryKit.MusicTheory.noteLabel(midi: midi, naming: .german)
    }
}
