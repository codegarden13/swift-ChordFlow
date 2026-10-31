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
