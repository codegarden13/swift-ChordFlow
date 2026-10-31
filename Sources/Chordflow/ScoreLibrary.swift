import Foundation
import OSLog
import SQLite3

struct Score: Identifiable, Equatable, Sendable { let id: Int64; var title: String }
struct ScoreScene: Identifiable, Equatable, Sendable { let id: Int64; let scoreID: Int64; var title: String; var tempo: Int; var position: Int; var tonic: Int = 0; var scale: ScaleKind = .major }
struct ScoreTrack: Identifiable, Equatable, Sendable { let id: Int64; let sceneID: Int64; var name: String; var abc: String; var position: Int; var scaleOverride: ScaleKind? = nil }

enum ScoreDefaults {
    static let trackNames = ["Bass", "Melodie", "Akkorde"]
    static let trackABC = ["C,4 | F,4 | G,4 | C,4 |", "C D E G | A G E D |", "[CEG]4 | [FAc]4 | [GBd]4 | [CEG]4 |"]
}

enum ScoreLibraryError: LocalizedError {
    case applicationSupportUnavailable, database(String), corruptData(String)
    var errorDescription: String? {
        switch self {
        case .applicationSupportUnavailable: "Der Speicherort für die Partituren ist nicht verfügbar."
        case let .database(message): "Die Partitur-Datenbank konnte nicht verwendet werden: \(message)"
        case let .corruptData(message): "Die Partitur-Datenbank enthält ungültige Daten: \(message)"
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
                CREATE INDEX IF NOT EXISTS scenes_score_position ON scenes(score_id, position);
                CREATE INDEX IF NOT EXISTS tracks_scene_position ON tracks(scene_id, position);
                """)
            if try !hasColumn("scenes", column: "tonic") { try execute("ALTER TABLE scenes ADD COLUMN tonic INTEGER NOT NULL DEFAULT 0 CHECK(tonic BETWEEN 0 AND 11)") }
            if try !hasColumn("scenes", column: "scale_kind") { try execute("ALTER TABLE scenes ADD COLUMN scale_kind TEXT NOT NULL DEFAULT 'major'") }
            if try !hasColumn("tracks", column: "scale_kind") { try execute("ALTER TABLE tracks ADD COLUMN scale_kind TEXT") }
            try execute("""
                CREATE TABLE IF NOT EXISTS chord_events (
                    id INTEGER PRIMARY KEY,
                    scene_id INTEGER NOT NULL REFERENCES scenes(id) ON DELETE CASCADE,
                    position INTEGER NOT NULL,
                    root INTEGER NOT NULL CHECK(root BETWEEN 0 AND 11),
                    quality TEXT NOT NULL,
                    pitches TEXT NOT NULL,
                    beats INTEGER NOT NULL DEFAULT 4 CHECK(beats BETWEEN 1 AND 32)
                );
                CREATE INDEX IF NOT EXISTS chord_events_scene_position ON chord_events(scene_id, position);
                """)
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
        try query("SELECT id, name, abc, position, scale_kind FROM tracks WHERE scene_id = ? ORDER BY position, id", binds: [.integer(sceneID)]) {
            let override: ScaleKind?
            if sqlite3_column_type($0, 4) == SQLITE_NULL { override = nil }
            else {
                let raw = try Self.text($0, column: 4, field: "tracks.scale_kind")
                guard let parsed = ScaleKind(rawValue: raw) else { throw ScoreLibraryError.corruptData("Unbekannte Spur-Tonleiter '\(raw)'.") }
                override = parsed
            }
            return ScoreTrack(id: sqlite3_column_int64($0, 0), sceneID: sceneID, name: try Self.text($0, column: 1, field: "tracks.name"), abc: try Self.text($0, column: 2, field: "tracks.abc"), position: Int(sqlite3_column_int($0, 3)), scaleOverride: override)
        }
    }
    func chordEvents(sceneID: Int64) throws -> [ChordEvent] {
        try query("SELECT id, position, root, quality, pitches, beats FROM chord_events WHERE scene_id = ? ORDER BY position, id", binds: [.integer(sceneID)]) {
            let rawQuality = try Self.text($0, column: 3, field: "chord_events.quality")
            guard let quality = ChordQuality(rawValue: rawQuality) else { throw ScoreLibraryError.corruptData("Unbekannte Akkordqualität '\(rawQuality)'.") }
            let rawPitches = try Self.text($0, column: 4, field: "chord_events.pitches")
            let pitches = rawPitches.split(separator: ",").compactMap { Int($0) }
            guard !pitches.isEmpty else { throw ScoreLibraryError.corruptData("Akkord \(sqlite3_column_int64($0, 0)) enthält keine Tonhöhen.") }
            return ChordEvent(id: sqlite3_column_int64($0, 0), sceneID: sceneID, position: Int(sqlite3_column_int($0, 1)), root: Int(sqlite3_column_int($0, 2)), quality: quality, pitches: pitches, beats: Int(sqlite3_column_int($0, 5)))
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
    func updateTrack(_ track: ScoreTrack, scoreID: Int64) throws { try run("UPDATE tracks SET name = ?, abc = ?, scale_kind = ? WHERE id = ?", binds: [.text(track.name), .text(track.abc), track.scaleOverride.map { .text($0.rawValue) } ?? .null, .integer(track.id)]); try touch(scoreID) }
    func deleteScore(id: Int64) throws { try run("DELETE FROM scores WHERE id = ?", binds: [.integer(id)]) }
    @discardableResult func addChord(sceneID: Int64, chord: TheoryChord) throws -> Int64 {
        let position = try scalarInt("SELECT count(*) FROM chord_events WHERE scene_id = ?", binds: [.integer(sceneID)])
        try run("INSERT INTO chord_events(scene_id, position, root, quality, pitches, beats) VALUES (?, ?, ?, ?, ?, 4)", binds: [.integer(sceneID), .integer(position), .integer(Int64(chord.root)), .text(chord.quality.rawValue), .text(chord.pitches.map(String.init).joined(separator: ","))])
        return sqlite3_last_insert_rowid(handle)
    }
    func updateChord(_ event: ChordEvent) throws {
        try run("UPDATE chord_events SET position = ?, root = ?, quality = ?, pitches = ?, beats = ? WHERE id = ?", binds: [.integer(Int64(event.position)), .integer(Int64(event.root)), .text(event.quality.rawValue), .text(event.pitches.map(String.init).joined(separator: ",")), .integer(Int64(event.beats)), .integer(event.id)])
    }
    func deleteChord(id: Int64) throws { try run("DELETE FROM chord_events WHERE id = ?", binds: [.integer(id)]) }
    func reorderChords(_ ids: [Int64]) throws { try transaction { for (position, id) in ids.enumerated() { try run("UPDATE chord_events SET position = ? WHERE id = ?", binds: [.integer(Int64(position)), .integer(id)]) } } }

    private func addDefaultTracks(sceneID: Int64) throws {
        for (position, name) in ScoreDefaults.trackNames.enumerated() {
            try run("INSERT INTO tracks(scene_id, name, abc, position) VALUES (?, ?, ?, ?)", binds: [.integer(sceneID), .text(name), .text(ScoreDefaults.trackABC[position]), .integer(Int64(position))])
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

    init(database: ScoreDatabase? = nil) { do { self.database = try database ?? ScoreDatabase(); try reloadScores(selecting: nil) } catch { report(error, context: "Partituren konnten nicht geladen werden") } }
    var selectedScore: Score? { scores.first { $0.id == selectedScoreID } }; var selectedScene: ScoreScene? { scenes.first { $0.id == selectedSceneID } }
    func addScore() { perform("Partitur konnte nicht angelegt werden") { let id = try $0.createScore(); try reloadScores(selecting: id) } }
    func selectScore(_ id: Int64?) { selectedScoreID = id; perform("Partitur konnte nicht geladen werden") { _ in try loadSelectedScore() } }
    func selectScene(_ id: Int64?) { selectedSceneID = id; perform("Szene konnte nicht geladen werden") { tracks = try id.map($0.tracks(sceneID:)) ?? []; chordEvents = try id.map($0.chordEvents(sceneID:)) ?? [] } }
    func addScene() { guard let scoreID = selectedScoreID else { return }; perform("Szene konnte nicht angelegt werden") { let id = try $0.createScene(scoreID: scoreID); scenes = try $0.scenes(scoreID: scoreID); selectScene(id) } }
    func updateScoreTitle(_ title: String) { guard let id = selectedScoreID, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }; perform("Partiturtitel konnte nicht gespeichert werden") { try $0.updateScore(id: id, title: title); if let index = scores.firstIndex(where: { $0.id == id }) { scores[index].title = title } } }
    func updateScene(_ scene: ScoreScene) { perform("Szene konnte nicht gespeichert werden") { try $0.updateScene(scene); if let index = scenes.firstIndex(where: { $0.id == scene.id }) { scenes[index] = scene } } }
    func updateTrack(_ track: ScoreTrack) { guard let scoreID = selectedScoreID else { return }; perform("Spur konnte nicht gespeichert werden") { try $0.updateTrack(track, scoreID: scoreID); if let index = tracks.firstIndex(where: { $0.id == track.id }) { tracks[index] = track } } }
    func addChord(_ chord: TheoryChord) { guard let sceneID = selectedSceneID else { return }; perform("Akkord konnte nicht eingefügt werden") { _ = try $0.addChord(sceneID: sceneID, chord: chord); chordEvents = try $0.chordEvents(sceneID: sceneID) } }
    func updateChord(_ event: ChordEvent) { perform("Akkord konnte nicht gespeichert werden") { try $0.updateChord(event); if let index = chordEvents.firstIndex(where: { $0.id == event.id }) { chordEvents[index] = event } } }
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
        let voices = tracks.enumerated().map { index, track in
            let content = track.name == "Akkorde" && !chords.isEmpty ? chordABC(chords) : track.abc
            return "V:v\(index + 1) name=\"\(escaped(track.name))\"\n\(content)"
        }.joined(separator: "\n")
        return "X:1\nT:\(score.title) – \(scene.title)\nM:4/4\nL:1/4\nQ:1/4=\(scene.tempo)\nK:\(MusicTheory.abcKey(tonic: scene.tonic, kind: scene.scale))\n%%score { \(tracks.indices.map { "v\($0 + 1)" }.joined(separator: " ")) }\n\(voices)"
    }
    private static func chordABC(_ events: [ChordEvent]) -> String {
        events.map { event in "\"\(event.chord.symbol)\"[\(event.pitches.map(MusicTheory.abcNote).joined())]\(event.beats) |" }.joined(separator: " ")
    }
    private static func escaped(_ value: String) -> String { value.replacingOccurrences(of: "\"", with: "'") }
}
