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
    var chord: TheoryChord { TheoryChord(root: root, quality: quality, pitches: pitches) }
}

enum MusicTheory {
    static let sharpNames = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "H"]
    static let flatNames = ["C", "D♭", "D", "E♭", "E", "F", "G♭", "G", "A♭", "A", "B", "H"]
    static let circleRoots = [0, 7, 2, 9, 4, 11, 6, 1, 8, 3, 10, 5]

    static func normalized(_ value: Int) -> Int { (value % 12 + 12) % 12 }
    static func noteName(_ pitchClass: Int, prefersFlats: Bool = false) -> String { (prefersFlats ? flatNames : sharpNames)[normalized(pitchClass)] }
    static func pitchName(_ midi: Int, prefersFlats: Bool = false) -> String { "\(noteName(midi, prefersFlats: prefersFlats))\(midi / 12 - 1)" }
    static func scale(tonic: Int, kind: ScaleKind) -> [Int] { kind.intervals.map { normalized(tonic + $0) } }
    static func scaleNames(tonic: Int, kind: ScaleKind) -> [String] { scale(tonic: tonic, kind: kind).map { noteName($0, prefersFlats: prefersFlats(tonic: tonic)) } }
    static func contains(_ pitch: Int, tonic: Int, kind: ScaleKind) -> Bool { scale(tonic: tonic, kind: kind).contains(normalized(pitch)) }
    static func nearestScalePitch(to pitch: Int, tonic: Int, kind: ScaleKind) -> Int {
        guard !contains(pitch, tonic: tonic, kind: kind) else { return pitch }
        for distance in 1...6 {
            if contains(pitch - distance, tonic: tonic, kind: kind) { return pitch - distance }
            if contains(pitch + distance, tonic: tonic, kind: kind) { return pitch + distance }
        }
        return pitch
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
