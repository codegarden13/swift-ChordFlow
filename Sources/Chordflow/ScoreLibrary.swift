import Foundation
import OSLog
import SQLite3

struct Score: Identifiable, Equatable, Sendable { let id: Int64; var title: String }
struct ScoreScene: Identifiable, Equatable, Sendable { let id: Int64; let scoreID: Int64; var title: String; var tempo: Int; var position: Int; var tonic: Int = 0; var scale: ScaleKind = .major }
enum TrackEndMode: String, CaseIterable, Identifiable, Sendable {
    case pad, loop, once, independent
    var id: String { rawValue }
    var title: String {
        switch self { case .pad: "Mit Pausen auffüllen"; case .loop: "Motiv wiederholen"; case .once: "Einmal spielen"; case .independent: "Eigene Länge" }
    }
}

struct ScoreTrack: Identifiable, Equatable, Sendable { let id: Int64; let sceneID: Int64; var name: String; var abc: String; var position: Int; var scaleOverride: ScaleKind? = nil; var endMode: TrackEndMode = .pad }

enum ScoreDefaults {
    static let trackNames = ["Bass", "Melodie", "Akkorde"]
    static let trackABC = ["C,4 | F,4 | G,4 | C,4 |", "C D E G | A G E D |", "[CEG]4 | [FAc]4 | [GBd]4 | [CEG]4 |"]
}

enum TimelineScoreTemplate {
    static let trackNames = ["Zeitachse", "Segmente", "Notizen"]

    static func trackABC(startYear: Int, endYear: Int) -> [String] {
        let years = Array(startYear...endYear)
        let timeline = years.map { year in
            "\"_\(year) · Q1\"x \"_Q2\"x \"_Q3\"x \"_Q4\"x |"
        }.joined(separator: " ")
        let empty = years.map { _ in "x4 |" }.joined(separator: " ")
        return [timeline, empty, empty]
    }
}

enum ScoreDemo {
    static let title = "Neonlinien – House Demo"
    static let sceneTitle = "Four Minute Journey"
    static let tempo = 124
    static let measureCount = 124
    static let trackNames = ["Bass-Groove", "Lead", "Chord-Stabs"]

    static var durationSeconds: Int { measureCount * 4 * 60 / tempo }

    static let trackABC: [String] = {
        [bassMeasures, leadMeasures, chordMeasures].map { $0.joined(separator: " ") }
    }()

    static let harmony: [(root: Int, quality: ChordQuality, pitches: [Int], bass: Int)] = [
        (9, .minor, [57, 60, 64], 33),
        (5, .major7, [53, 57, 60, 64], 29),
        (0, .major, [55, 60, 64], 36),
        (7, .major, [55, 59, 62], 31),
    ]

    private static var bassMeasures: [String] {
        (0..<measureCount).map { measure in
            let chord = harmony[(measure / 4) % harmony.count]
            let root = MusicTheory.abcNote(chord.bass)
            let fifth = MusicTheory.abcNote(chord.bass + 7)
            if measure < 8 || measure >= 116 { return "\(root)2 z2 |" }
            if (56..<72).contains(measure) { return measure.isMultiple(of: 2) ? "\(root)4 |" : "z4 |" }
            return "\(root) z \(fifth) z |"
        }
    }

    private static var leadMeasures: [String] {
        let groove = ["z E A c |", "e2 d c |", "z E G A |", "c2 A G |"]
        let lift = ["A c e c |", "F A c A |", "G c e G |", "G B d B |"]
        let peak = ["e d c A |", "c A F A |", "G A c e |", "d B G E |"]
        return (0..<measureCount).map { measure in
            switch measure {
            case 0..<8: "z4 |"
            case 8..<40: groove[measure % groove.count]
            case 40..<56: lift[measure % lift.count]
            case 56..<64: measure.isMultiple(of: 2) ? "A4 |" : "z4 |"
            case 64..<72: ["A2 c2 |", "e4 |", "G2 A2 |", "B4 |"][measure % 4]
            case 72..<112: peak[measure % peak.count]
            case 112..<120: groove[measure % groove.count]
            default: "z4 |"
            }
        }
    }

    private static var chordMeasures: [String] {
        (0..<measureCount).map { measure in
            let chord = harmony[(measure / 4) % harmony.count]
            let tones = chord.pitches.map(MusicTheory.abcNote).joined()
            if measure < 4 || measure >= 120 { return "[\(tones)]4 |" }
            if (56..<64).contains(measure) { return measure.isMultiple(of: 2) ? "[\(tones)]4 |" : "z4 |" }
            return "z [\(tones)] z [\(tones)] |"
        }
    }
}

enum ScoreLibraryError: LocalizedError {
    case applicationSupportUnavailable, database(String), corruptData(String), invalidInput(String)
    var errorDescription: String? {
        switch self {
        case .applicationSupportUnavailable: "Der Speicherort für die Partituren ist nicht verfügbar."
        case let .database(message): "Die Partitur-Datenbank konnte nicht verwendet werden: \(message)"
        case let .corruptData(message): "Die Partitur-Datenbank enthält ungültige Daten: \(message)"
        case let .invalidInput(message): message
        }
    }
}

final class ScoreDatabase {
    private static let logger = Logger(subsystem: "de.xviz.Chordflow", category: "database")
    private let handle: OpaquePointer
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    convenience init() throws {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { throw ScoreLibraryError.applicationSupportUnavailable }
        let directory = support.appending(path: "Chordflow", directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try self.init(url: directory.appending(path: "scores.sqlite3"))
        } catch {
            Self.logger.error("SQLite-Speicher konnte nicht vorbereitet werden: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    init(url: URL) throws {
        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK, let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "Unbekannter SQLite-Fehler"
            if let database { sqlite3_close(database) }
            throw ScoreLibraryError.database(message)
        }
        handle = database
        do {
            try execute("PRAGMA foreign_keys = ON")
            try execute("PRAGMA journal_mode = WAL")
            try execute("""
                CREATE TABLE IF NOT EXISTS scores (id INTEGER PRIMARY KEY, title TEXT NOT NULL CHECK(length(trim(title)) > 0), created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP, updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP);
                CREATE TABLE IF NOT EXISTS scenes (id INTEGER PRIMARY KEY, score_id INTEGER NOT NULL REFERENCES scores(id) ON DELETE CASCADE, title TEXT NOT NULL CHECK(length(trim(title)) > 0), tempo INTEGER NOT NULL DEFAULT 120 CHECK(tempo BETWEEN 20 AND 400), position INTEGER NOT NULL);
                CREATE TABLE IF NOT EXISTS tracks (id INTEGER PRIMARY KEY, scene_id INTEGER NOT NULL REFERENCES scenes(id) ON DELETE CASCADE, name TEXT NOT NULL CHECK(length(trim(name)) > 0), abc TEXT NOT NULL, position INTEGER NOT NULL);
                CREATE TABLE IF NOT EXISTS app_metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL);
                CREATE INDEX IF NOT EXISTS scenes_score_position ON scenes(score_id, position);
                CREATE INDEX IF NOT EXISTS tracks_scene_position ON tracks(scene_id, position);
                """)
            if try !hasColumn("scenes", column: "tonic") { try execute("ALTER TABLE scenes ADD COLUMN tonic INTEGER NOT NULL DEFAULT 0 CHECK(tonic BETWEEN 0 AND 11)") }
            if try !hasColumn("scenes", column: "scale_kind") { try execute("ALTER TABLE scenes ADD COLUMN scale_kind TEXT NOT NULL DEFAULT 'major'") }
            if try !hasColumn("tracks", column: "scale_kind") { try execute("ALTER TABLE tracks ADD COLUMN scale_kind TEXT") }
            if try !hasColumn("tracks", column: "end_mode") { try execute("ALTER TABLE tracks ADD COLUMN end_mode TEXT NOT NULL DEFAULT 'pad'") }
            try execute("""
                CREATE TABLE IF NOT EXISTS chord_events (
                    id INTEGER PRIMARY KEY,
                    scene_id INTEGER NOT NULL REFERENCES scenes(id) ON DELETE CASCADE,
                    position INTEGER NOT NULL,
                    root INTEGER NOT NULL CHECK(root BETWEEN 0 AND 11),
                    quality TEXT NOT NULL,
                    pitches TEXT NOT NULL,
                    beats INTEGER NOT NULL DEFAULT 4 CHECK(beats BETWEEN 1 AND 32),
                    start_beat INTEGER NOT NULL DEFAULT 0 CHECK(start_beat >= 0)
                );
                CREATE INDEX IF NOT EXISTS chord_events_scene_position ON chord_events(scene_id, position);
                """)
            if try !hasColumn("chord_events", column: "bass_pitch") { try execute("ALTER TABLE chord_events ADD COLUMN bass_pitch INTEGER") }
            if try !hasColumn("chord_events", column: "start_beat") {
                try execute("ALTER TABLE chord_events ADD COLUMN start_beat INTEGER NOT NULL DEFAULT 0")
                try migrateChordStartBeats()
            }
        } catch { sqlite3_close(database); throw error }
    }

    deinit { sqlite3_close(handle) }

    func scores() throws -> [Score] {
        try query("SELECT id, title FROM scores ORDER BY updated_at DESC, id DESC") { Score(id: sqlite3_column_int64($0, 0), title: try Self.text($0, column: 1, field: "scores.title")) }
    }
    func scenes(scoreID: Int64) throws -> [ScoreScene] {
        try query("SELECT id, title, tempo, position, tonic, scale_kind FROM scenes WHERE score_id = ? ORDER BY position, id", binds: [.integer(scoreID)]) {
            let rawScale = try Self.text($0, column: 5, field: "scenes.scale_kind")
            guard let scale = ScaleKind(rawValue: rawScale) else { throw ScoreLibraryError.corruptData("Unbekannte Tonleiter '\(rawScale)' in scenes.scale_kind.") }
            return ScoreScene(id: sqlite3_column_int64($0, 0), scoreID: scoreID, title: try Self.text($0, column: 1, field: "scenes.title"), tempo: Int(sqlite3_column_int($0, 2)), position: Int(sqlite3_column_int($0, 3)), tonic: Int(sqlite3_column_int($0, 4)), scale: scale)
        }
    }
    func tracks(sceneID: Int64) throws -> [ScoreTrack] {
        try query("SELECT id, name, abc, position, scale_kind, end_mode FROM tracks WHERE scene_id = ? ORDER BY position, id", binds: [.integer(sceneID)]) {
            let override: ScaleKind?
            if sqlite3_column_type($0, 4) == SQLITE_NULL { override = nil }
            else {
                let raw = try Self.text($0, column: 4, field: "tracks.scale_kind")
                guard let parsed = ScaleKind(rawValue: raw) else { throw ScoreLibraryError.corruptData("Unbekannte Spur-Tonleiter '\(raw)'.") }
                override = parsed
            }
            let rawEndMode = try Self.text($0, column: 5, field: "tracks.end_mode")
            guard let endMode = TrackEndMode(rawValue: rawEndMode) else { throw ScoreLibraryError.corruptData("Unbekannter Spur-Endmodus '\(rawEndMode)'.") }
            return ScoreTrack(id: sqlite3_column_int64($0, 0), sceneID: sceneID, name: try Self.text($0, column: 1, field: "tracks.name"), abc: try Self.text($0, column: 2, field: "tracks.abc"), position: Int(sqlite3_column_int($0, 3)), scaleOverride: override, endMode: endMode)
        }
    }
    func chordEvents(sceneID: Int64) throws -> [ChordEvent] {
        try query("SELECT id, position, root, quality, pitches, beats, start_beat, bass_pitch FROM chord_events WHERE scene_id = ? ORDER BY start_beat, position, id", binds: [.integer(sceneID)]) {
            let rawQuality = try Self.text($0, column: 3, field: "chord_events.quality")
            guard let quality = ChordQuality(rawValue: rawQuality) else { throw ScoreLibraryError.corruptData("Unbekannte Akkordqualität '\(rawQuality)'.") }
            let rawPitches = try Self.text($0, column: 4, field: "chord_events.pitches")
            let pitches = rawPitches.split(separator: ",").compactMap { Int($0) }
            guard !pitches.isEmpty else { throw ScoreLibraryError.corruptData("Akkord \(sqlite3_column_int64($0, 0)) enthält keine Tonhöhen.") }
            let bassPitch = sqlite3_column_type($0, 7) == SQLITE_NULL ? nil : Int(sqlite3_column_int($0, 7))
            return ChordEvent(id: sqlite3_column_int64($0, 0), sceneID: sceneID, position: Int(sqlite3_column_int($0, 1)), root: Int(sqlite3_column_int($0, 2)), quality: quality, pitches: pitches, beats: Int(sqlite3_column_int($0, 5)), startBeat: Int(sqlite3_column_int($0, 6)), bassPitch: bassPitch)
        }
    }

    @discardableResult func createScore(title: String = "Neue Partitur") throws -> Int64 {
        try transaction {
            try run("INSERT INTO scores(title) VALUES (?)", binds: [.text(title)])
            let scoreID = sqlite3_last_insert_rowid(handle)
            try run("INSERT INTO scenes(score_id, title, tempo, position) VALUES (?, 'Szene 1', 120, 0)", binds: [.integer(scoreID)])
            try addDefaultTracks(sceneID: sqlite3_last_insert_rowid(handle))
            return scoreID
        }
    }
    @discardableResult func createDemoScore() throws -> Int64 {
        try transaction {
            try run("INSERT INTO scores(title) VALUES (?)", binds: [.text(ScoreDemo.title)])
            let scoreID = sqlite3_last_insert_rowid(handle)
            try run("INSERT INTO scenes(score_id, title, tempo, position, tonic, scale_kind) VALUES (?, ?, ?, 0, 9, ?)", binds: [.integer(scoreID), .text(ScoreDemo.sceneTitle), .integer(Int64(ScoreDemo.tempo)), .text(ScaleKind.naturalMinor.rawValue)])
            let sceneID = sqlite3_last_insert_rowid(handle)
            for position in ScoreDemo.trackNames.indices {
                try run("INSERT INTO tracks(scene_id, name, abc, position) VALUES (?, ?, ?, ?)", binds: [.integer(sceneID), .text(ScoreDemo.trackNames[position]), .text(ScoreDemo.trackABC[position]), .integer(Int64(position))])
            }
            for position in 0..<31 {
                let harmony = ScoreDemo.harmony[position % ScoreDemo.harmony.count]
                try run("INSERT INTO chord_events(scene_id, position, root, quality, pitches, beats, start_beat, bass_pitch) VALUES (?, ?, ?, ?, ?, 16, ?, ?)", binds: [.integer(sceneID), .integer(Int64(position)), .integer(Int64(harmony.root)), .text(harmony.quality.rawValue), .text(harmony.pitches.map(String.init).joined(separator: ",")), .integer(Int64(position * 16)), .integer(Int64(harmony.bass))])
            }
            return scoreID
        }
    }
    @discardableResult func createTimelineScore(title: String, startYear: Int, endYear: Int) throws -> Int64 {
        let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedTitle.isEmpty else { throw ScoreLibraryError.invalidInput("Die Zeitachsen-Partitur benötigt einen Titel.") }
        guard startYear <= endYear else { throw ScoreLibraryError.invalidInput("Das Startjahr muss vor oder im Endjahr liegen.") }
        guard endYear - startYear < 300 else { throw ScoreLibraryError.invalidInput("Eine Zeitachse darf höchstens 300 Jahre umfassen.") }
        let tracks = TimelineScoreTemplate.trackABC(startYear: startYear, endYear: endYear)
        return try transaction {
            try run("INSERT INTO scores(title) VALUES (?)", binds: [.text(cleanedTitle)])
            let scoreID = sqlite3_last_insert_rowid(handle)
            try run("INSERT INTO scenes(score_id, title, tempo, position, tonic, scale_kind) VALUES (?, ?, 120, 0, 0, ?)", binds: [.integer(scoreID), .text("\(startYear)–\(endYear)"), .text(ScaleKind.major.rawValue)])
            let sceneID = sqlite3_last_insert_rowid(handle)
            for position in TimelineScoreTemplate.trackNames.indices {
                try run("INSERT INTO tracks(scene_id, name, abc, position, end_mode) VALUES (?, ?, ?, ?, ?)", binds: [.integer(sceneID), .text(TimelineScoreTemplate.trackNames[position]), .text(tracks[position]), .integer(Int64(position)), .text(TrackEndMode.independent.rawValue)])
            }
            return scoreID
        }
    }
    func createInitialDemoIfNeeded() throws -> Int64? {
        let wasHandled = try scalarInt("SELECT count(*) FROM app_metadata WHERE key = 'initial_demo_created'", binds: []) > 0
        guard !wasHandled else { return nil }
        let scoreID = try scalarInt("SELECT count(*) FROM scores WHERE title = ?", binds: [.text(ScoreDemo.title)]) == 0 ? createDemoScore() : nil
        try run("INSERT INTO app_metadata(key, value) VALUES ('initial_demo_created', '1')")
        return scoreID
    }
    @discardableResult func createScene(scoreID: Int64) throws -> Int64 {
        try transaction {
            let count = try scalarInt("SELECT count(*) FROM scenes WHERE score_id = ?", binds: [.integer(scoreID)])
            try run("INSERT INTO scenes(score_id, title, tempo, position) VALUES (?, ?, 120, ?)", binds: [.integer(scoreID), .text("Szene \(count + 1)"), .integer(count)])
            let sceneID = sqlite3_last_insert_rowid(handle)
            try addDefaultTracks(sceneID: sceneID); try touch(scoreID)
            return sceneID
        }
    }
    func updateScore(id: Int64, title: String) throws { try run("UPDATE scores SET title = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?", binds: [.text(title), .integer(id)]) }
    func updateScene(_ scene: ScoreScene) throws { try run("UPDATE scenes SET title = ?, tempo = ?, tonic = ?, scale_kind = ? WHERE id = ?", binds: [.text(scene.title), .integer(Int64(scene.tempo)), .integer(Int64(scene.tonic)), .text(scene.scale.rawValue), .integer(scene.id)]); try touch(scene.scoreID) }
    func updateTrack(_ track: ScoreTrack, scoreID: Int64) throws { try run("UPDATE tracks SET name = ?, abc = ?, scale_kind = ?, end_mode = ? WHERE id = ?", binds: [.text(track.name), .text(track.abc), track.scaleOverride.map { .text($0.rawValue) } ?? .null, .text(track.endMode.rawValue), .integer(track.id)]); try touch(scoreID) }
    func deleteScore(id: Int64) throws { try run("DELETE FROM scores WHERE id = ?", binds: [.integer(id)]) }
    @discardableResult func addChord(sceneID: Int64, chord: TheoryChord, at requestedPosition: Int? = nil) throws -> Int64 {
        try transaction {
            let events = try chordEvents(sceneID: sceneID)
            let count = events.count
            let position = min(max(0, requestedPosition ?? count), count)
            let startBeat = position < count ? events[position].startBeat : events.map { $0.startBeat + $0.beats }.max() ?? 0
            if position < count {
                try run("UPDATE chord_events SET position = position + 1 WHERE scene_id = ? AND position >= ?", binds: [.integer(sceneID), .integer(Int64(position))])
                try run("UPDATE chord_events SET start_beat = start_beat + 4 WHERE scene_id = ? AND start_beat >= ?", binds: [.integer(sceneID), .integer(Int64(startBeat))])
            }
            try run("INSERT INTO chord_events(scene_id, position, root, quality, pitches, beats, start_beat) VALUES (?, ?, ?, ?, ?, 4, ?)", binds: [.integer(sceneID), .integer(Int64(position)), .integer(Int64(chord.root)), .text(chord.quality.rawValue), .text(chord.pitches.map(String.init).joined(separator: ",")), .integer(Int64(startBeat))])
            return sqlite3_last_insert_rowid(handle)
        }
    }
    @discardableResult func addChord(sceneID: Int64, chord: TheoryChord, atBeat startBeat: Int) throws -> Int64 {
        guard startBeat >= 0 else { throw ScoreLibraryError.invalidInput("Die Akkordposition darf nicht vor Takt 1 liegen.") }
        return try transaction {
            let events = try chordEvents(sceneID: sceneID)
            let endBeat = startBeat + 4
            guard !events.contains(where: { $0.startBeat < endBeat && $0.startBeat + $0.beats > startBeat }) else {
                throw ScoreLibraryError.invalidInput("An dieser Position liegt bereits ein Akkord. Wähle einen freien Takt oder ersetze den vorhandenen Akkord.")
            }
            let position = events.filter { $0.startBeat < startBeat }.count
            try run("UPDATE chord_events SET position = position + 1 WHERE scene_id = ? AND position >= ?", binds: [.integer(sceneID), .integer(Int64(position))])
            try run("INSERT INTO chord_events(scene_id, position, root, quality, pitches, beats, start_beat) VALUES (?, ?, ?, ?, ?, 4, ?)", binds: [.integer(sceneID), .integer(Int64(position)), .integer(Int64(chord.root)), .text(chord.quality.rawValue), .text(chord.pitches.map(String.init).joined(separator: ",")), .integer(Int64(startBeat))])
            return sqlite3_last_insert_rowid(handle)
        }
    }
    func updateChord(_ event: ChordEvent) throws {
        guard event.startBeat >= 0 else { throw ScoreLibraryError.invalidInput("Die Akkordposition darf nicht vor Takt 1 liegen.") }
        let overlapCount = try scalarInt("SELECT count(*) FROM chord_events WHERE scene_id = ? AND id != ? AND start_beat < ? AND start_beat + beats > ?", binds: [.integer(event.sceneID), .integer(event.id), .integer(Int64(event.startBeat + event.beats)), .integer(Int64(event.startBeat))])
        guard overlapCount == 0 else { throw ScoreLibraryError.invalidInput("Die geänderte Akkorddauer würde einen anderen Akkord überlappen.") }
        try run("UPDATE chord_events SET position = ?, root = ?, quality = ?, pitches = ?, beats = ?, start_beat = ?, bass_pitch = ? WHERE id = ?", binds: [.integer(Int64(event.position)), .integer(Int64(event.root)), .text(event.quality.rawValue), .text(event.pitches.map(String.init).joined(separator: ",")), .integer(Int64(event.beats)), .integer(Int64(event.startBeat)), event.bassPitch.map { .integer(Int64($0)) } ?? .null, .integer(event.id)])
    }
    func deleteChord(id: Int64) throws {
        try transaction {
            guard let sceneID = try query("SELECT scene_id FROM chord_events WHERE id = ?", binds: [.integer(id)], map: { sqlite3_column_int64($0, 0) }).first else { return }
            try run("DELETE FROM chord_events WHERE id = ?", binds: [.integer(id)])
            for (position, event) in try chordEvents(sceneID: sceneID).enumerated() {
                try run("UPDATE chord_events SET position = ? WHERE id = ?", binds: [.integer(Int64(position)), .integer(event.id)])
            }
        }
    }
    func reorderChords(_ ids: [Int64]) throws {
        guard !ids.isEmpty else { return }
        try transaction {
            let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
            let events = try query("SELECT id, scene_id, start_beat, beats FROM chord_events WHERE id IN (\(placeholders)) ORDER BY start_beat, position, id", binds: ids.map(BindValue.integer)) {
                (id: sqlite3_column_int64($0, 0), sceneID: sqlite3_column_int64($0, 1), startBeat: Int(sqlite3_column_int($0, 2)), beats: Int(sqlite3_column_int($0, 3)))
            }
            guard events.count == ids.count, Set(events.map(\.sceneID)).count == 1 else {
                throw ScoreLibraryError.invalidInput("Die Akkordfolge enthält fehlende Akkorde oder Akkorde aus verschiedenen Szenen.")
            }
            let slots = events.map(\.startBeat)
            let eventByID = Dictionary(uniqueKeysWithValues: events.map { ($0.id, $0) })
            for index in ids.indices where index + 1 < slots.count {
                guard let event = eventByID[ids[index]], slots[index] + event.beats <= slots[index + 1] else {
                    throw ScoreLibraryError.invalidInput("Diese Reihenfolge passt zeitlich nicht in die vorhandenen Akkordplätze.")
                }
            }
            for (position, id) in ids.enumerated() {
                try run("UPDATE chord_events SET position = ?, start_beat = ? WHERE id = ?", binds: [.integer(Int64(position)), .integer(Int64(slots[position])), .integer(id)])
            }
        }
    }
    func transposeChords(sceneID: Int64, semitones: Int) throws {
        try transaction {
            for var event in try chordEvents(sceneID: sceneID) {
                event.root = MusicTheory.normalized(event.root + semitones)
                event.pitches = event.pitches.map { $0 + semitones }
                event.bassPitch = event.bassPitch.map { $0 + semitones }
                try updateChord(event)
            }
        }
    }

    private func addDefaultTracks(sceneID: Int64) throws {
        for (position, name) in ScoreDefaults.trackNames.enumerated() {
            try run("INSERT INTO tracks(scene_id, name, abc, position) VALUES (?, ?, ?, ?)", binds: [.integer(sceneID), .text(name), .text(ScoreDefaults.trackABC[position]), .integer(Int64(position))])
        }
    }
    private func migrateChordStartBeats() throws {
        let sceneIDs = try query("SELECT DISTINCT scene_id FROM chord_events", map: { sqlite3_column_int64($0, 0) })
        for sceneID in sceneIDs {
            let rows = try query("SELECT id, beats FROM chord_events WHERE scene_id = ? ORDER BY position, id", binds: [.integer(sceneID)]) { (sqlite3_column_int64($0, 0), Int(sqlite3_column_int($0, 1))) }
            var startBeat = 0
            for (id, beats) in rows {
                try run("UPDATE chord_events SET start_beat = ? WHERE id = ?", binds: [.integer(Int64(startBeat)), .integer(id)])
                startBeat += beats
            }
        }
    }
    private func touch(_ scoreID: Int64) throws { try run("UPDATE scores SET updated_at = CURRENT_TIMESTAMP WHERE id = ?", binds: [.integer(scoreID)]) }
    private func hasColumn(_ table: String, column: String) throws -> Bool {
        try query("PRAGMA table_info(\(table))") { try Self.text($0, column: 1, field: "PRAGMA table_info.name") }.contains(column)
    }
    private enum BindValue { case integer(Int64), text(String), null }
    private func execute(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(handle, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? errorMessage; sqlite3_free(error); throw ScoreLibraryError.database(message)
        }
    }
    private func run(_ sql: String, binds: [BindValue] = []) throws {
        let statement = try prepare(sql); defer { sqlite3_finalize(statement) }; try bind(binds, to: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw ScoreLibraryError.database(errorMessage) }
    }
    private func query<T>(_ sql: String, binds: [BindValue] = [], map: (OpaquePointer) throws -> T) throws -> [T] {
        let statement = try prepare(sql); defer { sqlite3_finalize(statement) }; try bind(binds, to: statement); var values: [T] = []
        while true { switch sqlite3_step(statement) { case SQLITE_ROW: values.append(try map(statement)); case SQLITE_DONE: return values; default: throw ScoreLibraryError.database(errorMessage) } }
    }
    private func scalarInt(_ sql: String, binds: [BindValue]) throws -> Int64 {
        guard let value = try query(sql, binds: binds, map: { sqlite3_column_int64($0, 0) }).first else { throw ScoreLibraryError.corruptData("Abfrage lieferte keinen Zahlenwert.") }; return value
    }
    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?; guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw ScoreLibraryError.database(errorMessage) }; return statement
    }
    private func bind(_ values: [BindValue], to statement: OpaquePointer) throws {
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1), result: Int32
            switch value { case let .integer(number): result = sqlite3_bind_int64(statement, index, number); case let .text(text): result = sqlite3_bind_text(statement, index, text, -1, Self.transient); case .null: result = sqlite3_bind_null(statement, index) }
            guard result == SQLITE_OK else { throw ScoreLibraryError.database(errorMessage) }
        }
    }
    private func transaction<T>(_ work: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do { let value = try work(); try execute("COMMIT"); return value } catch { try? execute("ROLLBACK"); throw error }
    }
    private var errorMessage: String { String(cString: sqlite3_errmsg(handle)) }
    private static func text(_ statement: OpaquePointer, column: Int32, field: String) throws -> String {
        guard sqlite3_column_type(statement, column) == SQLITE_TEXT, let value = sqlite3_column_text(statement, column) else { logger.error("Ungültiger SQLite-Wert in \(field, privacy: .public)"); throw ScoreLibraryError.corruptData("\(field) ist kein Textwert.") }; return String(cString: value)
    }
}

@MainActor final class ScoreLibrary: ObservableObject {
    private static let logger = Logger(subsystem: "de.xviz.Chordflow", category: "library")
    private var database: ScoreDatabase?
    @Published private(set) var scores: [Score] = []; @Published private(set) var scenes: [ScoreScene] = []; @Published private(set) var tracks: [ScoreTrack] = []; @Published private(set) var chordEvents: [ChordEvent] = []
    @Published var selectedScoreID: Int64?; @Published var selectedSceneID: Int64?; @Published var errorMessage: String?

    init(database: ScoreDatabase? = nil) { do { self.database = try database ?? ScoreDatabase(); let demoID = try self.database?.createInitialDemoIfNeeded(); try reloadScores(selecting: demoID) } catch { report(error, context: "Partituren konnten nicht geladen werden") } }
    var selectedScore: Score? { scores.first { $0.id == selectedScoreID } }; var selectedScene: ScoreScene? { scenes.first { $0.id == selectedSceneID } }
    func addScore() { perform("Partitur konnte nicht angelegt werden") { let id = try $0.createScore(); try reloadScores(selecting: id) } }
    func addTimelineScore(title: String, startYear: Int, endYear: Int) { perform("Zeitachsen-Partitur konnte nicht angelegt werden") { let id = try $0.createTimelineScore(title: title, startYear: startYear, endYear: endYear); try reloadScores(selecting: id) } }
    func selectScore(_ id: Int64?) { selectedScoreID = id; perform("Partitur konnte nicht geladen werden") { _ in try loadSelectedScore() } }
    func selectScene(_ id: Int64?) { selectedSceneID = id; perform("Szene konnte nicht geladen werden") { tracks = try id.map($0.tracks(sceneID:)) ?? []; chordEvents = try id.map($0.chordEvents(sceneID:)) ?? [] } }
    func addScene() { guard let scoreID = selectedScoreID else { return }; perform("Szene konnte nicht angelegt werden") { let id = try $0.createScene(scoreID: scoreID); scenes = try $0.scenes(scoreID: scoreID); selectScene(id) } }
    func updateScoreTitle(_ title: String) { guard let id = selectedScoreID, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }; perform("Partiturtitel konnte nicht gespeichert werden") { try $0.updateScore(id: id, title: title); if let index = scores.firstIndex(where: { $0.id == id }) { scores[index].title = title } } }
    func updateScene(_ scene: ScoreScene) { perform("Szene konnte nicht gespeichert werden") { try $0.updateScene(scene); if let index = scenes.firstIndex(where: { $0.id == scene.id }) { scenes[index] = scene } } }
    func updateTrack(_ track: ScoreTrack) { guard let scoreID = selectedScoreID else { return }; perform("Spur konnte nicht gespeichert werden") { try $0.updateTrack(track, scoreID: scoreID); if let index = tracks.firstIndex(where: { $0.id == track.id }) { tracks[index] = track } } }
    func addChord(_ chord: TheoryChord) { guard let sceneID = selectedSceneID else { return }; perform("Akkord konnte nicht eingefügt werden") { _ = try $0.addChord(sceneID: sceneID, chord: chord); chordEvents = try $0.chordEvents(sceneID: sceneID) } }
    @discardableResult func addChord(_ chord: TheoryChord, atBeat startBeat: Int) -> Bool { guard let sceneID = selectedSceneID else { return false }; var succeeded = false; perform("Akkord konnte nicht eingesetzt werden") { _ = try $0.addChord(sceneID: sceneID, chord: chord, atBeat: startBeat); chordEvents = try $0.chordEvents(sceneID: sceneID); succeeded = true }; return succeeded }
    func insertChord(_ chord: TheoryChord, before eventID: Int64) {
        guard let sceneID = selectedSceneID, let position = chordEvents.first(where: { $0.id == eventID })?.position else { return }
        perform("Akkord konnte nicht eingefügt werden") { _ = try $0.addChord(sceneID: sceneID, chord: chord, at: position); chordEvents = try $0.chordEvents(sceneID: sceneID) }
    }
    func updateChord(_ event: ChordEvent) { perform("Akkord konnte nicht gespeichert werden") { try $0.updateChord(event); if let index = chordEvents.firstIndex(where: { $0.id == event.id }) { chordEvents[index] = event } } }
    func replaceChord(id: Int64, with chord: TheoryChord) {
        guard var event = chordEvents.first(where: { $0.id == id }) else { return }
        event.root = chord.root; event.quality = chord.quality; event.pitches = chord.pitches
        updateChord(event)
    }
    func transposeChordProgression(from oldTonic: Int, to newTonic: Int) {
        guard let sceneID = selectedSceneID else { return }
        let semitones = MusicTheory.normalized(newTonic - oldTonic)
        perform("Akkordfolge konnte nicht transponiert werden") { try $0.transposeChords(sceneID: sceneID, semitones: semitones); chordEvents = try $0.chordEvents(sceneID: sceneID) }
    }
    func deleteChord(_ id: Int64) { guard let sceneID = selectedSceneID else { return }; perform("Akkord konnte nicht gelöscht werden") { try $0.deleteChord(id: id); chordEvents = try $0.chordEvents(sceneID: sceneID) } }
    func moveChord(_ sourceID: Int64, before targetID: Int64) {
        guard sourceID != targetID, let source = chordEvents.firstIndex(where: { $0.id == sourceID }), let target = chordEvents.firstIndex(where: { $0.id == targetID }) else { return }
        var reordered = chordEvents; let item = reordered.remove(at: source); reordered.insert(item, at: source < target ? target - 1 : target)
        perform("Akkordfolge konnte nicht umgeordnet werden") { try $0.reorderChords(reordered.map(\.id)); chordEvents = try $0.chordEvents(sceneID: reordered[0].sceneID) }
    }
    func deleteSelectedScore() { guard let id = selectedScoreID else { return }; perform("Partitur konnte nicht gelöscht werden") { try $0.deleteScore(id: id); try reloadScores(selecting: nil) } }
    private func reloadScores(selecting id: Int64?) throws { guard let database else { return }; scores = try database.scores(); selectedScoreID = id ?? scores.first?.id; try loadSelectedScore() }
    private func loadSelectedScore() throws { guard let database, let selectedScoreID else { scenes = []; tracks = []; chordEvents = []; selectedSceneID = nil; return }; scenes = try database.scenes(scoreID: selectedScoreID); selectedSceneID = scenes.first?.id; tracks = try selectedSceneID.map(database.tracks(sceneID:)) ?? []; chordEvents = try selectedSceneID.map(database.chordEvents(sceneID:)) ?? [] }
    private func perform(_ context: String, _ work: (ScoreDatabase) throws -> Void) { guard let database else { return }; do { try work(database); errorMessage = nil } catch { report(error, context: context) } }
    private func report(_ error: Error, context: String) { let message = "\(context): \(error.localizedDescription)"; Self.logger.error("\(message, privacy: .public)"); errorMessage = message }
}

enum ABCScoreBuilder {
    static func build(score: Score, scene: ScoreScene, tracks: [ScoreTrack], chords: [ChordEvent] = []) -> String {
        let chordBeats = chords.map { $0.startBeat + $0.beats }.max() ?? 0
        let rawSceneBeats = max(chordBeats, tracks.map { ABCTrackTiming.duration(of: $0.abc) }.max() ?? 0)
        let sceneBeats = ((rawSceneBeats + 3) / 4) * 4
        let voices = tracks.enumerated().map { index, track in
            let content: String
            if !chords.isEmpty && track.name == "Akkorde" { content = chordABC(chords, totalBeats: sceneBeats) }
            else if !chords.isEmpty && track.name == "Bass" { content = bassABC(chords, totalBeats: sceneBeats) }
            else { content = ABCTrackTiming.fitted(track.abc, to: sceneBeats, mode: track.endMode) }
            let clef = track.position == 0 || track.name.compare("Bass", options: .caseInsensitive) == .orderedSame ? "bass" : "treble"
            // The visually identical Cyrillic е makes the layout placeholder unambiguous in the renderer.
            return "V:v\(index + 1) name=\"\(escaped(track.name))\" subname=\"Akkordе\" clef=\(clef)\n\(content)"
        }.joined(separator: "\n")
        return "X:1\nT:\(score.title) – \(scene.title)\nM:4/4\nL:1/4\nQ:1/4=\(scene.tempo)\nK:\(MusicTheory.abcKey(tonic: scene.tonic, kind: scene.scale))\n%%score { \(tracks.indices.map { "v\($0 + 1)" }.joined(separator: " ")) }\n\(voices)"
    }

    static func sceneBeats(tracks: [ScoreTrack], chords: [ChordEvent]) -> Int {
        max(chords.map { $0.startBeat + $0.beats }.max() ?? 0, tracks.map { ABCTrackTiming.duration(of: $0.abc) }.max() ?? 0)
    }
    private static func chordABC(_ events: [ChordEvent], totalBeats: Int) -> String {
        timedABC(events, totalBeats: totalBeats) { event, duration, isFirstChunk, continues in
            let symbol = isFirstChunk ? "\"\(event.chord.symbol)\"" : ""
            return "\(symbol)[\(event.pitches.map(MusicTheory.abcNote).joined())]\(duration)\(continues ? "-" : "")"
        }
    }
    private static func bassABC(_ events: [ChordEvent], totalBeats: Int) -> String {
        timedABC(events, totalBeats: totalBeats) { event, duration, _, continues in
            "\(MusicTheory.abcNote(event.bassPitch ?? 36 + event.root))\(duration)\(continues ? "-" : "")"
        }
    }
    private static func timedABC(_ events: [ChordEvent], totalBeats: Int, render: (ChordEvent, Int, Bool, Bool) -> String) -> String {
        var cursor = 0, parts: [String] = []
        func append(_ token: String, duration: Int) {
            parts.append(token)
            cursor += duration
            if cursor.isMultiple(of: 4) { parts.append("|") }
        }
        func appendRests(until target: Int) {
            while cursor < target {
                let duration = min(target - cursor, 4 - cursor % 4)
                append("z\(duration)", duration: duration)
            }
        }
        for event in events.sorted(by: { ($0.startBeat, $0.position) < ($1.startBeat, $1.position) }) {
            appendRests(until: event.startBeat)
            var remaining = event.beats, isFirstChunk = true
            while remaining > 0 {
                let duration = min(remaining, 4 - cursor % 4)
                append(render(event, duration, isFirstChunk, remaining > duration), duration: duration)
                remaining -= duration
                isFirstChunk = false
            }
        }
        appendRests(until: totalBeats)
        return parts.joined(separator: " ")
    }
    private static func escaped(_ value: String) -> String { value.replacingOccurrences(of: "\"", with: "'") }

    static func singleChord(_ chord: TheoryChord, scene: ScoreScene) -> String {
        let clef = MusicTheory.preferredClef(for: chord.pitches) == .bass ? "bass" : "treble"
        let inScale = chord.pitches.filter { MusicTheory.contains($0, tonic: scene.tonic, kind: scene.scale) }
        let foreign = chord.pitches.filter { !MusicTheory.contains($0, tonic: scene.tonic, kind: scene.scale) }
        let header = "X:1\nT:\(chord.symbol)\nM:4/4\nL:1/4\nK:\(MusicTheory.abcKey(tonic: scene.tonic, kind: scene.scale))"
        guard !inScale.isEmpty, !foreign.isEmpty else {
            let color = inScale.isEmpty ? "\n%%voicecolor orange" : ""
            return "\(header)\nV:chord clef=\(clef)\(color)\n[V:chord] \"\(chord.symbol)\"[\(chord.pitches.map(MusicTheory.abcNote).joined())]4 |"
        }
        return "\(header)\n%%score ( chord foreign )\nV:chord clef=\(clef)\n[V:chord] \"\(chord.symbol)\"[\(inScale.map(MusicTheory.abcNote).joined())]4 |\nV:foreign clef=\(clef)\n%%voicecolor orange\n[V:foreign] [\(foreign.map(MusicTheory.abcNote).joined())]4 |"
    }
}

enum ABCTrackTiming {
    static func duration(of source: String) -> Int {
        events(in: source).reduce(0) { $0 + $1.duration }
    }

    static func fitted(_ source: String, to targetBeats: Int, mode: TrackEndMode) -> String {
        let beats = duration(of: source)
        guard targetBeats > beats, beats > 0 else { return source }
        switch mode {
        case .once, .independent: return source
        case .pad: return source + rest(beats: targetBeats - beats)
        case .loop:
            var result = source, remaining = targetBeats - beats
            while remaining >= beats { result += " " + source; remaining -= beats }
            return remaining > 0 ? result + rest(beats: remaining) : result
        }
    }

    private static func rest(beats: Int) -> String {
        var remaining = beats
        var measures: [String] = []
        while remaining > 0 {
            let duration = min(4, remaining)
            measures.append("z\(duration) |")
            remaining -= duration
        }
        return measures.isEmpty ? "" : " " + measures.joined(separator: " ")
    }

    private static func events(in source: String) -> [(duration: Int, token: String)] {
        let characters = Array(source); var result: [(Int, String)] = []; var index = 0; var quoted = false
        while index < characters.count {
            if characters[index] == "\"" { quoted.toggle(); index += 1; continue }
            if quoted { index += 1; continue }
            if characters[index] == "[", let end = characters[(index + 1)...].firstIndex(of: "]") {
                if index + 1 < end, characters[index + 1] != "V", characters[index + 1] != "P" {
                    let after = durationSuffix(in: characters, after: end + 1)
                    result.append((after.duration, String(characters[index..<after.end])))
                    index = after.end; continue
                }
            }
            var cursor = index
            while cursor < characters.count, "^_=".contains(characters[cursor]) { cursor += 1 }
            if cursor < characters.count, "ABCDEFGabcdefgzZxX".contains(characters[cursor]) {
                cursor += 1
                while cursor < characters.count, characters[cursor] == "," || characters[cursor] == "'" { cursor += 1 }
                let after = durationSuffix(in: characters, after: cursor)
                result.append((after.duration, String(characters[index..<after.end])))
                index = after.end; continue
            }
            index += 1
        }
        return result
    }

    private static func durationSuffix(in characters: [Character], after start: Int) -> (duration: Int, end: Int) {
        var end = start
        while end < characters.count, characters[end].isNumber { end += 1 }
        return (Int(String(characters[start..<end])) ?? 1, end)
    }
}
