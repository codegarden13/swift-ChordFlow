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
    }

    func testScaleAndChordTheory() {
        XCTAssertEqual(MusicTheory.scaleNames(tonic: 0, kind: .major), ["C", "D", "E", "F", "G", "A", "H"])
        XCTAssertEqual(MusicTheory.scaleNames(tonic: 9, kind: .naturalMinor), ["A", "H", "C", "D", "E", "F", "G"])
        let chord = TheoryChord(root: 0, quality: .major7)
        XCTAssertEqual(chord.symbol, "Cmaj7")
        XCTAssertEqual(chord.intervalLabels, ["1", "3", "5", "7"])
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
