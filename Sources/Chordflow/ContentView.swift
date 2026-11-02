import SwiftUI

struct ContentView: View {
    @ObservedObject var library: ScoreLibrary
    @StateObject private var midi = MIDIService.shared
    @StateObject private var score = ScoreController()
    @State private var scoreHeight: CGFloat = 360
    @State private var measure = 0
    @State private var sessionID = UUID()
    @State private var workspaceMode = WorkspaceMode.arrangement
    @State private var selectedArrangementChord: ChordEvent?
    @State private var showsTitleEditor = false
    @State private var titleDraft = ""
    @FocusState private var titleEditorFocused: Bool

    var body: some View {
        ZStack {
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

            if let event = selectedArrangementChord, let scene = library.selectedScene {
                ArrangementChordDetail(event: event, scene: scene, measure: measureNumber(for: event), update: { changed in
                    library.updateChord(changed)
                    selectedArrangementChord = changed
                    previewArrangementChord(changed)
                }, close: {
                    selectedArrangementChord = nil
                    MIDIService.shared.stopChordPreview()
                })
                .transition(.scale(scale: 0.96).combined(with: .opacity))
                .zIndex(10)
            }
        }
        .frame(minWidth: 1_100, minHeight: 700)
        .animation(.easeOut(duration: 0.16), value: selectedArrangementChord?.id)
        .onAppear {
            midi.start()
            score.transposeHandler = { [weak library, weak score] selection, semitones in
                guard let library, let score else { return }
                Self.transpose(selection, by: semitones, library: library, score: score)
            }
            score.selectionHandler = { [weak library, weak score] selection in
                guard let library, let score, let role = Self.toneRole(for: selection, library: library) else { return }
                score.setSelectedNoteColor(Self.cssColor(for: role))
            }
        }
        .onDisappear { midi.deactivate(sessionID) }
        .onChange(of: score.interactionCount) { _, _ in _ = midi.activate(sessionID) }
        .onChange(of: midi.notes) { _, notes in
            guard midi.isActive(sessionID) else { return }
            score.showMIDINotes(notes.map(\.number))
        }
        .onChange(of: midi.activeSessionID) { _, active in if active != sessionID { score.showMIDINotes([]) } }
        .onChange(of: library.selectedSceneID) { _, _ in
            selectedArrangementChord = nil
            score.clearHighlight()
            score.clearSelectedNote()
        }
        .onChange(of: workspaceMode) { _, mode in if mode != .arrangement { selectedArrangementChord = nil } }
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
                    else { TheoryWorkspaceView(library: library, scene: selectedScene, mode: workspaceMode, scoreController: score, selectedArrangementChord: $selectedArrangementChord) }
                }.frame(minWidth: 480, idealWidth: 650)
                preview(selectedScore, scene: selectedScene).frame(minWidth: 520)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func sceneToolbar(_ selectedScore: Score, scene: ScoreScene) -> some View {
        VStack(spacing: 7) {
            HStack(spacing: 10) {
                Button {
                    titleDraft = selectedScore.title
                    showsTitleEditor = true
                } label: {
                    HStack(spacing: 7) {
                        Text(selectedScore.title).font(.headline).lineLimit(1)
                        Image(systemName: "pencil").font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(width: 205, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .help("Partiturtitel bearbeiten")
                .popover(isPresented: $showsTitleEditor, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Partiturtitel bearbeiten").font(.headline)
                        TextField("Partiturtitel", text: $titleDraft)
                            .textFieldStyle(.roundedBorder)
                            .focused($titleEditorFocused)
                            .onSubmit { saveTitle() }
                        HStack {
                            Spacer()
                            Button("Abbrechen") { showsTitleEditor = false }
                            Button("Sichern") { saveTitle() }
                                .buttonStyle(.borderedProminent)
                                .disabled(titleDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    .padding(16)
                    .frame(width: 320)
                    .onAppear { titleEditorFocused = true }
                }
                Picker("Szene", selection: Binding<Int64?>(get: { library.selectedSceneID }, set: { library.selectScene($0) })) {
                    ForEach(library.scenes) { item in Text(item.title).tag(Optional(item.id)) }
                }.frame(width: 160)
                Button("Szene hinzufügen", systemImage: "plus") { library.addScene() }.labelStyle(.iconOnly)
                Stepper("\(scene.tempo) BPM", value: Binding(get: { scene.tempo }, set: { var changed = scene; changed.tempo = $0; library.updateScene(changed) }), in: 20...400).frame(width: 145)
                let beats = ABCScoreBuilder.sceneBeats(tracks: library.tracks, chords: library.chordEvents)
                Label("\(max(1, (beats + 3) / 4)) Takte", systemImage: "timeline.selection").font(.callout).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Picker("Bereich", selection: $workspaceMode) { ForEach(WorkspaceMode.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).frame(maxWidth: 520)
            }
            HStack(spacing: 12) {
                Label("Harmonie", systemImage: "music.quarternote.3").font(.callout.weight(.semibold)).foregroundStyle(.secondary)
                Picker("Grundton", selection: Binding(get: { scene.tonic }, set: { var changed = scene; changed.tonic = $0; library.updateScene(changed) })) {
                    ForEach(0..<12, id: \.self) { Text(MusicTheory.noteName($0, prefersFlats: MusicTheory.prefersFlats(tonic: scene.tonic))).tag($0) }
                }.frame(width: 130)
                Picker("Tonleiter", selection: Binding(get: { scene.scale }, set: { var changed = scene; changed.scale = $0; library.updateScene(changed) })) {
                    ForEach(ScaleKind.allCases) { Text($0.title).tag($0) }
                }.frame(width: 210)
                Text(MusicTheory.scaleNames(tonic: scene.tonic, kind: scene.scale).joined(separator: " · ")).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func saveTitle() {
        let title = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        library.updateScoreTitle(title)
        showsTitleEditor = false
    }

    private func editor(_ selectedScore: Score, scene selectedScene: ScoreScene) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Spuren für \(selectedScene.title)").font(.title2.bold())
            TextField("Szenenname", text: Binding(
                get: { selectedScene.title },
                set: { library.updateScene(ScoreScene(id: selectedScene.id, scoreID: selectedScene.scoreID, title: $0, tempo: selectedScene.tempo, position: selectedScene.position, tonic: selectedScene.tonic, scale: selectedScene.scale)) }
            ))
            let scaleKinds = library.tracks.map { $0.scaleOverride ?? selectedScene.scale }
            let common = MusicTheory.commonScaleTones(tonic: selectedScene.tonic, kinds: scaleKinds)
            GroupBox("Gemeinsamer Tonvorrat") {
                VStack(alignment: .leading, spacing: 5) {
                    Text(common.map { MusicTheory.noteName($0, prefersFlats: MusicTheory.prefersFlats(tonic: selectedScene.tonic)) }.joined(separator: " · "))
                        .font(.headline)
                    Text("Diese Töne liegen in allen Spurtonleitern. Sie eignen sich als Verbindungstöne; andere Töne können als Akkordfarbe oder Spannung trotzdem sinnvoll sein.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
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
                    library.updateTrack(ScoreTrack(id: track.id, sceneID: track.sceneID, name: $0, abc: track.abc, position: track.position, scaleOverride: track.scaleOverride, endMode: track.endMode))
                })).font(.headline)
                Picker("Tonleiter", selection: Binding<String>(get: { track.scaleOverride?.rawValue ?? "scene" }, set: { value in
                    library.updateTrack(ScoreTrack(id: track.id, sceneID: track.sceneID, name: track.name, abc: track.abc, position: track.position, scaleOverride: ScaleKind(rawValue: value), endMode: track.endMode))
                })) {
                    Text("Wie Szene").tag("scene")
                    ForEach(ScaleKind.allCases) { Text($0.title).tag($0.rawValue) }
                }.frame(width: 180)
                Picker("Spurende", selection: Binding(get: { track.endMode }, set: { value in
                    var changed = track; changed.endMode = value; library.updateTrack(changed)
                })) {
                    ForEach(TrackEndMode.allCases) { Text($0.title).tag($0) }
                }
                .frame(width: 210)
            }
            TextEditor(text: Binding(get: { track.abc }, set: {
                library.updateTrack(ScoreTrack(id: track.id, sceneID: track.sceneID, name: track.name, abc: $0, position: track.position, scaleOverride: track.scaleOverride, endMode: track.endMode))
            }))
            .font(.system(.body, design: .monospaced)).frame(minHeight: 84).scrollContentBackground(.hidden).padding(6)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func preview(_ selectedScore: Score, scene selectedScene: ScoreScene) -> some View {
        let abc = ABCScoreBuilder.build(score: selectedScore, scene: selectedScene, tracks: library.tracks, chords: library.chordEvents)
        let chordStyles = scoreChordStyles()
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
                selectedNoteStatus(scene: selectedScene)
                if !chordStyles.isEmpty { ChordColorLegend() }
                ScoreWebView(abc: abc, height: $scoreHeight, controller: score, chordStyles: chordStyles).frame(height: min(max(scoreHeight, 220), 1_200))
                if let error = score.errorMessage ?? midi.errorMessage { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) }
            }.padding(18)
        }
    }

    private func scoreChordStyles() -> [ScoreChordStyle] {
        guard let trackIndex = library.tracks.firstIndex(where: { $0.name.compare("Akkorde", options: .caseInsensitive) == .orderedSame }) else { return [] }
        return library.chordEvents.enumerated().map { noteIndex, event in
            let analysis = MusicTheory.analyzeVoicing(event.chord)
            return ScoreChordStyle(trackIndex: trackIndex, noteIndex: noteIndex, role: analysis.role)
        }
    }

    @ViewBuilder private func selectedNoteStatus(scene: ScoreScene) -> some View {
        if let selection = score.selectedNote, library.tracks.indices.contains(selection.trackIndex) {
            let track = library.tracks[selection.trackIndex]
            let scale = track.scaleOverride ?? scene.scale
            let analysis = MusicTheory.analyzeTone(selection.midi, tonic: scene.tonic, sceneScale: scene.scale, trackScale: scale, chord: chord(atMeasure: selection.measure)?.chord)
            HStack(spacing: 8) {
                Label("\(track.name): \(MusicTheory.pitchName(selection.midi, prefersFlats: MusicTheory.prefersFlats(tonic: scene.tonic)))", systemImage: toneIcon(analysis.role))
                    .foregroundStyle(toneColor(analysis.role))
                Text("\(analysis.title): \(analysis.explanation)")
                Text("↑/↓ verschiebt um einen Halbton").foregroundStyle(.secondary)
            }
            .font(.callout)
        }
    }

    private func chord(atMeasure measure: Int) -> ChordEvent? {
        let beat = max(0, measure) * 4
        var start = 0
        for event in library.chordEvents {
            if beat < start + event.beats { return event }
            start += event.beats
        }
        return nil
    }

    private func measureNumber(for event: ChordEvent) -> Int {
        library.chordEvents.filter { $0.position < event.position }.reduce(0) { $0 + $1.beats } / 4 + 1
    }

    private func previewArrangementChord(_ event: ChordEvent) {
        MIDIService.shared.previewChord(event.pitches)
        score.highlightChord(measure: measureNumber(for: event) - 1, pitches: event.pitches)
    }

    private func toneColor(_ role: ToneRole) -> Color {
        switch role { case .chordTone: .blue; case .chordColor: .orange; case .common: .green; case .scene: .purple; case .track: .cyan; case .tension: .red }
    }

    private func toneIcon(_ role: ToneRole) -> String {
        switch role { case .chordTone: "music.note"; case .chordColor: "paintpalette.fill"; case .common: "link.circle.fill"; case .scene: "circle.hexagongrid.fill"; case .track: "music.note.list"; case .tension: "exclamationmark.triangle.fill" }
    }

    private static func toneRole(for selection: ScoreNoteSelection, library: ScoreLibrary) -> ToneRole? {
        guard let scene = library.selectedScene, library.tracks.indices.contains(selection.trackIndex) else { return nil }
        let track = library.tracks[selection.trackIndex]
        let beat = max(0, selection.measure) * 4
        var start = 0
        var chord: TheoryChord?
        for event in library.chordEvents {
            if beat < start + event.beats { chord = event.chord; break }
            start += event.beats
        }
        return MusicTheory.analyzeTone(selection.midi, tonic: scene.tonic, sceneScale: scene.scale, trackScale: track.scaleOverride ?? scene.scale, chord: chord).role
    }

    private static func cssColor(for role: ToneRole) -> String {
        switch role { case .chordTone: "#0a84ff"; case .chordColor: "#ff9f0a"; case .common: "#30d158"; case .scene: "#bf5af2"; case .track: "#64d2ff"; case .tension: "#ff453a" }
    }

    private static func transpose(_ selection: ScoreNoteSelection, by semitones: Int, library: ScoreLibrary, score: ScoreController) {
        guard library.tracks.indices.contains(selection.trackIndex) else { score.report("Die gewählte Spur existiert nicht mehr."); return }
        let newMIDI = selection.midi + semitones
        guard (0...127).contains(newMIDI) else { score.report("Die Tonhöhe liegt außerhalb des MIDI-Bereichs."); return }
        let track = library.tracks[selection.trackIndex]
        var changedSelection = selection
        if !library.chordEvents.isEmpty, track.name.compare("Bass", options: .caseInsensitive) == .orderedSame {
            guard library.chordEvents.indices.contains(selection.noteIndex) else { score.report("Der gewählte Basston konnte keinem Akkord zugeordnet werden."); return }
            var event = library.chordEvents[selection.noteIndex]; event.bassPitch = newMIDI; library.updateChord(event)
        } else if !library.chordEvents.isEmpty, track.name.compare("Akkorde", options: .caseInsensitive) == .orderedSame {
            guard library.chordEvents.indices.contains(selection.noteIndex) else { score.report("Der gewählte Akkord existiert nicht mehr."); return }
            var event = library.chordEvents[selection.noteIndex]
            guard event.pitches.indices.contains(selection.pitchIndex) else { score.report("Der gewählte Akkordton existiert nicht mehr."); return }
            event.pitches[selection.pitchIndex] = newMIDI; event.pitches.sort(); library.updateChord(event)
            changedSelection.pitchIndex = event.pitches.firstIndex(of: newMIDI) ?? selection.pitchIndex
        } else {
            guard let abc = ABCNoteEditor.replacingNote(in: track.abc, eventIndex: selection.noteIndex, pitchIndex: selection.pitchIndex, with: newMIDI) else {
                score.report("Die gewählte Note konnte im ABC-Text der Spur \(track.name) nicht gefunden werden."); return
            }
            var changed = track; changed.abc = abc; library.updateTrack(changed)
        }
        changedSelection.midi = newMIDI
        score.updateSelectedNote(changedSelection)
        MIDIService.shared.previewChord([newMIDI], duration: .milliseconds(500))
    }

    private var midiStatus: some View {
        let active = midi.isActive(sessionID)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                if midi.sourceNames.isEmpty {
                    Button("MIDI erneut suchen", systemImage: "arrow.clockwise") {
                        _ = midi.activate(sessionID, reportsMissingInput: true)
                    }
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

private struct ChordColorLegend: View {
    var body: some View {
        HStack(spacing: 14) {
            legend("Grundstellung", color: .blue)
            legend("Umkehrung", color: .purple)
            legend("veränderte Akkordstruktur", color: .orange)
            Text("Die Auswahl wird weiterhin rot hervorgehoben.").foregroundStyle(.secondary)
        }
        .font(.caption)
    }

    private func legend(_ title: String, color: Color) -> some View {
        Label { Text(title) } icon: { Circle().fill(color).frame(width: 8, height: 8) }
    }
}
