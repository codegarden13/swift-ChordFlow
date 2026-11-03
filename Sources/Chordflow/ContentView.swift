import SwiftUI

struct ContentView: View {
    @ObservedObject var library: ScoreLibrary
    @StateObject private var midi = MIDIService.shared
    @StateObject private var score = ScoreController()
    @State private var scoreHeight: CGFloat = 360
    @State private var measure = 0
    @State private var sessionID = UUID()
    @State private var workspaceMode = WorkspaceMode.arrangement
    @State private var experienceMode = ExperienceMode.simple
    @State private var selectedArrangementChord: ChordEvent?
    @State private var showsArrangementDetail = false
    @State private var showsTitleEditor = false
    @State private var titleDraft = ""
    @State private var usesScoreSelectionRectangle = false
    @State private var showsTimelineCreator = false
    @State private var showsWholeScore = false
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
            .blur(radius: showsArrangementDetail && !showsWholeScore ? 7 : 0)
            .animation(.easeOut(duration: 0.18), value: showsWholeScore)

            arrangementChordOverlay
        }
        .frame(minWidth: 1_100, minHeight: 700)
        .tint(ChordflowDesign.actionTeal)
        .toolbar { windowToolbar }
        .animation(.easeOut(duration: 0.16), value: selectedArrangementChord?.id)
        .onAppear {
            midi.start()
            score.transposeHandler = { [weak library, weak score] selection, semitones in
                guard let library, let score else { return }
                Self.transpose(selection, by: semitones, library: library, score: score)
            }
            score.multiTransposeHandler = { [weak library, weak score] selections, semitones in
                guard let library, let score else { return }
                Self.transpose(selections, by: semitones, library: library, score: score)
            }
            score.selectionHandler = { [weak library, weak score] selection in
                guard let library, let score, let role = Self.toneRole(for: selection, library: library) else { return }
                score.setSelectedNoteColor(Self.cssColor(for: role))
            }
        }
        .onDisappear { midi.deactivate(sessionID) }
        .onChange(of: score.interactionCount) { _, _ in _ = midi.activate(sessionID) }
        .onChange(of: score.playingMeasure) { _, playingMeasure in
            guard let playingMeasure else { return }
            measure = playingMeasure
        }
        .onChange(of: score.selectedNotes) { _, selections in
            if let selectedMeasure = selections.first?.measure { measure = selectedMeasure }
        }
        .onChange(of: measure) { _, selectedMeasure in
            score.revealMeasure(selectedMeasure)
        }
        .onChange(of: showsWholeScore) { _, showsWholeScore in
            guard showsWholeScore else { return }
            focusWholeScoreOnCurrentChord()
        }
        .onChange(of: midi.notes) { _, notes in
            guard midi.isActive(sessionID) else { return }
            score.showMIDINotes(notes.map(\.number))
        }
        .onChange(of: midi.activeSessionID) { _, active in if active != sessionID { score.showMIDINotes([]) } }
        .onChange(of: library.selectedSceneID) { _, _ in
            measure = 0
            selectedArrangementChord = nil
            showsArrangementDetail = false
            showsWholeScore = false
            score.clearHighlight()
            score.clearSelectedNote()
        }
        .onChange(of: workspaceMode) { _, mode in
            if mode != .arrangement {
                selectedArrangementChord = nil
                showsArrangementDetail = false
                showsWholeScore = false
            }
        }
        .sheet(isPresented: $showsTimelineCreator) {
            TimelineScoreCreator { title, startYear, endYear in
                library.addTimelineScore(title: title, startYear: startYear, endYear: endYear)
            }
        }
        .alert("Aktion nicht möglich", isPresented: Binding(get: { library.errorMessage != nil }, set: { if !$0 { library.errorMessage = nil } })) {
            Button("OK", role: .cancel) { library.errorMessage = nil }
        } message: { Text(library.errorMessage ?? "Unbekannter Fehler") }
    }

    @ViewBuilder private var arrangementChordOverlay: some View {
        if showsArrangementDetail,
           let selectedArrangementChord,
           let event = library.chordEvents.first(where: { $0.id == selectedArrangementChord.id }),
           let scene = library.selectedScene {
            let initialDraft = library.chordDraft(id: event.id) ?? event
            Group {
                if showsWholeScore {
                    wholeScoreFloatingBar(event: event)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .padding(.top, 18)
                } else {
                    ZStack {
                        Color.black.opacity(0.10)
                            .ignoresSafeArea()
                            .onTapGesture(perform: closeArrangementChord)
                        ArrangementChordDetail(
                            event: event,
                            initialDraft: initialDraft,
                            scene: scene,
                            measure: measure + 1,
                            showsWholeScore: $showsWholeScore,
                            stage: stageArrangementDraft,
                            save: saveArrangementDraft,
                            discard: { discardArrangementDraft(event) },
                            canNavigate: canNavigateArrangementChord,
                            navigate: navigateArrangementChord,
                            canNavigateMeasure: canNavigateArrangementMeasure,
                            navigateMeasure: navigateArrangementMeasure,
                            close: closeArrangementChord
                        )
                    }
                }
            }
            .transition(.scale(scale: 0.98).combined(with: .opacity))
            .zIndex(10)
        }
    }

    private func wholeScoreFloatingBar(event: ChordEvent) -> some View {
        HStack(spacing: 12) {
            Button("Akkordfenster schließen", systemImage: "xmark.circle.fill", action: closeArrangementChord)
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            Button("Vorheriger Akkord", systemImage: "backward.end") { navigateArrangementChord(by: -1) }
                .labelStyle(.iconOnly)
                .keyboardShortcut(.leftArrow, modifiers: [.option])
                .disabled(!canNavigateArrangementChord(by: -1))
                .help("Zum vorherigen Akkord (⌥←)")
            Button("Vorheriger Takt", systemImage: "chevron.left") { navigateArrangementMeasure(by: -1) }
                .labelStyle(.iconOnly)
                .keyboardShortcut(.leftArrow, modifiers: [])
                .disabled(!canNavigateArrangementMeasure(by: -1))
                .help("Einen Takt zurück (←)")
            VStack(alignment: .leading, spacing: 1) {
                Text("\(event.chord.symbol) · Takt \(measure + 1)")
                    .font(ChordflowDesign.heading(.headline, size: 18))
                Text("Partituransicht")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Picker("Notenblatt", selection: $showsWholeScore) {
                Text("Fokus").tag(false)
                Text("Ganze Partitur").tag(true)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 220)
            Button("Nächster Takt", systemImage: "chevron.right") { navigateArrangementMeasure(by: 1) }
                .labelStyle(.iconOnly)
                .keyboardShortcut(.rightArrow, modifiers: [])
                .disabled(!canNavigateArrangementMeasure(by: 1))
                .help("Einen Takt vor (→)")
            Button("Nächster Akkord", systemImage: "forward.end") { navigateArrangementChord(by: 1) }
                .labelStyle(.iconOnly)
                .keyboardShortcut(.rightArrow, modifiers: [.option])
                .disabled(!canNavigateArrangementChord(by: 1))
                .help("Zum nächsten Akkord (⌥→)")
        }
        .buttonStyle(.bordered)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(.separator.opacity(0.55)))
        .shadow(color: .black.opacity(0.18), radius: 12, y: 5)
    }

    private func stageArrangementDraft(_ changed: ChordEvent) {
        library.stageChordDraft(changed)
        selectedArrangementChord = changed
        previewArrangementChord(changed)
    }

    private func saveArrangementDraft(_ changed: ChordEvent) {
        library.stageChordDraft(changed)
        guard library.saveChordDraft(id: changed.id), let saved = library.chordEvents.first(where: { $0.id == changed.id }) else { return }
        selectedArrangementChord = saved
        previewArrangementChord(saved)
    }

    private func discardArrangementDraft(_ saved: ChordEvent) {
        library.discardChordDraft(id: saved.id)
        selectedArrangementChord = saved
        previewArrangementChord(saved)
    }

    private func closeArrangementChord() {
        showsArrangementDetail = false
        showsWholeScore = false
        MIDIService.shared.stopChordPreview()
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: Binding<Int64?>(get: { library.selectedScoreID }, set: { library.selectScore($0) })) {
                Section("Partituren") {
                    ForEach(library.scores) { item in Label(item.title, systemImage: "music.note.list").tag(Optional(item.id)) }
                }
            }
            HStack {
                Menu("Partitur hinzufügen", systemImage: "plus") {
                    Button("Neue Musikpartitur", systemImage: "music.note.list") { library.addScore() }
                    Button("Neue Zeitachsen-Partitur …", systemImage: "calendar.day.timeline.leading") { showsTimelineCreator = true }
                }
                .labelStyle(.iconOnly)
                .menuStyle(.borderlessButton)
                .help("Neue Musik- oder Zeitachsen-Partitur anlegen")
                Button("Partitur löschen", systemImage: "trash", role: .destructive) { library.deleteSelectedScore() }.labelStyle(.iconOnly).disabled(library.selectedScoreID == nil)
                    .help("Ausgewählte Partitur löschen")
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
                    else { TheoryWorkspaceView(library: library, scene: selectedScene, mode: workspaceMode, experienceMode: experienceMode, scoreController: score, selectedArrangementChord: $selectedArrangementChord, selectedScoreMeasure: $measure, showsArrangementDetail: $showsArrangementDetail) }
                }.frame(minWidth: 720, idealWidth: 920)
                preview(selectedScore, scene: selectedScene).frame(minWidth: 520)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func sceneToolbar(_ selectedScore: Score, scene: ScoreScene) -> some View {
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
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ChordflowDesign.actionTeal.opacity(0.045))
    }

    @ToolbarContentBuilder private var windowToolbar: some ToolbarContent {
        if let selectedScore = library.selectedScore, let scene = library.selectedScene {
            ToolbarItemGroup(placement: .navigation) {
                scoreTitleButton(selectedScore)
            }
            ToolbarItemGroup(placement: .principal) {
                Picker("Abschnitt", selection: Binding<Int64?>(get: { library.selectedSceneID }, set: { library.selectScene($0) })) {
                    ForEach(library.scenes) { item in Text(item.title).tag(Optional(item.id)) }
                }
                .frame(width: 150)
                .help("Abschnitt des Stücks wählen; entspricht beim Ableton-Workflow einer Szene")
                Button("Abschnitt hinzufügen", systemImage: "plus") { library.addScene() }
                    .labelStyle(.iconOnly)
                    .help("Einen weiteren musikalischen Abschnitt hinzufügen")
                Stepper("\(scene.tempo) BPM", value: Binding(get: { scene.tempo }, set: { var changed = scene; changed.tempo = $0; library.updateScene(changed) }), in: 20...400)
                    .frame(width: 135)
                Label("\(sceneMeasureCount) Takte", systemImage: "timeline.selection")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Picker("Bedienung", selection: $experienceMode) {
                    ForEach(ExperienceMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 180)
                Picker("Bereich", selection: $workspaceMode) {
                    ForEach(WorkspaceMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 360)
            }
        }
    }

    private func scoreTitleButton(_ score: Score) -> some View {
        Button {
            titleDraft = score.title
            showsTitleEditor = true
        } label: {
            HStack(spacing: 7) {
                Text(score.title).font(.headline).lineLimit(1)
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
    }

    private var sceneMeasureCount: Int {
        let beats = ABCScoreBuilder.sceneBeats(tracks: library.tracks, chords: library.chordEvents)
        return max(1, (beats + 3) / 4)
    }

    private func saveTitle() {
        let title = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        library.updateScoreTitle(title)
        showsTitleEditor = false
    }

    private func editor(_ selectedScore: Score, scene selectedScene: ScoreScene) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Spuren für \(selectedScene.title)").font(ChordflowDesign.heading(.title2, size: 27))
            TextField("Abschnittsname", text: Binding(
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
            Text("Partitur, Abschnitte und Spuren werden automatisch in SQLite gespeichert.").font(.caption).foregroundStyle(.secondary)
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
                    Text("Wie Abschnitt").tag("scene")
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
        let abc = ABCScoreBuilder.build(score: selectedScore, scene: selectedScene, tracks: library.tracks, chords: library.displayedChordEvents)
        let chordStyles = scoreChordStyles()
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                measurePills(scene: selectedScene)
                HStack(spacing: 10) {
                    Button("\(selectedScore.title) hören", systemImage: "speaker.wave.2.fill") {
                        score.run(.play)
                    }
                    .foregroundStyle(score.isPlayingFullScore ? ChordflowDesign.focusGreen : ChordflowDesign.actionTeal)
                    .help("\(selectedScore.title) abspielen")
                    Button("Stopp", systemImage: "stop.fill") { score.run(.stop) }
                    Divider().frame(height: 18)
                    Text("Notenblatt")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Picker("Partituransicht", selection: $showsWholeScore) {
                        Text(experienceMode == .simple ? "Ein Takt" : "Fokus").tag(false)
                        Text("Ganze Partitur").tag(true)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 230)
                    if experienceMode == .advanced {
                        Divider().frame(height: 18)
                        Toggle("Auswahlrahmen", systemImage: "rectangle.dashed", isOn: Binding(
                            get: { usesScoreSelectionRectangle },
                            set: { enabled in
                                usesScoreSelectionRectangle = enabled
                                score.setMarqueeSelectionEnabled(enabled)
                            }
                        ))
                        .toggleStyle(.button)
                        .help("Aktivieren und in der Partitur einen Rahmen um mehrere Noten ziehen; alternativ mit gedrückter Umschalttaste ziehen")
                        Button("Gleiche Töne", systemImage: "equal.circle") { score.selectMatchingNotes() }
                            .disabled(score.selectedNote == nil)
                            .help("Alle Noten derselben Tonhöhe in der ausgewählten Notenzeile markieren")
                        Spacer()
                        Button("MIDI exportieren", systemImage: "square.and.arrow.up") { score.run(.exportMIDI) }
                            .labelStyle(.iconOnly)
                            .help("Partitur als MIDI-Datei exportieren")
                    } else {
                        Spacer()
                    }
                }
                .buttonStyle(.bordered)
                .padding(8)
                .background(ChordflowDesign.actionTeal.opacity(0.055), in: RoundedRectangle(cornerRadius: 11))
                .disabled(!score.isReady)
                if experienceMode == .advanced {
                    midiStatus
                    selectedNoteStatus(scene: selectedScene)
                    if !chordStyles.isEmpty { ChordColorLegend() }
                }
                ScoreWebView(
                    abc: abc,
                    height: $scoreHeight,
                    controller: score,
                    chordStyles: chordStyles,
                    centersMeasures: !showsWholeScore
                )
                    .frame(height: showsWholeScore ? min(max(scoreHeight, 420), 1_200) : 620)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(.separator.opacity(0.45)))
                if let error = score.errorMessage ?? midi.errorMessage { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) }
            }.padding(18)
        }
    }

    private func measurePills(scene: ScoreScene) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 8) {
                    ForEach(0..<sceneMeasureCount, id: \.self) { index in
                        let event = displayedChord(atMeasure: index)
                        HStack(spacing: 6) {
                            Button {
                                measure = index
                            } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 5) {
                                    Text("Takt \(index + 1)")
                                        .font(.caption.weight(.semibold))
                                    if event?.isDraft == true {
                                        Circle()
                                            .fill(.pink)
                                            .frame(width: 6, height: 6)
                                            .accessibilityLabel("Ungespeicherter Entwurf")
                                    }
                                }
                                HStack(spacing: 5) {
                                    Text(event?.chord.symbol ?? "–")
                                        .font(.callout.weight(.semibold))
                                    if let event,
                                       let degree = MusicTheory.romanDegree(root: event.root, tonic: scene.tonic, kind: scene.scale) {
                                        Text(degree)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .frame(minWidth: 70, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .help(measurePillHelp(index: index, event: event, scene: scene))
                            Button {
                                measure = index
                                score.run(.playMeasure(index))
                            } label: {
                                Image(systemName: "speaker.wave.2.fill")
                                    .font(.caption.weight(.semibold))
                                    .frame(width: 24, height: 24)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(score.playingMeasure == index ? ChordflowDesign.focusGreen : ChordflowDesign.actionTeal)
                            .contentShape(Circle())
                            .help("Takt \(index + 1) hören")
                        }
                        .padding(.leading, 11)
                        .padding(.trailing, 7)
                        .padding(.vertical, 7)
                        .background(measurePillColor(event).opacity(measure == index ? 0.16 : 0.09), in: Capsule())
                        .overlay {
                            Capsule()
                                .stroke(measure == index ? ChordflowDesign.focusGreen : Color.secondary.opacity(0.20), lineWidth: measure == index ? 2 : 1)
                        }
                        .shadow(color: measure == index ? ChordflowDesign.focusGreen.opacity(0.45) : .clear, radius: 7)
                        .id(index)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 7)
            }
            .scrollIndicators(.hidden)
            .onAppear { proxy.scrollTo(measure, anchor: .center) }
            .onChange(of: measure) { _, selectedMeasure in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(selectedMeasure, anchor: .center)
                }
            }
        }
        .frame(height: 62)
    }

    private func measurePillHelp(index: Int, event: ChordEvent?, scene: ScoreScene) -> String {
        guard let event else { return "Takt \(index + 1) · kein Akkord" }
        let degree = MusicTheory.romanDegree(root: event.root, tonic: scene.tonic, kind: scene.scale) ?? "chromatisch"
        let draft = event.isDraft ? " · ungespeicherter Entwurf" : ""
        return "Takt \(index + 1) · \(event.chord.symbol) · Stufe \(degree)\(draft)"
    }

    private func measurePillColor(_ event: ChordEvent?) -> Color {
        guard let event else { return .secondary }
        if event.isDraft { return ChordflowDesign.alteredPink }
        switch MusicTheory.analyzeVoicing(event.chord).role {
        case .standard: return ChordflowDesign.chordToneBlue
        case .inversion: return ChordflowDesign.inversionPurple
        case .altered: return ChordflowDesign.alteredPink
        }
    }

    private func displayedChord(atMeasure measure: Int) -> ChordEvent? {
        let beat = max(0, measure) * 4
        return library.displayedChordEvents.first { $0.startBeat <= beat && $0.startBeat + $0.beats > beat }
    }

    private func scoreChordStyles() -> [ScoreChordStyle] {
        guard let trackIndex = library.tracks.firstIndex(where: {
            $0.name.localizedCaseInsensitiveContains("akkord") || $0.name.localizedCaseInsensitiveContains("chord")
        }) else { return [] }
        return library.displayedChordEvents.enumerated().map { noteIndex, event in
            let analysis = MusicTheory.analyzeVoicing(event.chord)
            return ScoreChordStyle(trackIndex: trackIndex, noteIndex: noteIndex, role: event.isDraft ? .altered : analysis.role)
        }
    }

    @ViewBuilder private func selectedNoteStatus(scene: ScoreScene) -> some View {
        if let selection = score.selectedNote, library.tracks.indices.contains(selection.trackIndex) {
            let track = library.tracks[selection.trackIndex]
            let scale = track.scaleOverride ?? scene.scale
            let analysis = MusicTheory.analyzeTone(selection.midi, tonic: scene.tonic, sceneScale: scene.scale, trackScale: scale, chord: chord(atMeasure: selection.measure)?.chord)
            HStack(spacing: 8) {
                Label(score.selectedNotes.count == 1
                      ? "\(track.name): \(MusicTheory.pitchName(selection.midi, prefersFlats: MusicTheory.prefersFlats(tonic: scene.tonic)))"
                      : "\(score.selectedNotes.count) Noten ausgewählt",
                      systemImage: toneIcon(analysis.role))
                    .foregroundStyle(toneColor(analysis.role))
                if score.selectedNotes.count == 1 { Text("\(analysis.title): \(analysis.explanation)") }
                Text("↑/↓ verschiebt \(score.selectedNotes.count == 1 ? "die Note" : "alle gemeinsam") um einen Halbton").foregroundStyle(.secondary)
            }
            .font(.callout)
        }
    }

    private func chord(atMeasure measure: Int) -> ChordEvent? {
        let beat = max(0, measure) * 4
        return library.displayedChordEvents.first { $0.startBeat <= beat && $0.startBeat + $0.beats > beat }
    }

    private func measureNumber(for event: ChordEvent) -> Int {
        event.startBeat / 4 + 1
    }

    private func previewArrangementChord(_ event: ChordEvent) {
        measure = measureNumber(for: event) - 1
        MIDIService.shared.previewChord(event.pitches)
        score.highlightChord(measure: measureNumber(for: event) - 1, pitches: event.pitches)
    }

    private func focusWholeScoreOnCurrentChord() {
        let focusedMeasure = measure
        let focusedPitches = selectedArrangementChord.flatMap { selected in
            library.displayedChordEvents.first(where: { $0.id == selected.id })?.pitches
        } ?? chord(atMeasure: focusedMeasure)?.pitches
        if let focusedPitches {
            score.highlightChord(measure: focusedMeasure, pitches: focusedPitches)
        }
        score.revealMeasure(focusedMeasure)

        // Die Partitur erhält beim Wechsel eine andere Höhe. Nach diesem Layoutschritt
        // wird derselbe Takt erneut zentriert, damit er zuverlässig einrastet.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            if let focusedPitches {
                score.highlightChord(measure: focusedMeasure, pitches: focusedPitches)
            }
            score.revealMeasure(focusedMeasure)
        }
    }

    private func canNavigateArrangementChord(by offset: Int) -> Bool {
        guard let selectedArrangementChord,
              let index = library.chordEvents.firstIndex(where: { $0.id == selectedArrangementChord.id }) else { return false }
        return library.chordEvents.indices.contains(index + offset)
    }

    private func navigateArrangementChord(by offset: Int) {
        guard let selectedArrangementChord,
              let index = library.chordEvents.firstIndex(where: { $0.id == selectedArrangementChord.id }),
              library.chordEvents.indices.contains(index + offset) else { return }
        let event = library.displayedChordEvents[index + offset]
        self.selectedArrangementChord = event
        previewArrangementChord(event)
    }

    private var arrangementMeasureCount: Int {
        max(1, (ABCScoreBuilder.sceneBeats(tracks: library.tracks, chords: library.chordEvents) + 3) / 4)
    }

    private func canNavigateArrangementMeasure(by offset: Int) -> Bool {
        (0..<arrangementMeasureCount).contains(measure + offset)
    }

    private func navigateArrangementMeasure(by offset: Int) {
        let target = measure + offset
        guard (0..<arrangementMeasureCount).contains(target) else { return }
        measure = target
        if let event = chord(atMeasure: target) {
            selectedArrangementChord = event
            MIDIService.shared.previewChord(event.pitches)
            score.highlightChord(measure: target, pitches: event.pitches)
        } else {
            score.highlightChord(measure: target, pitches: [])
            MIDIService.shared.stopChordPreview()
        }
    }

    private func toneColor(_ role: ToneRole) -> Color {
        switch role {
        case .chordTone: ChordflowDesign.chordToneBlue
        case .chordColor: ChordflowDesign.tensionOrange
        case .common: ChordflowDesign.commonMint
        case .scene: ChordflowDesign.inversionPurple
        case .track: .cyan
        case .tension: .red
        }
    }

    private func toneIcon(_ role: ToneRole) -> String {
        switch role { case .chordTone: "music.note"; case .chordColor: "paintpalette.fill"; case .common: "link.circle.fill"; case .scene: "circle.hexagongrid.fill"; case .track: "music.note.list"; case .tension: "exclamationmark.triangle.fill" }
    }

    private static func toneRole(for selection: ScoreNoteSelection, library: ScoreLibrary) -> ToneRole? {
        guard let scene = library.selectedScene, library.tracks.indices.contains(selection.trackIndex) else { return nil }
        let track = library.tracks[selection.trackIndex]
        let beat = max(0, selection.measure) * 4
        let chord = library.chordEvents.first { $0.startBeat <= beat && $0.startBeat + $0.beats > beat }?.chord
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

    private static func transpose(_ selections: [ScoreNoteSelection], by semitones: Int, library: ScoreLibrary, score: ScoreController) {
        guard !selections.isEmpty else { score.report("Die Notenauswahl ist leer."); return }
        guard selections.allSatisfy({ library.tracks.indices.contains($0.trackIndex) }) else { score.report("Mindestens eine ausgewählte Spur existiert nicht mehr."); return }
        guard selections.map({ $0.midi + semitones }).allSatisfy({ (0...127).contains($0) }) else { score.report("Mindestens eine Tonhöhe läge außerhalb des MIDI-Bereichs."); return }

        var changedTracks: [Int: ScoreTrack] = [:]
        var changedChords: [Int64: ChordEvent] = [:]
        var updatedSelections: [ScoreNoteSelection] = []

        for selection in selections {
            let track = library.tracks[selection.trackIndex]
            let newMIDI = selection.midi + semitones
            var updated = selection
            updated.midi = newMIDI
            if !library.chordEvents.isEmpty, track.name.compare("Bass", options: .caseInsensitive) == .orderedSame {
                guard library.chordEvents.indices.contains(selection.noteIndex) else { score.report("Ein ausgewählter Basston konnte keinem Akkord zugeordnet werden."); return }
                var event = changedChords[library.chordEvents[selection.noteIndex].id] ?? library.chordEvents[selection.noteIndex]
                event.bassPitch = newMIDI
                changedChords[event.id] = event
            } else if !library.chordEvents.isEmpty, track.name.compare("Akkorde", options: .caseInsensitive) == .orderedSame {
                guard library.chordEvents.indices.contains(selection.noteIndex) else { score.report("Ein ausgewählter Akkord existiert nicht mehr."); return }
                let original = library.chordEvents[selection.noteIndex]
                var event = changedChords[original.id] ?? original
                guard event.pitches.indices.contains(selection.pitchIndex) else { score.report("Ein ausgewählter Akkordton existiert nicht mehr."); return }
                event.pitches[selection.pitchIndex] = newMIDI
                changedChords[event.id] = event
            } else {
                var changed = changedTracks[selection.trackIndex] ?? track
                guard let abc = ABCNoteEditor.replacingNote(in: changed.abc, eventIndex: selection.noteIndex, pitchIndex: selection.pitchIndex, with: newMIDI) else {
                    score.report("Eine ausgewählte Note konnte im ABC-Text der Spur \(track.name) nicht gefunden werden."); return
                }
                changed.abc = abc
                changedTracks[selection.trackIndex] = changed
            }
            updatedSelections.append(updated)
        }

        var sortedChords: [Int64: ChordEvent] = [:]
        changedChords.values.forEach { event in
            var sorted = event
            sorted.pitches.sort()
            sortedChords[sorted.id] = sorted
            library.updateChord(sorted)
        }
        changedTracks.values.forEach(library.updateTrack)
        var usedPitchIndices: [Int64: Set<Int>] = [:]
        updatedSelections = updatedSelections.map { selection in
            let track = library.tracks[selection.trackIndex]
            guard track.name.compare("Akkorde", options: .caseInsensitive) == .orderedSame,
                  library.chordEvents.indices.contains(selection.noteIndex) else { return selection }
            let eventID = library.chordEvents[selection.noteIndex].id
            guard let event = sortedChords[eventID] else { return selection }
            let used = usedPitchIndices[eventID, default: []]
            guard let pitchIndex = event.pitches.indices.first(where: { event.pitches[$0] == selection.midi && !used.contains($0) }) else { return selection }
            usedPitchIndices[eventID, default: []].insert(pitchIndex)
            var adjusted = selection
            adjusted.pitchIndex = pitchIndex
            return adjusted
        }
        score.updateSelectedNotes(updatedSelections)
        MIDIService.shared.previewChord(updatedSelections.map(\.midi), duration: .milliseconds(500))
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

private struct TimelineScoreCreator: View {
    let create: (String, Int, Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = "Meine Zeitachse"
    @State private var startYear = Calendar.current.component(.year, from: .now) - 40
    @State private var endYear = Calendar.current.component(.year, from: .now)

    private var yearCount: Int { max(0, endYear - startYear + 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Neue Zeitachsen-Partitur").font(ChordflowDesign.heading(.title2, size: 27))
            Text("Ein Jahr wird als 4/4-Takt angelegt; Q1 bis Q4 entsprechen den vier Vierteln.")
                .foregroundStyle(.secondary)
            TextField("Titel", text: $title)
            HStack {
                Stepper("Startjahr: \(startYear)", value: $startYear, in: 1...9999)
                Stepper("Endjahr einschließlich: \(endYear)", value: $endYear, in: 1...9999)
            }
            GroupBox("Vorschau") {
                LabeledContent("Zeitraum", value: "\(startYear)–\(endYear)")
                LabeledContent("Umfang", value: "\(yearCount) Takte · \(yearCount * 4) Quartale")
            }
            HStack {
                Spacer()
                Button("Abbrechen") { dismiss() }
                Button("Zeitachsen-Partitur anlegen") {
                    create(title, startYear, endYear)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || startYear > endYear || yearCount > 300)
            }
        }
        .padding(20)
        .frame(width: 520)
    }
}

private struct ChordColorLegend: View {
    var body: some View {
        HStack(spacing: 14) {
            legend("Grundstellung", color: .blue)
            legend("Umkehrung", color: .purple)
            legend("veränderte Struktur / Entwurf", color: .pink)
            legend("aktiver Takt / Wiedergabe", color: Color(red: 0.22, green: 1.0, blue: 0.53))
        }
        .font(.caption)
    }

    private func legend(_ title: String, color: Color) -> some View {
        Label { Text(title) } icon: { Circle().fill(color).frame(width: 8, height: 8) }
    }
}
