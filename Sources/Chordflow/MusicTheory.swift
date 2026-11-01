import Foundation

enum ScaleKind: String, CaseIterable, Identifiable, Sendable {
    case major, naturalMinor, harmonicMinor, melodicMinor, dorian, mixolydian, majorPentatonic, minorPentatonic, blues

    var id: String { rawValue }
    var title: String {
        switch self {
        case .major: "Dur"
        case .naturalMinor: "Natürlich Moll"
        case .harmonicMinor: "Harmonisch Moll"
        case .melodicMinor: "Melodisch Moll"
        case .dorian: "Dorisch"
        case .mixolydian: "Mixolydisch"
        case .majorPentatonic: "Dur-Pentatonik"
        case .minorPentatonic: "Moll-Pentatonik"
        case .blues: "Blues"
        }
    }
    var intervals: [Int] {
        switch self {
        case .major: [0, 2, 4, 5, 7, 9, 11]
        case .naturalMinor: [0, 2, 3, 5, 7, 8, 10]
        case .harmonicMinor: [0, 2, 3, 5, 7, 8, 11]
        case .melodicMinor: [0, 2, 3, 5, 7, 9, 11]
        case .dorian: [0, 2, 3, 5, 7, 9, 10]
        case .mixolydian: [0, 2, 4, 5, 7, 9, 10]
        case .majorPentatonic: [0, 2, 4, 7, 9]
        case .minorPentatonic: [0, 3, 5, 7, 10]
        case .blues: [0, 3, 5, 6, 7, 10]
        }
    }
}

enum ChordQuality: String, CaseIterable, Identifiable, Sendable {
    case major, minor, diminished, augmented, dominant7, major7, minor7, suspended2, suspended4
    var id: String { rawValue }
    var title: String {
        switch self {
        case .major: "Dur"
        case .minor: "Moll"
        case .diminished: "Vermindert"
        case .augmented: "Übermäßig"
        case .dominant7: "Dominantseptakkord"
        case .major7: "Großer Septakkord"
        case .minor7: "Mollseptakkord"
        case .suspended2: "Sus2"
        case .suspended4: "Sus4"
        }
    }
    var suffix: String {
        switch self { case .major: ""; case .minor: "m"; case .diminished: "dim"; case .augmented: "+"; case .dominant7: "7"; case .major7: "maj7"; case .minor7: "m7"; case .suspended2: "sus2"; case .suspended4: "sus4" }
    }
    var intervals: [Int] {
        switch self { case .major: [0,4,7]; case .minor: [0,3,7]; case .diminished: [0,3,6]; case .augmented: [0,4,8]; case .dominant7: [0,4,7,10]; case .major7: [0,4,7,11]; case .minor7: [0,3,7,10]; case .suspended2: [0,2,7]; case .suspended4: [0,5,7] }
    }
}

struct TheoryChord: Equatable, Sendable {
    var root: Int
    var quality: ChordQuality
    var pitches: [Int]

    init(root: Int, quality: ChordQuality, pitches: [Int]? = nil) {
        self.root = MusicTheory.normalized(root)
        self.quality = quality
        self.pitches = pitches ?? quality.intervals.map { 60 + MusicTheory.normalized(root) + $0 }
        self.pitches.sort()
    }
    var symbol: String { MusicTheory.noteName(root) + quality.suffix }
    var intervalLabels: [String] { pitches.map { MusicTheory.intervalName(MusicTheory.normalized($0 - root)) } }
}

struct ChordEvent: Identifiable, Equatable, Sendable {
    let id: Int64
    let sceneID: Int64
    var position: Int
    var root: Int
    var quality: ChordQuality
    var pitches: [Int]
    var beats: Int
    var bassPitch: Int? = nil
    var chord: TheoryChord { TheoryChord(root: root, quality: quality, pitches: pitches) }
}

enum ToneRole: Equatable, Sendable {
    case chordTone, chordColor, common, scene, track, tension
}

struct ToneAnalysis: Equatable, Sendable {
    let role: ToneRole
    let title: String
    let explanation: String
}

struct VoiceLeadingAnalysis: Equatable, Sendable {
    let commonPitchClasses: [Int]
    let semitoneMoves: [(from: Int, to: Int)]

    static func == (lhs: VoiceLeadingAnalysis, rhs: VoiceLeadingAnalysis) -> Bool {
        lhs.commonPitchClasses == rhs.commonPitchClasses && lhs.semitoneMoves.map { [$0.from, $0.to] } == rhs.semitoneMoves.map { [$0.from, $0.to] }
    }
}

enum ChordVoicingRole: String, Equatable, Sendable { case standard, inversion, altered }

struct ChordVoicingAnalysis: Equatable, Sendable {
    let role: ChordVoicingRole
    let description: String
    var isAltered: Bool { role == .altered }
}

enum ABCNoteEditor {
    static func replacingNote(in source: String, eventIndex: Int, pitchIndex: Int, with midi: Int) -> String? {
        let characters = Array(source)
        var event = 0, index = 0
        var quoted = false
        while index < characters.count {
            if characters[index] == "\"" { quoted.toggle(); index += 1; continue }
            if quoted { index += 1; continue }
            if characters[index] == "[", let end = characters[(index + 1)...].firstIndex(of: "]") {
                let contentStart = index + 1
                if contentStart < end, characters[contentStart] != "V", characters[contentStart] != "P" {
                    let ranges = noteRanges(in: characters, from: contentStart, to: end)
                    if !ranges.isEmpty {
                        if event == eventIndex, ranges.indices.contains(pitchIndex) { return replacing(characters, range: ranges[pitchIndex], with: MusicTheory.abcNote(midi)) }
                        event += 1
                    }
                }
                index = end + 1; continue
            }
            if let range = noteRange(in: characters, at: index, limit: characters.count) {
                if event == eventIndex, pitchIndex == 0 { return replacing(characters, range: range, with: MusicTheory.abcNote(midi)) }
                event += 1; index = range.upperBound; continue
            }
            index += 1
        }
        return nil
    }

    private static func noteRanges(in characters: [Character], from start: Int, to end: Int) -> [Range<Int>] {
        var result: [Range<Int>] = [], index = start
        while index < end {
            if let range = noteRange(in: characters, at: index, limit: end) { result.append(range); index = range.upperBound }
            else { index += 1 }
        }
        return result
    }

    private static func noteRange(in characters: [Character], at start: Int, limit: Int) -> Range<Int>? {
        var index = start
        while index < limit, "^_=".contains(characters[index]) { index += 1 }
        guard index < limit, "ABCDEFGabcdefg".contains(characters[index]) else { return nil }
        index += 1
        while index < limit, characters[index] == "," || characters[index] == "'" { index += 1 }
        return start..<index
    }

    private static func replacing(_ characters: [Character], range: Range<Int>, with replacement: String) -> String {
        String(characters[..<range.lowerBound]) + replacement + String(characters[range.upperBound...])
    }
}

enum MusicTheory {
    enum StaffClef: Equatable { case treble, bass }
    static let sharpNames = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "H"]
    static let flatNames = ["C", "D♭", "D", "E♭", "E", "F", "G♭", "G", "A♭", "A", "B", "H"]
    static let circleRoots = [0, 7, 2, 9, 4, 11, 6, 1, 8, 3, 10, 5]

    static func normalized(_ value: Int) -> Int { (value % 12 + 12) % 12 }
    static func noteName(_ pitchClass: Int, prefersFlats: Bool = false) -> String { (prefersFlats ? flatNames : sharpNames)[normalized(pitchClass)] }
    static func pitchName(_ midi: Int, prefersFlats: Bool = false) -> String { "\(noteName(midi, prefersFlats: prefersFlats))\(midi / 12 - 1)" }
    static func scale(tonic: Int, kind: ScaleKind) -> [Int] { kind.intervals.map { normalized(tonic + $0) } }
    static func scaleNames(tonic: Int, kind: ScaleKind) -> [String] { scale(tonic: tonic, kind: kind).map { noteName($0, prefersFlats: prefersFlats(tonic: tonic)) } }
    static func contains(_ pitch: Int, tonic: Int, kind: ScaleKind) -> Bool { scale(tonic: tonic, kind: kind).contains(normalized(pitch)) }
    static func commonScaleTones(tonic: Int, kinds: [ScaleKind]) -> [Int] {
        guard let first = kinds.first else { return [] }
        return kinds.dropFirst().reduce(Set(scale(tonic: tonic, kind: first))) { result, kind in
            result.intersection(scale(tonic: tonic, kind: kind))
        }.sorted()
    }
    static func analyzeTone(_ pitch: Int, tonic: Int, sceneScale: ScaleKind, trackScale: ScaleKind, chord: TheoryChord?) -> ToneAnalysis {
        let inScene = contains(pitch, tonic: tonic, kind: sceneScale)
        let inTrack = contains(pitch, tonic: tonic, kind: trackScale)
        let inChord = chord?.pitches.contains { normalized($0) == normalized(pitch) } ?? false
        let name = noteName(pitch, prefersFlats: prefersFlats(tonic: tonic))
        if inChord, let chord {
            let interval = intervalName(normalized(pitch - chord.root))
            if inScene && inTrack {
                return ToneAnalysis(role: .chordTone, title: "Akkordton", explanation: "\(name) ist die \(interval) von \(chord.symbol) und liegt zugleich in Szenen- und Spurtonleiter.")
            }
            let missing = !inScene && !inTrack ? "Szenen- und Spurtonleiter" : !inScene ? "Szenentonleiter" : "Spurtonleiter"
            return ToneAnalysis(role: .chordColor, title: "Akkordfarbe", explanation: "\(name) liegt außerhalb der \(missing), ist aber als \(interval) von \(chord.symbol) harmonisch erklärt.")
        }
        if inScene && inTrack {
            return ToneAnalysis(role: .common, title: "Gemeinsamer Ton", explanation: "\(name) gehört zur Szenen- und Spurtonleiter und eignet sich als stabiler Verbindungston.")
        }
        if inScene {
            return ToneAnalysis(role: .scene, title: "Szenenton", explanation: "\(name) gehört zum gemeinsamen Szenenklang, liegt aber außerhalb der gewählten Spurtonleiter.")
        }
        if inTrack {
            return ToneAnalysis(role: .track, title: "Spurton", explanation: "\(name) gehört zur Spurtonleiter, erweitert aber den gemeinsamen Szenenklang.")
        }
        return ToneAnalysis(role: .tension, title: "Offene Spannung", explanation: "\(name) gehört weder zum aktuellen Akkord noch zur Szenen- oder Spurtonleiter. Entscheidend ist seine Auflösung in den nächsten Ton.")
    }
    static func voiceLeading(from source: TheoryChord, to destination: TheoryChord) -> VoiceLeadingAnalysis {
        let sourceClasses = Set(source.pitches.map(normalized))
        let destinationClasses = Set(destination.pitches.map(normalized))
        let common = sourceClasses.intersection(destinationClasses).sorted()
        var moves: [(Int, Int)] = []
        for pitch in sourceClasses.subtracting(common).sorted() {
            let targets = destinationClasses.subtracting(common).filter { target in
                let distance = abs(target - pitch)
                return min(distance, 12 - distance) == 1
            }
            if let target = targets.sorted().first { moves.append((pitch, target)) }
        }
        return VoiceLeadingAnalysis(commonPitchClasses: common, semitoneMoves: moves)
    }
    static func analyzeVoicing(_ chord: TheoryChord, prefersFlats: Bool = false) -> ChordVoicingAnalysis {
        let expected = Set(chord.quality.intervals.map { normalized(chord.root + $0) })
        let actual = Set(chord.pitches.map(normalized))
        let added = actual.subtracting(expected).sorted()
        let missing = expected.subtracting(actual).sorted()
        let range = chord.pitches.sorted()
        let rangeText = range.first.map { low in
            let high = range.last ?? low
            return "Lage \(pitchName(low, prefersFlats: prefersFlats))–\(pitchName(high, prefersFlats: prefersFlats))"
        } ?? "Leeres Voicing"

        if !added.isEmpty || !missing.isEmpty {
            let change: String
            if added.count == 1, missing.count == 1 {
                change = "\(noteName(added[0], prefersFlats: prefersFlats)) statt \(noteName(missing[0], prefersFlats: prefersFlats))"
            } else {
                let additions = added.isEmpty ? nil : "hinzu: \(added.map { noteName($0, prefersFlats: prefersFlats) }.joined(separator: ", "))"
                let removals = missing.isEmpty ? nil : "fehlt: \(missing.map { noteName($0, prefersFlats: prefersFlats) }.joined(separator: ", "))"
                change = [additions, removals].compactMap { $0 }.joined(separator: " · ")
            }
            return ChordVoicingAnalysis(role: .altered, description: "Variante: \(change) · \(rangeText)")
        }

        let bassInterval = chord.pitches.first.map { normalized($0 - chord.root) }
        let inversion = bassInterval.flatMap { chord.quality.intervals.firstIndex(of: $0) }
        let position = inversion == 0 ? "Grundstellung" : inversion.map { "\($0). Umkehrung" } ?? "Eigenes Voicing"
        let role: ChordVoicingRole = inversion == 0 ? .standard : .inversion
        return ChordVoicingAnalysis(role: role, description: "\(position) · \(rangeText)")
    }
    static func nearestScalePitch(to pitch: Int, tonic: Int, kind: ScaleKind) -> Int {
        guard !contains(pitch, tonic: tonic, kind: kind) else { return pitch }
        for distance in 1...6 {
            if contains(pitch - distance, tonic: tonic, kind: kind) { return pitch - distance }
            if contains(pitch + distance, tonic: tonic, kind: kind) { return pitch + distance }
        }
        return pitch
    }
    static func invertedVoicing(_ pitches: [Int], upward: Bool) -> [Int] {
        guard !pitches.isEmpty else { return [] }
        var result = pitches.sorted()
        if upward { result[0] += 12 } else { result[result.count - 1] -= 12 }
        result.sort()
        while result.max() ?? 0 > 84 { result = result.map { $0 - 12 } }
        while result.min() ?? 127 < 36 { result = result.map { $0 + 12 } }
        return result
    }
    static func preferredClef(for pitches: [Int]) -> StaffClef {
        (pitches.max() ?? 60) >= 60 ? .treble : .bass
    }
    static func prefersFlats(tonic: Int) -> Bool { [1, 3, 5, 8, 10].contains(normalized(tonic)) }
    static func intervalName(_ semitones: Int) -> String { [0:"1",1:"♭2",2:"2",3:"♭3",4:"3",5:"4",6:"♭5",7:"5",8:"♭6",9:"6",10:"♭7",11:"7"][normalized(semitones)] ?? "?" }
    static func romanDegree(root: Int, tonic: Int, kind: ScaleKind) -> String? {
        guard let index = scale(tonic: tonic, kind: kind).firstIndex(of: normalized(root)) else { return nil }
        let values = ["I", "II", "III", "IV", "V", "VI", "VII"]
        return index < values.count ? values[index] : nil
    }
    static func abcNote(_ midi: Int) -> String {
        let names = ["C", "^C", "D", "^D", "E", "F", "^F", "G", "^G", "A", "^A", "B"]
        let base = names[normalized(midi)]
        let octave = midi / 12 - 1
        if octave < 4 { return base + String(repeating: ",", count: 4 - octave) }
        if octave == 4 { return base }
        return base.lowercased() + String(repeating: "'", count: max(0, octave - 5))
    }
    static func abcKey(tonic: Int, kind: ScaleKind) -> String {
        noteName(tonic, prefersFlats: prefersFlats(tonic: tonic)).replacingOccurrences(of: "♯", with: "#").replacingOccurrences(of: "♭", with: "b") + (kind == .naturalMinor ? "m" : "")
    }
}
