import CoreMIDI
import XCTest
@testable import Chordflow

final class ChordflowTests: XCTestCase {
    func testNewScoreHasSceneAndThreeDefaultTracks() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".sqlite3")
        defer { try? FileManager.default.removeItem(at: url) }
        let database = try ScoreDatabase(url: url)
        let scoreID = try database.createScore(title: "Live Set")
        let scenes = try database.scenes(scoreID: scoreID)
        XCTAssertEqual(scenes.map(\.title), ["Szene 1"])
        XCTAssertEqual(try database.tracks(sceneID: XCTUnwrap(scenes.first?.id)).map(\.name), ["Bass", "Melodie", "Akkorde"])
    }

    func testDatabasePersistsScoreUpdates() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".sqlite3")
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            let database = try ScoreDatabase(url: url)
            let id = try database.createScore()
            try database.updateScore(id: id, title: "Festival")
        }
        XCTAssertEqual(try ScoreDatabase(url: url).scores().first?.title, "Festival")
    }

    func testABCBuilderCombinesAllTracksAsVoices() {
        let score = Score(id: 1, title: "Set")
        let scene = ScoreScene(id: 2, scoreID: 1, title: "Intro", tempo: 128, position: 0)
        let tracks = ScoreDefaults.trackNames.enumerated().map { ScoreTrack(id: Int64($0.offset), sceneID: 2, name: $0.element, abc: ScoreDefaults.trackABC[$0.offset], position: $0.offset) }
        let abc = ABCScoreBuilder.build(score: score, scene: scene, tracks: tracks)
        XCTAssertTrue(abc.contains("Q:1/4=128"))
        XCTAssertEqual(abc.components(separatedBy: "V:v").count - 1, 3)
        XCTAssertTrue(abc.contains("V:v1 name=\"Bass\" subname=\"Akkordе\" clef=bass"))
        XCTAssertTrue(abc.contains("V:v2 name=\"Melodie\" subname=\"Akkordе\" clef=treble"))
    }

    func testScaleAndChordTheory() {
        XCTAssertEqual(MusicTheory.scaleNames(tonic: 0, kind: .major), ["C", "D", "E", "F", "G", "A", "H"])
        XCTAssertEqual(MusicTheory.scaleNames(tonic: 9, kind: .naturalMinor), ["A", "H", "C", "D", "E", "F", "G"])
        let chord = TheoryChord(root: 0, quality: .major7)
        XCTAssertEqual(chord.symbol, "Cmaj7")
        XCTAssertEqual(chord.intervalLabels, ["1", "3", "5", "7"])
    }

    func testToneAnalysisExplainsSharedChordAndTensionRoles() {
        let chord = TheoryChord(root: 9, quality: .major, pitches: [69, 73, 76])
        XCTAssertEqual(MusicTheory.commonScaleTones(tonic: 9, kinds: [.blues, .minorPentatonic]), [0, 2, 4, 7, 9])
        XCTAssertEqual(MusicTheory.analyzeTone(69, tonic: 9, sceneScale: .blues, trackScale: .minorPentatonic, chord: chord).role, .chordTone)
        XCTAssertEqual(MusicTheory.analyzeTone(73, tonic: 9, sceneScale: .blues, trackScale: .minorPentatonic, chord: chord).role, .chordColor)
        XCTAssertEqual(MusicTheory.analyzeTone(71, tonic: 9, sceneScale: .blues, trackScale: .minorPentatonic, chord: chord).role, .tension)
    }

    func testVoiceLeadingFindsCommonTonesAndSemitoneResolutions() {
        let cMajor = TheoryChord(root: 0, quality: .major, pitches: [60, 64, 67])
        let fMajor = TheoryChord(root: 5, quality: .major, pitches: [60, 65, 69])
        let analysis = MusicTheory.voiceLeading(from: cMajor, to: fMajor)

        XCTAssertEqual(analysis.commonPitchClasses, [0])
        XCTAssertEqual(analysis.semitoneMoves.map { [$0.from, $0.to] }, [[4, 5]])
    }

    func testChordEventsPersistAndDriveABCChordTrack() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".sqlite3")
        defer { try? FileManager.default.removeItem(at: url) }
        let database = try ScoreDatabase(url: url)
        let scoreID = try database.createScore(title: "Theorie")
        let scene = try XCTUnwrap(database.scenes(scoreID: scoreID).first)
        _ = try database.addChord(sceneID: scene.id, chord: TheoryChord(root: 7, quality: .dominant7))
        let events = try database.chordEvents(sceneID: scene.id)
        XCTAssertEqual(events.first?.chord.symbol, "G7")
        let abc = ABCScoreBuilder.build(score: Score(id: scoreID, title: "Theorie"), scene: scene, tracks: try database.tracks(sceneID: scene.id), chords: events)
        XCTAssertTrue(abc.contains("\"G7\"[GBdf]4 |"))
    }

    func testChordCanBeInsertedAtExplicitScenePosition() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".sqlite3")
        defer { try? FileManager.default.removeItem(at: url) }
        let database = try ScoreDatabase(url: url)
        let scoreID = try database.createScore()
        let scene = try XCTUnwrap(database.scenes(scoreID: scoreID).first)
        _ = try database.addChord(sceneID: scene.id, chord: TheoryChord(root: 0, quality: .major))
        _ = try database.addChord(sceneID: scene.id, chord: TheoryChord(root: 7, quality: .major))
        _ = try database.addChord(sceneID: scene.id, chord: TheoryChord(root: 5, quality: .major), at: 1)
        let events = try database.chordEvents(sceneID: scene.id)
        XCTAssertEqual(events.map(\.chord.symbol), ["C", "F", "G"])
        XCTAssertEqual(events.map(\.position), [0, 1, 2])
    }

    func testSceneAndTrackScaleChoicesPersist() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".sqlite3")
        defer { try? FileManager.default.removeItem(at: url) }
        let database = try ScoreDatabase(url: url)
        let scoreID = try database.createScore()
        var scene = try XCTUnwrap(database.scenes(scoreID: scoreID).first)
        scene.tonic = 2; scene.scale = .dorian; try database.updateScene(scene)
        var track = try XCTUnwrap(database.tracks(sceneID: scene.id).first)
        track.scaleOverride = .minorPentatonic; try database.updateTrack(track, scoreID: scoreID)
        XCTAssertEqual(try database.scenes(scoreID: scoreID).first?.scale, .dorian)
        XCTAssertEqual(try database.tracks(sceneID: scene.id).first?.scaleOverride, .minorPentatonic)
    }

    func testScaleSnappingUsesNearestLowerToneOnTie() {
        XCTAssertEqual(MusicTheory.nearestScalePitch(to: 61, tonic: 0, kind: .major), 60)
        XCTAssertEqual(MusicTheory.nearestScalePitch(to: 66, tonic: 0, kind: .major), 65)
        XCTAssertEqual(MusicTheory.nearestScalePitch(to: 64, tonic: 0, kind: .major), 64)
    }

    func testRepeatedInversionsRemainInVisibleRegister() {
        let originalClasses = Set([60, 64, 67].map(MusicTheory.normalized))
        var upward = [60, 64, 67]
        var downward = upward
        for _ in 0..<18 {
            upward = MusicTheory.invertedVoicing(upward, upward: true)
            downward = MusicTheory.invertedVoicing(downward, upward: false)
            XCTAssertTrue(upward.allSatisfy { (36...84).contains($0) })
            XCTAssertTrue(downward.allSatisfy { (36...84).contains($0) })
            XCTAssertEqual(Set(upward.map(MusicTheory.normalized)), originalClasses)
            XCTAssertEqual(Set(downward.map(MusicTheory.normalized)), originalClasses)
        }
    }

    func testClefFollowsVoicingRange() {
        XCTAssertEqual(MusicTheory.preferredClef(for: [48, 52, 55]), .bass)
        XCTAssertEqual(MusicTheory.preferredClef(for: [55, 60, 64]), .treble)
        XCTAssertEqual(MusicTheory.preferredClef(for: [60, 64, 67]), .treble)
        let scene = ScoreScene(id: 1, scoreID: 1, title: "Test", tempo: 120, position: 0)
        XCTAssertTrue(ABCScoreBuilder.singleChord(TheoryChord(root: 0, quality: .major, pitches: [48, 52, 55]), scene: scene).contains("V:chord clef=bass"))
        XCTAssertTrue(ABCScoreBuilder.singleChord(TheoryChord(root: 0, quality: .major, pitches: [60, 64, 67]), scene: scene).contains("V:chord clef=treble"))
    }

    func testSingleChordSeparatesForeignTonesIntoColoredVoice() {
        let scene = ScoreScene(id: 2, scoreID: 1, title: "Intro", tempo: 120, position: 0, tonic: 0, scale: .major)
        let abc = ABCScoreBuilder.singleChord(TheoryChord(root: 2, quality: .major7, pitches: [57, 61, 62, 66]), scene: scene)
        XCTAssertTrue(abc.contains("%%score ( chord foreign )"))
        XCTAssertTrue(abc.contains("%%voicecolor orange"))
        XCTAssertTrue(abc.contains("[V:foreign] [^C^F]4"))
    }

    func testABCNoteEditorReplacesSingleAndChordNotes() {
        XCTAssertEqual(ABCNoteEditor.replacingNote(in: "C D E G |", eventIndex: 1, pitchIndex: 0, with: 63), "C ^D E G |")
        XCTAssertEqual(ABCNoteEditor.replacingNote(in: "[CEG]4 |", eventIndex: 0, pitchIndex: 1, with: 65), "[CFG]4 |")
    }

    func testCustomBassPitchPersistsAndDrivesScore() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".sqlite3")
        defer { try? FileManager.default.removeItem(at: url) }
        let database = try ScoreDatabase(url: url)
        let scoreID = try database.createScore()
        let scene = try XCTUnwrap(database.scenes(scoreID: scoreID).first)
        _ = try database.addChord(sceneID: scene.id, chord: TheoryChord(root: 0, quality: .major))
        var event = try XCTUnwrap(database.chordEvents(sceneID: scene.id).first)
        event.bassPitch = 37; try database.updateChord(event)
        let persisted = try XCTUnwrap(database.chordEvents(sceneID: scene.id).first)
        XCTAssertEqual(persisted.bassPitch, 37)
        let abc = ABCScoreBuilder.build(score: Score(id: scoreID, title: "Set"), scene: scene, tracks: try database.tracks(sceneID: scene.id), chords: [persisted])
        XCTAssertTrue(abc.contains("^C,,4 |"))
    }

    func testTrackEndModePersistsAndFitsSceneTimeline() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".sqlite3")
        defer { try? FileManager.default.removeItem(at: url) }
        let database = try ScoreDatabase(url: url)
        let scoreID = try database.createScore()
        let scene = try XCTUnwrap(database.scenes(scoreID: scoreID).first)
        var melody = try XCTUnwrap(database.tracks(sceneID: scene.id).first { $0.name == "Melodie" })
        melody.endMode = .loop; try database.updateTrack(melody, scoreID: scoreID)
        XCTAssertEqual(try database.tracks(sceneID: scene.id).first { $0.id == melody.id }?.endMode, .loop)
        XCTAssertEqual(ABCTrackTiming.duration(of: "C D E G |"), 4)
        XCTAssertEqual(ABCTrackTiming.duration(of: ABCTrackTiming.fitted("C D E G |", to: 10, mode: .loop)), 10)
        XCTAssertEqual(ABCTrackTiming.fitted("C D E G |", to: 6, mode: .pad), "C D E G | z2 |")
        XCTAssertEqual(ABCTrackTiming.fitted("C D E G |", to: 16, mode: .pad), "C D E G | z4 | z4 | z4 |")
    }

    func testChordProgressionGeneratesChordAndBassVoices() throws {
        let score = Score(id: 1, title: "Set")
        let scene = ScoreScene(id: 2, scoreID: 1, title: "Intro", tempo: 120, position: 0)
        let tracks = ScoreDefaults.trackNames.enumerated().map { ScoreTrack(id: Int64($0.offset), sceneID: 2, name: $0.element, abc: ScoreDefaults.trackABC[$0.offset], position: $0.offset) }
        let event = ChordEvent(id: 1, sceneID: 2, position: 0, root: 0, quality: .major, pitches: [60, 64, 67], beats: 4)
        let abc = ABCScoreBuilder.build(score: score, scene: scene, tracks: tracks, chords: [event])
        XCTAssertTrue(abc.contains("\"C\"[CEG]4 |"))
        XCTAssertTrue(abc.contains("C,,4 |"))
    }

    func testControlledChordTranspositionPreservesIntervals() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".sqlite3")
        defer { try? FileManager.default.removeItem(at: url) }
        let database = try ScoreDatabase(url: url)
        let scoreID = try database.createScore()
        let scene = try XCTUnwrap(database.scenes(scoreID: scoreID).first)
        _ = try database.addChord(sceneID: scene.id, chord: TheoryChord(root: 0, quality: .major7))
        try database.transposeChords(sceneID: scene.id, semitones: 2)
        let transposed = try XCTUnwrap(database.chordEvents(sceneID: scene.id).first)
        XCTAssertEqual(transposed.chord.symbol, "Dmaj7")
        XCTAssertEqual(transposed.pitches, [62, 66, 69, 73])
    }

    func testParserReadsRunningStatus() {
        XCTAssertEqual(MIDIMessageParser.messages(in: [0x91, 60, 100, 64, 90, 60, 0]), [.noteOn(60, 100, 1), .noteOn(64, 90, 1), .noteOff(60, 1)])
    }

    func testMultipleCoreMIDIPacketsUseOriginalListStorage() {
        var list = MIDIPacketList()
        withUnsafeMutablePointer(to: &list) { pointer in
            var packet = MIDIPacketListInit(pointer)
            for bytes: [UInt8] in [[0x90, 60, 100], [0x90, 64, 90]] {
                packet = bytes.withUnsafeBufferPointer { MIDIPacketListAdd(pointer, MemoryLayout<MIDIPacketList>.size, packet, 0, bytes.count, $0.baseAddress!) }
            }
            XCTAssertEqual(MIDIService.packetMessages(in: UnsafePointer(pointer)), [.noteOn(60, 100, 0), .noteOn(64, 90, 0)])
        }
    }
}
