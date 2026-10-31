import SwiftUI

struct ContentView: View {
    @ObservedObject var library: ScoreLibrary
    @StateObject private var midi = MIDIService.shared
    @StateObject private var score = ScoreController()
    @State private var scoreHeight: CGFloat = 360
    @State private var measure = 0
    @State private var sessionID = UUID()
    @State private var workspaceMode = WorkspaceMode.arrangement

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            if let selectedScore = library.selectedScore, let selectedScene = library.selectedScene {
                workspace(selectedScore, scene: selectedScene)
            } else {
                ContentUnavailableView("Noch keine Partitur", systemImage: "music.note.list", description: Text("Lege links eine Partitur für dein Live-Set an."))
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 1_100, minHeight: 700)
        .onAppear { midi.start() }
        .onDisappear { midi.deactivate(sessionID) }
        .onChange(of: score.interactionCount) { _, _ in midi.activate(sessionID) }
        .onChange(of: midi.notes) { _, notes in
            guard midi.isActive(sessionID) else { return }
            score.showMIDINotes(notes.map(\.number))
        }
        .onChange(of: midi.activeSessionID) { _, active in if active != sessionID { score.showMIDINotes([]) } }
        .alert("Datenbankfehler", isPresented: Binding(get: { library.errorMessage != nil }, set: { if !$0 { library.errorMessage = nil } })) {
            Button("OK", role: .cancel) { library.errorMessage = nil }
        } message: { Text(library.errorMessage ?? "Unbekannter Fehler") }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: Binding<Int64?>(get: { library.selectedScoreID }, set: { library.selectScore($0) })) {
                Section("Partituren") {
                    ForEach(library.scores) { item in Label(item.title, systemImage: "music.note.list").tag(Optional(item.id)) }
                }
            }
            HStack {
                Button("Partitur hinzufügen", systemImage: "plus") { library.addScore() }.labelStyle(.iconOnly)
                Button("Partitur löschen", systemImage: "trash", role: .destructive) { library.deleteSelectedScore() }.labelStyle(.iconOnly).disabled(library.selectedScoreID == nil)
                Spacer()
            }
            .buttonStyle(.borderless).padding(10)
        }
        .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 280)
    }

    private func workspace(_ selectedScore: Score, scene selectedScene: ScoreScene) -> some View {
        VStack(spacing: 0) {
            sceneToolbar(selectedScore, scene: selectedScene)
            Divider()
            HSplitView {
                Group {
                    if workspaceMode == .tracks { editor(selectedScore, scene: selectedScene) }
                    else { TheoryWorkspaceView(library: library, scene: selectedScene, mode: workspaceMode) }
                }.frame(minWidth: 480, idealWidth: 650)
                preview(selectedScore, scene: selectedScene).frame(minWidth: 520)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func sceneToolbar(_ selectedScore: Score, scene: ScoreScene) -> some View {
        HStack(spacing: 10) {
            TextField("Partiturtitel", text: Binding<String>(get: { selectedScore.title }, set: { library.updateScoreTitle($0) })).font(.headline).textFieldStyle(.roundedBorder).frame(width: 190)
            Picker("Szene", selection: Binding<Int64?>(get: { library.selectedSceneID }, set: { library.selectScene($0) })) {
                ForEach(library.scenes) { item in Text(item.title).tag(Optional(item.id)) }
            }.frame(width: 150)
            Button("Szene hinzufügen", systemImage: "plus") { library.addScene() }.labelStyle(.iconOnly)
            Picker("Grundton", selection: Binding(get: { scene.tonic }, set: { var changed = scene; changed.tonic = $0; library.updateScene(changed) })) {
                ForEach(0..<12, id: \.self) { Text(MusicTheory.noteName($0, prefersFlats: MusicTheory.prefersFlats(tonic: scene.tonic))).tag($0) }
            }.frame(width: 120)
            Picker("Tonleiter", selection: Binding(get: { scene.scale }, set: { var changed = scene; changed.scale = $0; library.updateScene(changed) })) {
                ForEach(ScaleKind.allCases) { Text($0.title).tag($0) }
            }.frame(width: 180)
            Picker("Bereich", selection: $workspaceMode) { ForEach(WorkspaceMode.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).frame(maxWidth: 480)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func editor(_ selectedScore: Score, scene selectedScene: ScoreScene) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker("Szene", selection: Binding<Int64?>(get: { library.selectedSceneID }, set: { library.selectScene($0) })) {
                    ForEach(library.scenes) { scene in Text(scene.title).tag(Optional(scene.id)) }
                }
                Button("Szene hinzufügen", systemImage: "plus") { library.addScene() }.labelStyle(.iconOnly)
                Stepper("\(selectedScene.tempo) BPM", value: Binding(
                    get: { selectedScene.tempo },
                    set: { library.updateScene(ScoreScene(id: selectedScene.id, scoreID: selectedScene.scoreID, title: selectedScene.title, tempo: $0, position: selectedScene.position, tonic: selectedScene.tonic, scale: selectedScene.scale)) }
                ), in: 20...400).frame(width: 150)
            }
            TextField("Szenenname", text: Binding(
                get: { selectedScene.title },
                set: { library.updateScene(ScoreScene(id: selectedScene.id, scoreID: selectedScene.scoreID, title: $0, tempo: selectedScene.tempo, position: selectedScene.position, tonic: selectedScene.tonic, scale: selectedScene.scale)) }
            ))
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) { ForEach(library.tracks) { track in trackEditor(track) } }
            }
            Text("Partitur, Szenen und Spuren werden automatisch in SQLite gespeichert.").font(.caption).foregroundStyle(.secondary)
        }
        .padding(18)
    }

    private func trackEditor(_ track: ScoreTrack) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("Spurname", text: Binding(get: { track.name }, set: {
                    library.updateTrack(ScoreTrack(id: track.id, sceneID: track.sceneID, name: $0, abc: track.abc, position: track.position, scaleOverride: track.scaleOverride))
                })).font(.headline)
                Picker("Tonleiter", selection: Binding<String>(get: { track.scaleOverride?.rawValue ?? "scene" }, set: { value in
                    library.updateTrack(ScoreTrack(id: track.id, sceneID: track.sceneID, name: track.name, abc: track.abc, position: track.position, scaleOverride: ScaleKind(rawValue: value)))
                })) {
                    Text("Wie Szene").tag("scene")
                    ForEach(ScaleKind.allCases) { Text($0.title).tag($0.rawValue) }
                }.frame(width: 180)
            }
            TextEditor(text: Binding(get: { track.abc }, set: {
                library.updateTrack(ScoreTrack(id: track.id, sceneID: track.sceneID, name: track.name, abc: $0, position: track.position, scaleOverride: track.scaleOverride))
            }))
            .font(.system(.body, design: .monospaced)).frame(minHeight: 84).scrollContentBackground(.hidden).padding(6)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func preview(_ selectedScore: Score, scene selectedScene: ScoreScene) -> some View {
        let abc = ABCScoreBuilder.build(score: selectedScore, scene: selectedScene, tracks: library.tracks, chords: library.chordEvents)
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Button("Alles", systemImage: "play.fill") { score.run(.play) }
                    Button("Stopp", systemImage: "stop.fill") { score.run(.stop) }
                    if score.measureCount > 0 {
                        Picker("Takt", selection: $measure) { ForEach(0..<score.measureCount, id: \.self) { Text("\($0 + 1)").tag($0) } }.frame(width: 110)
                        Button("Takt", systemImage: "play.fill") { score.run(.playMeasure(measure)) }
                    }
                    Spacer()
                    Button("MIDI exportieren", systemImage: "square.and.arrow.up") { score.run(.exportMIDI) }
                }.buttonStyle(.bordered).disabled(!score.isReady)
                midiStatus
                ScoreWebView(abc: abc, height: $scoreHeight, controller: score).frame(height: min(max(scoreHeight, 220), 1_200))
                if let error = score.errorMessage ?? midi.errorMessage { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) }
            }.padding(18)
        }
    }

    private var midiStatus: some View {
        let active = midi.isActive(sessionID)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                if midi.sourceNames.isEmpty {
                    Button("MIDI erneut suchen", systemImage: "arrow.clockwise") { midi.activate(sessionID, reportsMissingInput: true) }
                    Text("Kein Keyboard erkannt").foregroundStyle(.secondary)
                } else {
                    Label(active ? "Keyboard aktiv" : "Partitur anklicken", systemImage: "pianokeys")
                    Text(midi.sourceNames.joined(separator: " · ")).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            if active {
                Text(midi.notes.isEmpty ? "Spiele auf dem Keyboard …" : midi.notes.map { MusicNames.note($0.number) }.joined(separator: " · ")).font(.callout.monospacedDigit()).foregroundStyle(midi.notes.isEmpty ? .secondary : .primary)
            }
        }
    }
}
