import CoreMIDI
import XCTest
@testable import Chordflow

final class ChordflowTests: XCTestCase {
    func testInitialDemoCreatesExactFourMinuteHouseScoreOnce() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".sqlite3")
        defer { try? FileManager.default.removeItem(at: url) }
        let database = try ScoreDatabase(url: url)

        let scoreID = try XCTUnwrap(database.createInitialDemoIfNeeded())
        let scene = try XCTUnwrap(database.scenes(scoreID: scoreID).first)
        let tracks = try database.tracks(sceneID: scene.id)
        let chords = try database.chordEvents(sceneID: scene.id)

        XCTAssertEqual(try database.scores().first?.title, ScoreDemo.title)
        XCTAssertEqual(scene.title, ScoreDemo.sceneTitle)
        XCTAssertEqual(scene.tempo, 124)
        XCTAssertEqual(scene.tonic, 9)
        XCTAssertEqual(scene.scale, .naturalMinor)
        XCTAssertEqual(ScoreDemo.durationSeconds, 240)
        XCTAssertEqual(tracks.map(\.name), ScoreDemo.trackNames)
        XCTAssertEqual(tracks.map { ABCTrackTiming.duration(of: $0.abc) }, [496, 496, 496])
        XCTAssertEqual(chords.reduce(0) { $0 + $1.beats }, 496)
        XCTAssertNil(try database.createInitialDemoIfNeeded())
    }

    func testTimelineScoreMapsEachYearToOneMeasureAndEachQuarterToOneBeat() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".sqlite3")
        defer { try? FileManager.default.removeItem(at: url) }
        let database = try ScoreDatabase(url: url)

        let scoreID = try database.createTimelineScore(title: "Projektgeschichte", startYear: 2020, endYear: 2022)
        let scene = try XCTUnwrap(database.scenes(scoreID: scoreID).first)
        let tracks = try database.tracks(sceneID: scene.id)

        XCTAssertEqual(scene.title, "2020–2022")
        XCTAssertEqual(tracks.map(\.name), ["Zeitachse", "Segmente", "Notizen"])
        XCTAssertEqual(tracks.map { ABCTrackTiming.duration(of: $0.abc) }, [12, 12, 12])
        XCTAssertTrue(tracks[0].abc.contains("\"_2020 · Q1\"x \"_Q2\"x \"_Q3\"x \"_Q4\"x |"))
        XCTAssertTrue(tracks.allSatisfy { $0.endMode == .independent })
    }

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

    func testVoicingAnalysisDistinguishesAlterationAndInversion() {
        let standard = TheoryChord(root: 11, quality: .major7, pitches: [71, 75, 78, 82])
        let altered = TheoryChord(root: 11, quality: .major7, pitches: [66, 70, 71, 74])
        let inversion = TheoryChord(root: 11, quality: .major7, pitches: [66, 70, 71, 75])

        XCTAssertEqual(MusicTheory.analyzeVoicing(standard).role, .standard)
        XCTAssertEqual(MusicTheory.analyzeVoicing(altered), ChordVoicingAnalysis(role: .altered, description: "Variante: D statt D♯ · Lage F♯4–D5"))
        XCTAssertEqual(MusicTheory.analyzeVoicing(inversion), ChordVoicingAnalysis(role: .inversion, description: "2. Umkehrung · Lage F♯4–D♯5"))
    }

    func testInversionDescriptionExplainsPositionUsingBassTone() {
        let root = TheoryChord(root: 0, quality: .major, pitches: [60, 64, 67])
        let first = TheoryChord(root: 0, quality: .major, pitches: [64, 67, 72])
        let second = TheoryChord(root: 0, quality: .major, pitches: [67, 72, 76])

        XCTAssertEqual(MusicTheory.inversionDescription(root), "Grundstellung · C liegt im Bass")
        XCTAssertEqual(MusicTheory.inversionDescription(first), "1. Umkehrung · E liegt im Bass")
        XCTAssertEqual(MusicTheory.inversionDescription(second), "2. Umkehrung · G liegt im Bass")
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

    func testChordCanStartAfterEmptyMeasuresWithoutMovingTimeline() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".sqlite3")
        defer { try? FileManager.default.removeItem(at: url) }
        let database = try ScoreDatabase(url: url)
        let scoreID = try database.createScore()
        let scene = try XCTUnwrap(database.scenes(scoreID: scoreID).first)

        _ = try database.addChord(sceneID: scene.id, chord: TheoryChord(root: 9, quality: .minor), atBeat: 41)
        let event = try XCTUnwrap(database.chordEvents(sceneID: scene.id).first)
        let abc = ABCScoreBuilder.build(score: Score(id: scoreID, title: "Zeitachse"), scene: scene, tracks: try database.tracks(sceneID: scene.id), chords: [event])

        XCTAssertEqual(event.startBeat, 41)
        XCTAssertEqual(ABCScoreBuilder.sceneBeats(tracks: [], chords: [event]), 45)
        XCTAssertTrue(abc.contains("z4 | z1 \"Am\"[Ace]3- | [Ace]1 z3 |"))
        XCTAssertThrowsError(try database.addChord(sceneID: scene.id, chord: TheoryChord(root: 0, quality: .major), atBeat: 42))
    }

    func testOccupiedMeasureCanBeSplitWithoutChangingFollowingTimeline() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".sqlite3")
        defer { try? FileManager.default.removeItem(at: url) }
        let database = try ScoreDatabase(url: url)
        let scoreID = try database.createScore()
        let scene = try XCTUnwrap(database.scenes(scoreID: scoreID).first)
        let eventID = try database.addChord(sceneID: scene.id, chord: TheoryChord(root: 0, quality: .major))
        var event = try XCTUnwrap(database.chordEvents(sceneID: scene.id).first)
        event.beats = 16
        try database.updateChord(event)

        try database.splitChordMeasure(eventID: eventID, measureStartBeat: 8, chord: TheoryChord(root: 2, quality: .minor), newChordFirst: false)
        let events = try database.chordEvents(sceneID: scene.id)

        XCTAssertEqual(events.map(\.chord.symbol), ["C", "C", "Dm", "C"])
        XCTAssertEqual(events.map(\.startBeat), [0, 8, 10, 12])
        XCTAssertEqual(events.map(\.beats), [8, 2, 2, 4])
        XCTAssertEqual(events.map(\.position), [0, 1, 2, 3])
    }

    @MainActor func testChordDraftRemainsTransientUntilExplicitSave() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".sqlite3")
        defer { try? FileManager.default.removeItem(at: url) }
        let database = try ScoreDatabase(url: url)
        let library = ScoreLibrary(database: database)
        let saved = try XCTUnwrap(library.chordEvents.first)
        var draft = saved
        draft.root = MusicTheory.normalized(saved.root + 1)
        draft.pitches = draft.pitches.map { $0 + 1 }

        library.stageChordDraft(draft)

        XCTAssertEqual(library.chordEvents.first?.root, saved.root)
        XCTAssertEqual(library.displayedChordEvents.first?.root, draft.root)
        XCTAssertEqual(library.displayedChordEvents.first?.isDraft, true)
        let score = try XCTUnwrap(library.selectedScore)
        let scene = try XCTUnwrap(library.selectedScene)
        let abc = ABCScoreBuilder.build(score: score, scene: scene, tracks: library.tracks, chords: library.displayedChordEvents)
        XCTAssertTrue(abc.contains("· Entwurf"))
        XCTAssertTrue(abc.contains("%%voicecolor lightgray"))
        XCTAssertTrue(abc.contains("[\(saved.pitches.map(MusicTheory.abcNote).joined())]"))
        XCTAssertTrue(library.saveChordDraft(id: saved.id))
        XCTAssertEqual(library.chordEvents.first?.root, draft.root)
        XCTAssertNil(library.chordDraft(id: saved.id))
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
