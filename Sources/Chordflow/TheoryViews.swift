import MusicTheoryUI
import SwiftUI

enum ExperienceMode: String, CaseIterable, Identifiable {
    case simple = "Einfach"
    case advanced = "Erweitert"
    var id: String { rawValue }
}

enum WorkspaceMode: String, CaseIterable, Identifiable {
    case arrangement = "Akkordfolge"
    case chordLab = "Akkordlabor"
    case circle = "Quintenzirkel"
    case tracks = "Spuren"
    var id: String { rawValue }
    static var allCases: [WorkspaceMode] { [.arrangement, .circle, .tracks] }
}

private enum ChordLabDestination: Hashable {
    case timelinePosition
    case append
    case insertBefore(Int64)
    case replace(Int64)
}

private enum OccupiedChordAction: String, CaseIterable, Identifiable {
    case replace = "Ersetzen"
    case before = "Davor"
    case after = "Danach"
    case split = "Takt teilen"
    var id: String { rawValue }
}

private enum ArrangementAnalysisMode: String, CaseIterable, Identifiable {
    case roles = "Rollen"
    case voiceLeading = "Stimmführung"
    var id: String { rawValue }
}

struct TheoryWorkspaceView: View {
    @ObservedObject var library: ScoreLibrary
    let scene: ScoreScene
    let mode: WorkspaceMode
    let experienceMode: ExperienceMode
    let scoreController: ScoreController
    @Binding var selectedArrangementChord: ChordEvent?
    @Binding var selectedScoreMeasure: Int
    @Binding var showsArrangementDetail: Bool
    @State private var root = 0
    @State private var quality = ChordQuality.major
    @State private var pitches = TheoryChord(root: 0, quality: .major).pitches
    @State private var chordDestination = ChordLabDestination.timelinePosition
    @State private var insertionMeasure = 0
    @State private var insertionBeat = 0
    @State private var occupiedChordAction = OccupiedChordAction.replace
    @State private var splitNewChordFirst = false
    @State private var editedEventID: Int64?
    @State private var sceneActionMessage: String?
    @State private var snapsToScale = true
    @State private var automaticallyPreviewsChord = true
    @State private var pendingTonic: Int?
    @State private var arrangementAnalysisMode = ArrangementAnalysisMode.roles
    @State private var chordNotationHeight: CGFloat = 250
    @StateObject private var chordNotationController = ScoreController()

    private var chord: TheoryChord { TheoryChord(root: root, quality: quality, pitches: pitches) }

    var body: some View {
        Group {
            switch mode {
            case .arrangement: arrangement
            case .chordLab: chordLab
            case .circle: circle
            case .tracks: EmptyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var arrangement: some View {
        VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center) {
                        Text("Akkordfolge")
                            .font(ChordflowDesign.heading(.title2, size: 27))
                            .fixedSize(horizontal: true, vertical: false)
                        Spacer()
                        if experienceMode == .advanced {
                            Picker("Analyse", selection: $arrangementAnalysisMode) {
                                ForEach(ArrangementAnalysisMode.allCases) { Text($0.rawValue).tag($0) }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(width: 220)
                        }
                    }
                    HStack(spacing: 8) {
                        Button("Vorheriger Takt", systemImage: "chevron.left") { navigateArrangementMeasure(by: -1) }
                            .labelStyle(.iconOnly)
                            .keyboardShortcut(.leftArrow, modifiers: [])
                            .disabled(!canNavigateArrangementMeasure(by: -1))
                            .help("Einen Takt zurück (←)")
                        Button("Vorheriger Akkord", systemImage: "backward.end") { navigateArrangementChord(by: -1) }
                            .labelStyle(.iconOnly)
                            .keyboardShortcut(.leftArrow, modifiers: [.option])
                            .disabled(!canNavigateArrangementChord(by: -1))
                            .help("Zum vorherigen Akkord (⌥←)")
                        Button("Nächster Akkord", systemImage: "forward.end") { navigateArrangementChord(by: 1) }
                            .labelStyle(.iconOnly)
                            .keyboardShortcut(.rightArrow, modifiers: [.option])
                            .disabled(!canNavigateArrangementChord(by: 1))
                            .help("Zum nächsten Akkord (⌥→)")
                        Button("Nächster Takt", systemImage: "chevron.right") { navigateArrangementMeasure(by: 1) }
                            .labelStyle(.iconOnly)
                            .keyboardShortcut(.rightArrow, modifiers: [])
                            .disabled(!canNavigateArrangementMeasure(by: 1))
                            .help("Einen Takt vor (→)")
                        Text(experienceMode == .simple
                             ? "Wähle einen Klangbaustein und höre ihn an"
                             : arrangementAnalysisMode == .roles
                                ? "Funktion der Akkorde in \(MusicTheory.noteName(scene.tonic)) \(scene.scale.title)"
                                : "Liegetöne und Halbtonwege zum nächsten Akkord")
                            .font(.callout)
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .buttonStyle(.bordered)
                    Divider()
                }
                if experienceMode == .simple {
                    Text("Baue deine Folge Schritt für Schritt. Du kannst nichts kaputtmachen.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if arrangementAnalysisMode == .voiceLeading {
                    VoiceLeadingLegend()
                        .font(.caption)
                } else {
                    Text("I Ruhe · IV Öffnung · V Spannung und Rückkehr")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Group {
                    if let selected = selectedArrangementChord,
                       let saved = library.chordEvents.first(where: { $0.id == selected.id }) {
                        ArrangementCompactInspector(
                            event: saved,
                            initialDraft: library.chordDraft(id: saved.id) ?? saved,
                            scene: scene,
                            experienceMode: experienceMode,
                            previousEvent: adjacentEvent(to: saved, offset: -1),
                            nextEvent: adjacentEvent(to: saved, offset: 1),
                            onChange: updateArrangementDraft,
                            onSave: saveArrangementDraft,
                            onDiscard: discardArrangementDraft,
                            showDetails: { showsArrangementDetail = true }
                        )
                        .id(saved.id)
                    } else {
                        ContentUnavailableView(
                            "Akkord auswählen",
                            systemImage: "rectangle.stack",
                            description: Text("Wähle unten eine Karte, um den Akkord hier zu bearbeiten.")
                        )
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: experienceMode == .simple ? 230 : 300)
                .background(.quaternary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))

                Divider()

                if library.chordEvents.isEmpty {
                    ContentUnavailableView {
                        Label("Noch keine Akkorde", systemImage: "rectangle.stack.badge.plus")
                    } description: {
                        Text("Lege den ersten Akkord an und bearbeite ihn direkt im Inspector.")
                    } actions: {
                        Button("Ersten Akkord anlegen", systemImage: "plus") { createFirstChord() }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    GeometryReader { viewport in
                        ScrollViewReader { proxy in
                            ScrollView {
                                LazyVGrid(
                                    columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 9), count: 4),
                                    alignment: .leading,
                                    spacing: 9
                                ) {
                                    ForEach(library.displayedChordEvents) { event in
                                        VStack(spacing: 5) {
                                            chordCard(event)
                                            Button("Akkord danach", systemImage: "plus.circle") { insertChord(after: event) }
                                                .font(.caption)
                                                .labelStyle(.iconOnly)
                                                .buttonStyle(.borderless)
                                                .foregroundStyle(.secondary)
                                                .help("Direkt nach \(event.chord.symbol) einen neuen Akkord einfügen")
                                        }
                                        .id(event.id)
                                    }
                                }
                                .padding(.top, 8)
                                .padding(.bottom, max(8, viewport.size.height / 2 - 82))
                            }
                            .onChange(of: selectedArrangementChord?.id) { _, selectedID in
                                guard let selectedID else { return }
                                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(selectedID, anchor: .center) }
                            }
                        }
                    }
                }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear(perform: selectInitialArrangementChord)
    }

    private func updateArrangementDraft(_ draft: ChordEvent) {
        library.stageChordDraft(draft)
        selectedArrangementChord = draft
        previewArrangementChord(draft)
    }

    private func saveArrangementDraft(_ draft: ChordEvent) {
        library.stageChordDraft(draft)
        guard library.saveChordDraft(id: draft.id),
              let saved = library.chordEvents.first(where: { $0.id == draft.id }) else { return }
        selectedArrangementChord = saved
        previewArrangementChord(saved)
    }

    private func discardArrangementDraft(_ event: ChordEvent) {
        library.discardChordDraft(id: event.id)
        guard let saved = library.chordEvents.first(where: { $0.id == event.id }) else { return }
        selectedArrangementChord = saved
        previewArrangementChord(saved)
    }

    private func insertChord(after event: ChordEvent) {
        let newChord = TheoryChord(root: scene.tonic, quality: .major)
        guard library.insertChord(newChord, after: event.id),
              let index = library.chordEvents.firstIndex(where: { $0.id == event.id }),
              library.chordEvents.indices.contains(index + 1) else { return }
        let inserted = library.chordEvents[index + 1]
        selectedArrangementChord = inserted
        previewArrangementChord(inserted)
    }

    private func createFirstChord() {
        library.addChord(TheoryChord(root: scene.tonic, quality: .major))
        guard let inserted = library.chordEvents.first else { return }
        selectedArrangementChord = inserted
        previewArrangementChord(inserted)
    }

    private func selectInitialArrangementChord() {
        guard selectedArrangementChord == nil, let first = library.displayedChordEvents.first else { return }
        selectedArrangementChord = first
        selectedScoreMeasure = first.startBeat / 4
        scoreController.highlightChord(measure: selectedScoreMeasure, pitches: first.pitches)
    }

    private func adjacentEvent(to event: ChordEvent, offset: Int) -> ChordEvent? {
        guard let index = library.displayedChordEvents.firstIndex(where: { $0.id == event.id }),
              library.displayedChordEvents.indices.contains(index + offset) else { return nil }
        return library.displayedChordEvents[index + offset]
    }

    private func canNavigateArrangementMeasure(by offset: Int) -> Bool {
        (0..<max(1, sceneMeasureCount)).contains(selectedScoreMeasure + offset)
    }

    private func navigateArrangementMeasure(by offset: Int) {
        let target = selectedScoreMeasure + offset
        guard (0..<max(1, sceneMeasureCount)).contains(target) else { return }
        selectedScoreMeasure = target
        if let event = event(atMeasure: target) {
            selectedArrangementChord = library.chordDraft(id: event.id) ?? event
            MIDIService.shared.previewChord(event.pitches)
            scoreController.highlightChord(measure: target, pitches: event.pitches)
        } else {
            scoreController.highlightChord(measure: target, pitches: [])
            MIDIService.shared.stopChordPreview()
        }
    }

    private func canNavigateArrangementChord(by offset: Int) -> Bool {
        guard let selectedArrangementChord,
              let index = library.displayedChordEvents.firstIndex(where: { $0.id == selectedArrangementChord.id }) else { return false }
        return library.displayedChordEvents.indices.contains(index + offset)
    }

    private func navigateArrangementChord(by offset: Int) {
        guard let selectedArrangementChord,
              let index = library.displayedChordEvents.firstIndex(where: { $0.id == selectedArrangementChord.id }),
              library.displayedChordEvents.indices.contains(index + offset) else { return }
        let event = library.displayedChordEvents[index + offset]
        self.selectedArrangementChord = event
        previewArrangementChord(event)
    }

    private func chordCard(_ event: ChordEvent) -> some View {
        let voicing = MusicTheory.analyzeVoicing(event.chord, prefersFlats: MusicTheory.prefersFlats(tonic: scene.tonic))
        let degree = MusicTheory.romanDegree(root: event.root, tonic: scene.tonic, kind: scene.scale)
        let isActive = selectedArrangementChord?.id == event.id
        let terminalGreen = ChordflowDesign.focusGreen
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(event.chord.symbol).font(ChordflowDesign.heading(.title2, size: 24))
                if event.isDraft {
                    Text("Entwurf")
                        .font(.caption2.bold())
                        .foregroundStyle(ChordflowDesign.alteredPink)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(ChordflowDesign.alteredPink.opacity(0.12), in: Capsule())
                }
                Spacer()
                Button {
                    MIDIService.shared.previewChord(event.pitches)
                } label: {
                    Image(systemName: "speaker.wave.2.fill")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(ChordflowDesign.actionTeal)
                .help("\(event.chord.symbol) anhören")
                Menu("Aktionen", systemImage: "ellipsis.circle") {
                    Button("Akkord löschen", systemImage: "trash", role: .destructive) { library.deleteChord(event.id) }
                }
                .labelStyle(.iconOnly)
                .menuStyle(.borderlessButton)
                .help("Aktionen für \(event.chord.symbol)")
            }
            Text(experienceMode == .simple ? friendlyRole(for: event) : degree.map { harmonicRoleLabel(for: event, degree: $0) } ?? "chromatisch")
                .font(.caption.weight(.semibold))
                .foregroundStyle(degree == nil ? ChordflowDesign.tensionOrange : Color.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background((degree == nil ? ChordflowDesign.tensionOrange : Color.secondary).opacity(0.1), in: Capsule())
            if experienceMode == .advanced {
                Label(voicing.description, systemImage: voicing.isAltered ? "waveform.badge.exclamationmark" : "pianokeys")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(voicingColor(event))
                    .lineLimit(1)
                Text(event.pitches.map { MusicTheory.pitchName($0, prefersFlats: MusicTheory.prefersFlats(tonic: scene.tonic)) }.joined(separator: " · "))
                    .font(.caption.monospaced())
                    .lineLimit(1)
            }
            Group {
                if arrangementAnalysisMode == .voiceLeading {
                    voiceLeadingSummary(for: event)
                } else if let degree {
                    Text("Stufe \(degree) in \(MusicTheory.noteName(scene.tonic)) \(scene.scale.title)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Außerhalb der gewählten Tonleiter")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: experienceMode == .simple ? 26 : 32, alignment: .topLeading)
            Spacer(minLength: 0)
            if experienceMode == .advanced {
                Stepper("\(event.beats) Zählzeiten", value: Binding(get: { event.beats }, set: { value in
                    var changed = event; changed.beats = value; library.stageChordDraft(changed)
                }), in: 1...32)
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, minHeight: experienceMode == .simple ? 118 : 150, maxHeight: experienceMode == .simple ? 118 : 150, alignment: .topLeading)
        .background(cardColor(event).opacity(isActive ? 0.10 : 0.055), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(isActive ? terminalGreen.opacity(0.95) : .clear, lineWidth: 2))
        .shadow(color: isActive ? terminalGreen.opacity(0.32) : .clear, radius: 9)
        .animation(.easeOut(duration: 0.16), value: isActive)
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture {
            selectedArrangementChord = event
            previewArrangementChord(event)
        }
        .help(chordHelp(event))
        .draggable(String(event.id))
        .dropDestination(for: String.self) { values, _ in
            guard let raw = values.first, let source = Int64(raw) else { return false }
            library.moveChord(source, before: event.id); return true
        }
    }

    private func friendlyRole(for event: ChordEvent) -> String {
        switch MusicTheory.normalized(event.root - scene.tonic) {
        case 0: "Zuhause · Tonika"
        case 5: "Reise · Subdominante"
        case 7: "Spannung · Dominante"
        default: "Anderer Klang"
        }
    }

    private func voicingColor(_ event: ChordEvent) -> Color {
        switch MusicTheory.analyzeVoicing(event.chord).role {
        case .standard: ChordflowDesign.chordToneBlue
        case .inversion: ChordflowDesign.inversionPurple
        case .altered: ChordflowDesign.alteredPink
        }
    }

    private func cardColor(_ event: ChordEvent) -> Color {
        if event.isDraft { return ChordflowDesign.alteredPink }
        if MusicTheory.romanDegree(root: event.root, tonic: scene.tonic, kind: scene.scale) == nil {
            return ChordflowDesign.tensionOrange
        }
        return voicingColor(event)
    }

    private func harmonicRoleLabel(for event: ChordEvent, degree: String) -> String {
        switch MusicTheory.normalized(event.root - scene.tonic) {
        case 0: "\(degree) · Tonika"
        case 5: "\(degree) · Subdominante"
        case 7: "\(degree) · Dominante"
        default: "Stufe \(degree)"
        }
    }

    @ViewBuilder private func voiceLeadingSummary(for event: ChordEvent) -> some View {
        if let index = library.chordEvents.firstIndex(where: { $0.id == event.id }), library.chordEvents.indices.contains(index + 1) {
            let next = library.chordEvents[index + 1]
            let analysis = MusicTheory.voiceLeading(from: event.chord, to: next.chord)
            VStack(alignment: .leading, spacing: 4) {
                Text("→ \(next.chord.symbol)").font(.caption.bold()).foregroundStyle(.secondary)
                if !analysis.commonPitchClasses.isEmpty {
                    Label("Bleibt: \(analysis.commonPitchClasses.map { MusicTheory.noteName($0, prefersFlats: MusicTheory.prefersFlats(tonic: scene.tonic)) }.joined(separator: ", "))", systemImage: "link")
                        .foregroundStyle(ChordflowDesign.commonMint)
                }
                if !analysis.semitoneMoves.isEmpty {
                    Label(analysis.semitoneMoves.map { "\(MusicTheory.noteName($0.from))→\(MusicTheory.noteName($0.to))" }.joined(separator: " · "), systemImage: "arrow.left.arrow.right")
                        .foregroundStyle(ChordflowDesign.resolutionGold)
                }
                if analysis.commonPitchClasses.isEmpty && analysis.semitoneMoves.isEmpty {
                    Text("Keine direkten Liege- oder Halbtonverbindungen").foregroundStyle(.secondary)
                }
            }
            .font(.caption)
            .lineLimit(2)
        } else {
            Text("Ende der Akkordfolge").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var chordLab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("Akkordlabor").font(ChordflowDesign.heading(.title2, size: 27))
                    Spacer()
                }
                chordNavigation
                HStack {
                    Picker("Grundton", selection: Binding(get: { root }, set: { root = $0; resetVoicing() })) { ForEach(0..<12, id: \.self) { Text(MusicTheory.noteName($0, prefersFlats: MusicTheory.prefersFlats(tonic: scene.tonic))).tag($0) } }.frame(maxWidth: 180)
                    Picker("Akkord", selection: Binding(get: { quality }, set: { quality = $0; resetVoicing() })) { ForEach(ChordQuality.allCases) { Text($0.title).tag($0) } }.frame(maxWidth: 240)
                    Spacer()
                }
                sceneDestinationPanel
                HStack {
                    Button("Lage höher ↑") { invert(up: true) }
                        .help("Den tiefsten Akkordton eine Oktave nach oben setzen")
                    Button("Lage tiefer ↓") { invert(up: false) }
                        .help("Den höchsten Akkordton eine Oktave nach unten setzen")
                    Toggle("Beim Ziehen auf Abschnittstonleiter einrasten", isOn: $snapsToScale).toggleStyle(.switch)
                    Spacer()
                }
                VoicingPositionLabel(chord: chord, prefersFlats: MusicTheory.prefersFlats(tonic: scene.tonic))
                Text(snapsToScale ? "Mausziehen überspringt leiterfremde Halbtöne. ↑/↓ bleibt chromatisch." : "Mausziehen und ↑/↓ verschieben chromatisch in Halbtonschritten.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Probehören", systemImage: "speaker.wave.2.fill") { previewChord() }.buttonStyle(.borderedProminent)
                    Toggle("Nach Änderungen automatisch spielen", isOn: $automaticallyPreviewsChord).toggleStyle(.switch)
                    Spacer()
                }
                ScoreWebView(abc: chordNotationSource, height: $chordNotationHeight, controller: chordNotationController)
                    .frame(height: min(max(chordNotationHeight, 220), 340))
                VoicingPitchEditor(pitches: pitches, tonic: scene.tonic, scale: scene.scale) { index, pitch in
                    pitches[index] = snapsToScale ? MusicTheory.nearestScalePitch(to: pitch, tonic: scene.tonic, kind: scene.scale) : pitch
                    pitches.sort()
                }
                ChordTheoryExplanation(chord: chord, scene: scene)
                HStack(alignment: .top, spacing: 16) {
                    PianoChordView(
                        pitches: pitches.compactMap(UInt8.init(exactly:)),
                        rootPitchClass: MusicTheory.normalized(root)
                    )
                    GuitarChordView(pitches: pitches.compactMap(UInt8.init(exactly:)))
                }
                Text("Ziehe einen Notenkopf im Notenfeld nach oben oder unten. Er rastet chromatisch auf der nächstgelegenen Tonhöhe ein.").font(.caption).foregroundStyle(.secondary)
            }.padding(18)
        }
        .onChange(of: chordDestination) { _, destination in
            guard case let .replace(id) = destination, let event = library.chordEvents.first(where: { $0.id == id }) else { return }
            loadForEditing(event)
        }
        .onChange(of: scoreController.selectedNotes) { _, selections in
            if let selectedMeasure = selections.first?.measure {
                insertionMeasure = min(max(0, selectedMeasure), max(0, sceneMeasureCount - 1))
                occupiedChordAction = .replace
                chordDestination = .timelinePosition
            }
        }
        .onChange(of: selectedScoreMeasure) { _, selectedMeasure in
            insertionMeasure = min(max(0, selectedMeasure), max(0, sceneMeasureCount - 1))
            occupiedChordAction = .replace
        }
        .onChange(of: insertionBeat) { _, _ in occupiedChordAction = .replace }
        .onChange(of: pitches) { _, _ in
            stageCurrentChordDraft()
            if automaticallyPreviewsChord { previewChord() }
        }
        .onChange(of: automaticallyPreviewsChord) { _, enabled in if enabled { previewChord() } else { MIDIService.shared.stopChordPreview() } }
        .onAppear {
            insertionMeasure = min(max(0, selectedScoreMeasure), max(0, sceneMeasureCount - 1))
            if let editedEvent {
                loadForEditing(editedEvent)
            } else if let event = event(atMeasure: selectedScoreMeasure) ?? library.chordEvents.first {
                loadForEditing(event)
            } else if automaticallyPreviewsChord { previewChord() }
        }
        .onChange(of: scene.id) { _, _ in
            editedEventID = nil
        }
        .onDisappear { MIDIService.shared.stopChordPreview() }
    }

    private var chordNavigation: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button("Vorheriger Takt", systemImage: "chevron.left") { navigateMeasure(by: -1) }
                    .labelStyle(.iconOnly)
                    .keyboardShortcut(.leftArrow, modifiers: [])
                    .disabled(!canNavigateMeasure(by: -1))
                    .help("Einen Takt zurück (←)")
                Button("Vorheriger Akkord", systemImage: "backward.end") { navigateChord(by: -1) }
                    .labelStyle(.iconOnly)
                    .keyboardShortcut(.leftArrow, modifiers: [.option])
                    .disabled(!canNavigateChord(by: -1))
                    .help("Zum vorherigen Akkord (⌥←)")
                if let event = editedEvent {
                    Text("Takt \(selectedScoreMeasure + 1) · Akkord \(event.position + 1) von \(library.chordEvents.count) · \(event.chord.symbol)")
                        .font(.headline)
                } else {
                    Text("Neuer Akkord").font(.headline)
                }
                Button("Nächster Akkord", systemImage: "forward.end") { navigateChord(by: 1) }
                    .labelStyle(.iconOnly)
                    .keyboardShortcut(.rightArrow, modifiers: [.option])
                    .disabled(!canNavigateChord(by: 1))
                    .help("Zum nächsten Akkord (⌥→)")
                Button("Nächster Takt", systemImage: "chevron.right") { navigateMeasure(by: 1) }
                    .labelStyle(.iconOnly)
                    .keyboardShortcut(.rightArrow, modifiers: [])
                    .disabled(!canNavigateMeasure(by: 1))
                    .help("Einen Takt vor (→)")
                Spacer()
                if editedEvent != nil {
                    Button("Als neuen Akkord verwenden", systemImage: "plus") {
                        editedEventID = nil
                        sceneActionMessage = "\(chord.symbol) kann jetzt an einer neuen Position eingesetzt werden."
                    }
                }
            }
            if hasUnsavedChordChanges, let event = editedEvent {
                HStack(spacing: 10) {
                    Label("Ungespeicherte Änderung an \(event.chord.symbol)", systemImage: "pencil.circle.fill")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(ChordflowDesign.alteredPink)
                    Button("Änderung speichern", systemImage: "checkmark") { saveEditedChord() }
                        .buttonStyle(.borderedProminent)
                    Button("Verwerfen", systemImage: "arrow.uturn.backward") { discardEditedChord() }
                    Text("Der Entwurf bleibt beim Navigieren erhalten und wird in Karte und Partitur markiert.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }

    private var editedEvent: ChordEvent? {
        guard let editedEventID else { return nil }
        return library.displayedChordEvents.first { $0.id == editedEventID }
    }
    private var hasUnsavedChordChanges: Bool {
        guard let editedEventID else { return false }
        return library.chordDraft(id: editedEventID) != nil
    }
    private func event(atMeasure measure: Int) -> ChordEvent? {
        let beat = max(0, measure) * 4
        return library.displayedChordEvents.first { $0.startBeat <= beat && $0.startBeat + $0.beats > beat }
    }
    private func canNavigateChord(by offset: Int) -> Bool {
        guard let editedEvent, let index = library.chordEvents.firstIndex(where: { $0.id == editedEvent.id }) else { return false }
        return library.chordEvents.indices.contains(index + offset)
    }
    private func canNavigateMeasure(by offset: Int) -> Bool {
        let target = selectedScoreMeasure + offset
        return (0..<sceneMeasureCount).contains(target)
    }
    private func navigateMeasure(by offset: Int) {
        stageCurrentChordDraft()
        let target = selectedScoreMeasure + offset
        guard (0..<sceneMeasureCount).contains(target) else { return }
        selectedScoreMeasure = target
        insertionMeasure = target
        insertionBeat = 0
        if let targetEvent = event(atMeasure: target) {
            if targetEvent.id == editedEventID {
                scoreController.highlightChord(measure: target, pitches: targetEvent.pitches)
                MIDIService.shared.previewChord(targetEvent.pitches)
            } else {
                loadForEditing(targetEvent)
            }
        } else {
            scoreController.highlightChord(measure: target, pitches: [])
            MIDIService.shared.stopChordPreview()
        }
    }
    private func navigateChord(by offset: Int) {
        stageCurrentChordDraft()
        guard let editedEvent,
              let index = library.chordEvents.firstIndex(where: { $0.id == editedEvent.id }),
              library.chordEvents.indices.contains(index + offset) else { return }
        loadForEditing(library.chordEvents[index + offset])
    }
    private func loadForEditing(_ event: ChordEvent) {
        editedEventID = event.id
        let displayedEvent = library.chordDraft(id: event.id) ?? event
        root = displayedEvent.root
        quality = displayedEvent.quality
        pitches = displayedEvent.pitches
        insertionMeasure = displayedEvent.startBeat / 4
        insertionBeat = displayedEvent.startBeat % 4
        selectedScoreMeasure = insertionMeasure
        scoreController.highlightChord(measure: insertionMeasure, pitches: displayedEvent.pitches)
        previewChord()
        sceneActionMessage = nil
    }
    private func saveEditedChord() {
        stageCurrentChordDraft()
        guard let editedEvent, library.saveChordDraft(id: editedEvent.id) else { return }
        sceneActionMessage = "\(chord.symbol) in Takt \(measureNumber(for: editedEvent)) wurde gespeichert."
    }
    private func discardEditedChord() {
        guard let editedEventID, let savedEvent = library.chordEvents.first(where: { $0.id == editedEventID }) else { return }
        library.discardChordDraft(id: editedEventID)
        loadForEditing(savedEvent)
        sceneActionMessage = "Ungespeicherte Änderungen wurden verworfen."
    }
    private func stageCurrentChordDraft() {
        guard let editedEventID, var event = library.chordEvents.first(where: { $0.id == editedEventID }) else { return }
        event.root = chord.root
        event.quality = chord.quality
        event.pitches = chord.pitches
        library.stageChordDraft(event)
    }

    private var sceneDestinationPanel: some View {
        GroupBox("In Abschnitt übernehmen") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Aktion", selection: $chordDestination) {
                    Text("In ausgewählten Takt einsetzen").tag(ChordLabDestination.timelinePosition)
                    if !library.chordEvents.isEmpty {
                        Section("Einfügen") {
                            Text("Am Ende · ab Takt \(appendMeasure)").tag(ChordLabDestination.append)
                            ForEach(library.chordEvents) { event in
                                Text("Vor \(event.position + 1). \(event.chord.symbol) · Takt \(measureNumber(for: event))").tag(ChordLabDestination.insertBefore(event.id))
                            }
                        }
                        Section("Ersetzen") {
                            ForEach(library.chordEvents) { event in
                                Text("\(event.position + 1). \(event.chord.symbol) ersetzen · Takt \(measureNumber(for: event))").tag(ChordLabDestination.replace(event.id))
                            }
                        }
                    }
                }
                .frame(maxWidth: 420)
                if chordDestination == .timelinePosition {
                    HStack(spacing: 14) {
                        Stepper("Takt \(insertionMeasure + 1)", value: Binding(
                            get: { insertionMeasure },
                            set: { insertionMeasure = $0; selectedScoreMeasure = $0 }
                        ), in: 0...max(0, sceneMeasureCount - 1))
                            .frame(width: 150)
                        Picker("Zählzeit", selection: $insertionBeat) {
                            ForEach(0..<4, id: \.self) { Text("\($0 + 1)").tag($0) }
                        }
                        .frame(width: 130)
                    }
                    Label("Die Taktauswahl rechts oben und Klicks auf Noten werden übernommen. Du kannst Takt und Zählzeit auch direkt einstellen.", systemImage: "cursorarrow.click.2")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let occupiedEvent {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Takt \(insertionMeasure + 1) ist mit \(occupiedEvent.chord.symbol) belegt", systemImage: "exclamationmark.circle.fill")
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(ChordflowDesign.tensionOrange)
                            Picker("Belegten Takt bearbeiten", selection: $occupiedChordAction) {
                                ForEach(OccupiedChordAction.allCases.filter { $0 != .split || canSplitOccupiedMeasure }) { Text($0.rawValue).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 520)
                            if occupiedChordAction == .split {
                                Picker("Reihenfolge", selection: $splitNewChordFirst) {
                                    Text("\(occupiedEvent.chord.symbol) → \(chord.symbol)").tag(false)
                                    Text("\(chord.symbol) → \(occupiedEvent.chord.symbol)").tag(true)
                                }
                                .pickerStyle(.segmented)
                                .frame(maxWidth: 360)
                            }
                        }
                        .padding(10)
                        .background(ChordflowDesign.tensionOrange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                Text(destinationExplanation).font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button(destinationButtonTitle, systemImage: destinationButtonIcon) { applyChordToScene() }
                        .buttonStyle(.borderedProminent)
                    if let sceneActionMessage {
                        Label(sceneActionMessage, systemImage: "checkmark.circle.fill").font(.callout).foregroundStyle(ChordflowDesign.commonMint)
                    }
                }
            }
            .padding(.top, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var sceneMeasureCount: Int { max(1, (ABCScoreBuilder.sceneBeats(tracks: library.tracks, chords: library.chordEvents) + 3) / 4) }
    private var insertionStartBeat: Int { insertionMeasure * 4 + insertionBeat }
    private var occupiedEvent: ChordEvent? {
        library.chordEvents.first { $0.startBeat <= insertionStartBeat && $0.startBeat + $0.beats > insertionStartBeat }
    }
    private var canSplitOccupiedMeasure: Bool {
        guard let occupiedEvent else { return false }
        let measureStart = insertionMeasure * 4
        return occupiedEvent.startBeat <= measureStart && occupiedEvent.startBeat + occupiedEvent.beats >= measureStart + 4
    }
    private var appendMeasure: Int { (library.chordEvents.map { $0.startBeat + $0.beats }.max() ?? 0) / 4 + 1 }
    private func measureNumber(for event: ChordEvent) -> Int {
        event.startBeat / 4 + 1
    }
    private var destinationExplanation: String {
        switch chordDestination {
        case .timelinePosition:
            guard let occupiedEvent else { return "Der Akkord beginnt in Takt \(insertionMeasure + 1) auf Zählzeit \(insertionBeat + 1), ohne frühere Takte zu verschieben." }
            switch occupiedChordAction {
            case .replace:
                return "\(occupiedEvent.chord.symbol) wird durch \(chord.symbol) ersetzt; Position und Dauer bleiben erhalten."
            case .before:
                return "\(chord.symbol) wird vor \(occupiedEvent.chord.symbol) eingefügt. Der vorhandene Akkord und alle folgenden Akkorde rücken um einen Takt nach rechts."
            case .after:
                return "\(chord.symbol) wird nach dem vollständigen \(occupiedEvent.chord.symbol)-Abschnitt eingefügt. Alle folgenden Akkorde rücken um einen Takt nach rechts."
            case .split:
                return "Takt \(insertionMeasure + 1) wird halbiert: \(splitNewChordFirst ? chord.symbol : occupiedEvent.chord.symbol) auf Zählzeit 1–2, \(splitNewChordFirst ? occupiedEvent.chord.symbol : chord.symbol) auf Zählzeit 3–4."
            }
        case .append: return "Der Akkord wird nach der vorhandenen Folge eingefügt und beginnt ab Takt \(appendMeasure)."
        case let .insertBefore(id):
            guard let event = library.chordEvents.first(where: { $0.id == id }) else { return "Wähle eine gültige Einfügeposition." }
            return "Der neue Akkord wird unmittelbar vor \(event.chord.symbol) in Takt \(measureNumber(for: event)) eingefügt."
        case let .replace(id):
            guard let event = library.chordEvents.first(where: { $0.id == id }) else { return "Wähle einen gültigen Akkord." }
            return "\(event.chord.symbol) in Takt \(measureNumber(for: event)) wird ersetzt; Position und Dauer bleiben erhalten."
        }
    }
    private var destinationButtonTitle: String {
        switch chordDestination {
        case .timelinePosition:
            guard let occupiedEvent else { return "In Takt \(insertionMeasure + 1) einsetzen" }
            switch occupiedChordAction {
            case .replace: return "\(occupiedEvent.chord.symbol) durch \(chord.symbol) ersetzen"
            case .before: return "\(chord.symbol) vor \(occupiedEvent.chord.symbol) einfügen"
            case .after: return "\(chord.symbol) nach \(occupiedEvent.chord.symbol) einfügen"
            case .split: return "Takt \(insertionMeasure + 1) teilen"
            }
        case .append: return "Am Ende einfügen"
        case .insertBefore: return "An Position einfügen"
        case .replace: return "Akkord ersetzen"
        }
    }
    private var destinationButtonIcon: String {
        if case .replace = chordDestination { return "arrow.triangle.2.circlepath" }
        if chordDestination == .timelinePosition, occupiedEvent != nil {
            return occupiedChordAction == .split ? "rectangle.split.2x1" : occupiedChordAction == .replace ? "arrow.triangle.2.circlepath" : "plus"
        }
        return "plus"
    }
    private func applyChordToScene() {
        switch chordDestination {
        case .timelinePosition:
            if let occupiedEvent {
                applyChord(chord, toOccupied: occupiedEvent)
            } else if library.addChord(chord, atBeat: insertionStartBeat) {
                sceneActionMessage = "\(chord.symbol) beginnt in Takt \(insertionMeasure + 1) auf Zählzeit \(insertionBeat + 1)."
            }
        case .append:
            let measure = appendMeasure
            library.addChord(chord)
            sceneActionMessage = "\(chord.symbol) wurde ab Takt \(measure) angefügt."
        case let .insertBefore(id):
            let measure = library.chordEvents.first(where: { $0.id == id }).map(measureNumber) ?? 1
            if library.insertChord(chord, before: id) { sceneActionMessage = "\(chord.symbol) wurde in Takt \(measure) eingefügt." }
        case let .replace(id):
            let measure = library.chordEvents.first(where: { $0.id == id }).map(measureNumber) ?? 1
            if library.replaceChord(id: id, with: chord) { sceneActionMessage = "Akkord in Takt \(measure) wurde durch \(chord.symbol) ersetzt." }
        }
    }

    private func applyChord(_ chord: TheoryChord, toOccupied event: ChordEvent) {
        switch occupiedChordAction {
        case .replace:
            if library.replaceChord(id: event.id, with: chord) {
                sceneActionMessage = "\(event.chord.symbol) wurde in Takt \(insertionMeasure + 1) durch \(chord.symbol) ersetzt."
            }
        case .before:
            if library.insertChord(chord, before: event.id) {
                sceneActionMessage = "\(chord.symbol) wurde vor \(event.chord.symbol) eingefügt."
            }
        case .after:
            if library.insertChord(chord, after: event.id) {
                sceneActionMessage = "\(chord.symbol) wurde nach \(event.chord.symbol) eingefügt."
            }
        case .split:
            if library.splitChordMeasure(eventID: event.id, measureStartBeat: insertionMeasure * 4, with: chord, newChordFirst: splitNewChordFirst) {
                sceneActionMessage = "Takt \(insertionMeasure + 1) enthält jetzt \(splitNewChordFirst ? chord.symbol : event.chord.symbol) und \(splitNewChordFirst ? event.chord.symbol : chord.symbol)."
            }
        }
    }

    private var circle: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(MusicTheory.noteName(scene.tonic, prefersFlats: MusicTheory.prefersFlats(tonic: scene.tonic))) \(scene.scale.title)")
                        .font(ChordflowDesign.heading(.title2, size: 27))
                    Text(MusicTheory.scaleNames(tonic: scene.tonic, kind: scene.scale).joined(separator: " – ")).font(.headline)
                    Text(learningText).font(.callout).fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .frame(maxWidth: 560, alignment: .leading)
                .background(functionColor(scene.tonic).opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                CircleOfFifthsView(tonic: scene.tonic) { newTonic in
                    pendingTonic = newTonic
                }.frame(width: 440, height: 440)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Verwandte Funktionen").font(.headline)
                    HStack(spacing: 10) {
                        theoryValue("Dominante", MusicTheory.noteName(scene.tonic + 7), color: .orange)
                        theoryValue("Subdominante", MusicTheory.noteName(scene.tonic + 5), color: .purple)
                        theoryValue("Paralleltonart", MusicTheory.noteName(scene.tonic + (scene.scale == .major ? 9 : 3)) + (scene.scale == .major ? " Moll" : " Dur"), color: .blue)
                    }
                    Text("Klicke eine Tonart im Kreis und entscheide anschließend, ob nur die Analyse oder auch die Akkordfolge geändert werden soll.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: 560, alignment: .leading)
            }
            .padding(.leading, 8)
            .padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .confirmationDialog("Tonart wechseln", isPresented: Binding(get: { pendingTonic != nil }, set: { if !$0 { pendingTonic = nil } }), titleVisibility: .visible) {
            if let newTonic = pendingTonic {
                Button("Nur Analyse auf \(MusicTheory.noteName(newTonic)) ändern") { changeTonic(to: newTonic, transposesChords: false) }
                Button("Akkordfolge nach \(MusicTheory.noteName(newTonic)) transponieren") { changeTonic(to: newTonic, transposesChords: true) }
            }
            Button("Abbrechen", role: .cancel) { pendingTonic = nil }
        } message: {
            Text("Die kontrollierte Transposition verändert die gespeicherten Akkorde und die daraus erzeugte Bassspur. Frei eingegebene Melodien bleiben unverändert.")
        }
    }

    private func resetVoicing() { pitches = TheoryChord(root: root, quality: quality).pitches }
    private func previewChord() { MIDIService.shared.previewChord(pitches) }
    private var chordNotationSource: String {
        ABCScoreBuilder.singleChord(chord, scene: scene)
    }
    private func invert(up: Bool) {
        pitches = MusicTheory.invertedVoicing(pitches, upward: up)
    }
    private func changeTonic(to newTonic: Int, transposesChords: Bool) {
        if transposesChords { library.transposeChordProgression(from: scene.tonic, to: newTonic) }
        var changed = scene; changed.tonic = newTonic; library.updateScene(changed); pendingTonic = nil
    }
    private func functionColor(_ chordRoot: Int) -> Color {
        switch MusicTheory.normalized(chordRoot - scene.tonic) {
        case 0, 3, 4, 8, 9: ChordflowDesign.actionTeal
        case 5, 2: ChordflowDesign.inversionPurple
        case 7, 11: ChordflowDesign.tensionOrange
        default: .red
        }
    }
    private func chordHelp(_ event: ChordEvent) -> String {
        let chord = event.chord
        let tones = chord.pitches.map { MusicTheory.pitchName($0, prefersFlats: MusicTheory.prefersFlats(tonic: scene.tonic)) }.joined(separator: " · ")
        let degree = MusicTheory.romanDegree(root: chord.root, tonic: scene.tonic, kind: scene.scale) ?? "chromatischer Grundton"
        return "\(chord.symbol) · \(chord.quality.title)\nTöne: \(tones)\nIntervalle: \(chord.intervalLabels.joined(separator: " · "))\nStufe: \(degree)\nKlicken zum Anhören und Anzeigen"
    }
    private func previewArrangementChord(_ event: ChordEvent) {
        selectedScoreMeasure = measureNumber(for: event) - 1
        MIDIService.shared.previewChord(event.pitches)
        scoreController.highlightChord(measure: measureNumber(for: event) - 1, pitches: event.pitches)
    }
    private var learningText: String {
        "Die Tonika \(MusicTheory.noteName(scene.tonic)) vermittelt Ruhe. Die Dominante \(MusicTheory.noteName(scene.tonic + 7)) erzeugt Spannung und führt zurück zur Tonika; die Subdominante \(MusicTheory.noteName(scene.tonic + 5)) öffnet die Bewegung von ihr weg."
    }
    private func theoryValue(_ title: String, _ value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline)
        }.padding(10).frame(maxWidth: .infinity, alignment: .leading).background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
    }
}

private struct ArrangementCompactInspector: View {
    let event: ChordEvent
    let initialDraft: ChordEvent
    let scene: ScoreScene
    let experienceMode: ExperienceMode
    let previousEvent: ChordEvent?
    let nextEvent: ChordEvent?
    let onChange: (ChordEvent) -> Void
    let onSave: (ChordEvent) -> Void
    let onDiscard: (ChordEvent) -> Void
    let showDetails: () -> Void
    @State private var draft: ChordEvent

    init(event: ChordEvent, initialDraft: ChordEvent, scene: ScoreScene, experienceMode: ExperienceMode, previousEvent: ChordEvent?, nextEvent: ChordEvent?, onChange: @escaping (ChordEvent) -> Void, onSave: @escaping (ChordEvent) -> Void, onDiscard: @escaping (ChordEvent) -> Void, showDetails: @escaping () -> Void) {
        self.event = event
        self.initialDraft = initialDraft
        self.scene = scene
        self.experienceMode = experienceMode
        self.previousEvent = previousEvent
        self.nextEvent = nextEvent
        self.onChange = onChange
        self.onSave = onSave
        self.onDiscard = onDiscard
        self.showDetails = showDetails
        _draft = State(initialValue: initialDraft)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(draft.chord.symbol).font(ChordflowDesign.heading(.title, size: 30))
                        Text("Takt \(draft.startBeat / 4 + 1) · \(draft.beats) Zählzeiten")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(experienceMode == .simple ? "Mehr entdecken" : "Detailmodus", systemImage: "arrow.up.left.and.arrow.down.right") { showDetails() }
                        .labelStyle(.iconOnly)
                        .help(experienceMode == .simple ? "Noten, Klaviatur und Erklärungen entdecken" : "Großen Detailmodus mit Notation, Musiktheorie und Klaviatur öffnen")
                }

                if hasChanges {
                    Label("Ungespeicherter Entwurf", systemImage: "pencil.circle.fill")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(ChordflowDesign.alteredPink)
                }

                GroupBox(experienceMode == .simple ? "Klang verändern" : "Akkord") {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker(experienceMode == .simple ? "Startton" : "Grundton", selection: Binding(get: { draft.root }, set: { value in changeRoot(value) })) {
                            ForEach(0..<12, id: \.self) { root in
                                Text(MusicTheory.noteName(root, prefersFlats: MusicTheory.prefersFlats(tonic: scene.tonic))).tag(root)
                            }
                        }
                        Picker(experienceMode == .simple ? "Klangart" : "Typ", selection: Binding(get: { draft.quality }, set: { value in changeQuality(value) })) {
                            ForEach(ChordQuality.allCases) { Text($0.title).tag($0) }
                        }
                        HStack {
                            Button(experienceMode == .simple ? "Klang höher" : "Lage höher", systemImage: "arrow.up") { invert(upward: true) }
                            Button(experienceMode == .simple ? "Klang tiefer" : "Lage tiefer", systemImage: "arrow.down") { invert(upward: false) }
                        }
                        .labelStyle(.titleAndIcon)
                        if experienceMode == .advanced {
                            VoicingPositionLabel(chord: draft.chord, prefersFlats: MusicTheory.prefersFlats(tonic: scene.tonic))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.top, 4)
                }

                DisclosureGroup(experienceMode == .simple ? "Warum klingt das so?" : "Musiktheorie") {
                    ChordTheoryExplanation(chord: draft.chord, scene: scene, showsSymbol: false)
                        .padding(.vertical, 8)
                }

                DisclosureGroup("Im harmonischen Zusammenhang") {
                    VStack(alignment: .leading, spacing: 10) {
                        if let previousEvent {
                            voiceLeadingRow(title: "Von \(previousEvent.chord.symbol)", from: previousEvent.chord, to: draft.chord)
                        }
                        if let nextEvent {
                            voiceLeadingRow(title: "Zu \(nextEvent.chord.symbol)", from: draft.chord, to: nextEvent.chord)
                        }
                        if previousEvent == nil && nextEvent == nil {
                            Text("Füge einen weiteren Akkord hinzu, um Liegetöne und Halbtonbewegungen zu vergleichen.")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.callout)
                    .padding(.vertical, 8)
                }

                HStack {
                    Button("Probehören", systemImage: "speaker.wave.2.fill") {
                        MIDIService.shared.previewChord(draft.pitches)
                    }
                    Spacer()
                    if hasChanges {
                        Button("Verwerfen", systemImage: "arrow.uturn.backward") {
                            draft = event
                            onDiscard(event)
                        }
                        Button("Speichern", systemImage: "checkmark") { onSave(draft) }
                            .buttonStyle(.borderedProminent)
                    }
                }

                Button(experienceMode == .simple ? "Mehr über diesen Klang entdecken" : "Detailmodus: Notation, Voicing und Instrumente", systemImage: "sidebar.trailing") {
                    showDetails()
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
        }
        .onChange(of: initialDraft) { _, value in draft = value }
    }

    private var hasChanges: Bool { draft != event }

    private func changeRoot(_ root: Int) {
        draft.root = root
        draft.pitches = TheoryChord(root: root, quality: draft.quality).pitches
        draft.bassPitch = nil
        changed()
    }

    private func changeQuality(_ quality: ChordQuality) {
        draft.quality = quality
        draft.pitches = TheoryChord(root: draft.root, quality: quality).pitches
        draft.bassPitch = nil
        changed()
    }

    private func invert(upward: Bool) {
        draft.pitches = MusicTheory.invertedVoicing(draft.pitches, upward: upward)
        changed()
    }

    private func changed() {
        onChange(draft)
        MIDIService.shared.previewChord(draft.pitches)
    }

    @ViewBuilder private func voiceLeadingRow(title: String, from: TheoryChord, to: TheoryChord) -> some View {
        let analysis = MusicTheory.voiceLeading(from: from, to: to)
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            if !analysis.commonPitchClasses.isEmpty {
                Label(
                    "Liegetöne: \(analysis.commonPitchClasses.map { MusicTheory.noteName($0, prefersFlats: MusicTheory.prefersFlats(tonic: scene.tonic)) }.joined(separator: ", "))",
                    systemImage: "link"
                )
                .foregroundStyle(ChordflowDesign.commonMint)
            }
            if !analysis.semitoneMoves.isEmpty {
                Label(
                    analysis.semitoneMoves.map { "\(MusicTheory.noteName($0.from))→\(MusicTheory.noteName($0.to))" }.joined(separator: " · "),
                    systemImage: "arrow.left.arrow.right"
                )
                .foregroundStyle(ChordflowDesign.resolutionGold)
            }
            if analysis.commonPitchClasses.isEmpty && analysis.semitoneMoves.isEmpty {
                Text("Keine direkten Liege- oder Halbtonverbindungen")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct ArrangementChordDetail: View {
    let event: ChordEvent
    let initialDraft: ChordEvent
    let scene: ScoreScene
    let measure: Int
    @Binding var showsWholeScore: Bool
    let stage: (ChordEvent) -> Void
    let save: (ChordEvent) -> Void
    let discard: () -> Void
    let canNavigate: (Int) -> Bool
    let navigate: (Int) -> Void
    let canNavigateMeasure: (Int) -> Bool
    let navigateMeasure: (Int) -> Void
    let close: () -> Void
    @State private var draft: ChordEvent
    @State private var snapsToScale = true
    @State private var notationHeight: CGFloat = 250
    @State private var offset = CGSize.zero
    @State private var showsTheory = true
    @State private var showsKeyboard = false
    @GestureState private var dragOffset = CGSize.zero
    @StateObject private var notationController = ScoreController()

    init(event: ChordEvent, initialDraft: ChordEvent, scene: ScoreScene, measure: Int, showsWholeScore: Binding<Bool>, stage: @escaping (ChordEvent) -> Void, save: @escaping (ChordEvent) -> Void, discard: @escaping () -> Void, canNavigate: @escaping (Int) -> Bool, navigate: @escaping (Int) -> Void, canNavigateMeasure: @escaping (Int) -> Bool, navigateMeasure: @escaping (Int) -> Void, close: @escaping () -> Void) {
        self.event = event
        self.initialDraft = initialDraft
        self.scene = scene
        self.measure = measure
        _showsWholeScore = showsWholeScore
        self.stage = stage
        self.save = save
        self.discard = discard
        self.canNavigate = canNavigate
        self.navigate = navigate
        self.canNavigateMeasure = canNavigateMeasure
        self.navigateMeasure = navigateMeasure
        self.close = close
        _draft = State(initialValue: initialDraft)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button(action: close) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .help("Schließen (Esc)")
                Button("Vorheriger Takt", systemImage: "chevron.left") { navigateMeasure(-1) }
                    .labelStyle(.iconOnly)
                    .keyboardShortcut(.leftArrow, modifiers: [])
                    .disabled(!canNavigateMeasure(-1))
                    .help("Einen Takt zurück (←)")
                Button("Vorheriger Akkord", systemImage: "backward.end") { navigate(-1) }
                    .labelStyle(.iconOnly)
                    .keyboardShortcut(.leftArrow, modifiers: [.option])
                    .disabled(!canNavigate(-1))
                    .help("Zum vorherigen Akkord (⌥←)")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Akkord in Takt \(measure)").font(ChordflowDesign.heading(.title2, size: 27))
                    Text("Position \(event.position + 1) · \(event.beats) Zählzeiten").font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                .contentShape(Rectangle())
                .gesture(moveGesture)
                .help("Zum Verschieben ziehen")
                Picker("Notenblatt", selection: $showsWholeScore) {
                    Text("Fokus").tag(false)
                    Text("Ganze Partitur").tag(true)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 205)
                .help("Zwischen dem zentrierten aktiven Takt und der gesamten Partitur wechseln")
                Button("Nächster Akkord", systemImage: "forward.end") { navigate(1) }
                    .labelStyle(.iconOnly)
                    .keyboardShortcut(.rightArrow, modifiers: [.option])
                    .disabled(!canNavigate(1))
                    .help("Zum nächsten Akkord (⌥→)")
                Button("Nächster Takt", systemImage: "chevron.right") { navigateMeasure(1) }
                    .labelStyle(.iconOnly)
                    .keyboardShortcut(.rightArrow, modifiers: [])
                    .disabled(!canNavigateMeasure(1))
                    .help("Einen Takt vor (→)")
            }
            if hasUnsavedChanges {
                HStack(spacing: 10) {
                    Label("Ungespeicherte Änderung", systemImage: "pencil.circle.fill")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(ChordflowDesign.alteredPink)
                    Button("Änderung speichern", systemImage: "checkmark") { save(draft) }
                        .buttonStyle(.borderedProminent)
                    Button("Verwerfen", systemImage: "arrow.uturn.backward") {
                        draft = event
                        discard()
                        MIDIService.shared.previewChord(event.pitches)
                    }
                    Text("Der Entwurf bleibt beim Navigieren erhalten und ist in Karte und Partitur markiert.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            editControls
            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 6) {
                    ScoreWebView(abc: ABCScoreBuilder.singleChord(draft.chord, scene: scene), height: $notationHeight, controller: notationController)
                        .frame(width: 380, height: 185)
                    HStack(spacing: 6) {
                        ForEach(draft.pitches, id: \.self) { pitch in
                            let analysis = MusicTheory.analyzeTone(pitch, tonic: scene.tonic, sceneScale: scene.scale, trackScale: scene.scale, chord: draft.chord)
                            Text(MusicTheory.pitchName(pitch, prefersFlats: MusicTheory.prefersFlats(tonic: scene.tonic)))
                                .font(.caption.monospaced().weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .foregroundStyle(toneRoleColor(analysis.role))
                                .background(toneRoleColor(analysis.role).opacity(0.14), in: Capsule())
                                .overlay(Capsule().stroke(toneRoleColor(analysis.role).opacity(0.65)))
                                .help(analysis.explanation)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(width: 380)
                DisclosureGroup("Harmonische Einordnung", isExpanded: $showsTheory) {
                    ChordTheoryExplanation(chord: draft.chord, scene: scene, showsSymbol: false)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(.top, 8)
                }
                .font(.callout.weight(.semibold))
            }
            .frame(height: 235, alignment: .top)
            VoicingPitchEditor(pitches: draft.pitches, tonic: scene.tonic, scale: scene.scale) { index, pitch in
                guard draft.pitches.indices.contains(index) else { return }
                draft.pitches[index] = snapsToScale ? MusicTheory.nearestScalePitch(to: pitch, tonic: scene.tonic, kind: scene.scale) : pitch
                draft.pitches.sort()
                commit()
            }
            DisclosureGroup("Klaviatur", isExpanded: $showsKeyboard) {
                PianoView(pitches: draft.pitches, scale: Set(MusicTheory.scale(tonic: scene.tonic, kind: scene.scale)), tonic: scene.tonic, keyHeight: 64)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
            }
            .font(.callout.weight(.semibold))
        }
        .padding(16)
        .frame(width: 820, height: 650)
        .background(ChordflowDesign.panelBackground.opacity(0.98), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.separator.opacity(0.55)))
        .shadow(color: .black.opacity(0.28), radius: 20, y: 8)
        .offset(x: offset.width + dragOffset.width, y: offset.height + dragOffset.height)
        .onAppear {
            notationController.transposeHandler = { selection, semitones in
                transposeSelectedPitch(selection, by: semitones)
            }
            notationController.selectionHandler = { selection in
                let analysis = MusicTheory.analyzeTone(selection.midi, tonic: scene.tonic, sceneScale: scene.scale, trackScale: scene.scale, chord: draft.chord)
                notationController.setSelectedNoteColor(toneRoleCSSColor(analysis.role))
            }
        }
        .onChange(of: initialDraft) { _, changed in draft = changed }
        .onDisappear {
            notationController.transposeHandler = nil
            notationController.selectionHandler = nil
            MIDIService.shared.stopChordPreview()
        }
    }

    private var editControls: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 10) {
                Picker("Grundton", selection: Binding(get: { draft.root }, set: { root in
                    draft.root = root
                    draft.pitches = TheoryChord(root: root, quality: draft.quality).pitches
                    draft.bassPitch = nil
                    commit()
                })) {
                    ForEach(0..<12, id: \.self) { root in
                        Text(MusicTheory.noteName(root, prefersFlats: MusicTheory.prefersFlats(tonic: scene.tonic))).tag(root)
                    }
                }
                .frame(width: 145)
                Picker("Akkord", selection: Binding(get: { draft.quality }, set: { quality in
                    draft.quality = quality
                    draft.pitches = TheoryChord(root: draft.root, quality: quality).pitches
                    commit()
                })) {
                    ForEach(ChordQuality.allCases) { Text($0.title).tag($0) }
                }
                .frame(width: 210)
                Button("Lage höher ↑") { draft.pitches = MusicTheory.invertedVoicing(draft.pitches, upward: true); commit() }
                    .help("Den tiefsten Akkordton eine Oktave nach oben setzen")
                Button("Lage tiefer ↓") { draft.pitches = MusicTheory.invertedVoicing(draft.pitches, upward: false); commit() }
                    .help("Den höchsten Akkordton eine Oktave nach unten setzen")
            }
            VoicingPositionLabel(chord: draft.chord, prefersFlats: MusicTheory.prefersFlats(tonic: scene.tonic))
            HStack(spacing: 8) {
                Toggle("Beim Ziehen auf Abschnittstonleiter einrasten", isOn: $snapsToScale).toggleStyle(.switch)
                Text(snapsToScale ? "Leiterfremde Halbtöne werden übersprungen; ↑/↓ bleibt chromatisch." : "Alle Eingaben sind chromatisch.")
                    .foregroundStyle(.secondary)
            }
        }
        .controlSize(.small)
    }

    private var hasUnsavedChanges: Bool { draft != event }

    private func commit() {
        stage(draft)
        MIDIService.shared.previewChord(draft.pitches)
    }

    private func transposeSelectedPitch(_ selection: ScoreNoteSelection, by semitones: Int) {
        guard let index = draft.pitches.firstIndex(of: selection.midi) else {
            notationController.report("Der gewählte Akkordton ist im aktuellen Voicing nicht mehr vorhanden.")
            return
        }
        let changedPitch = selection.midi + semitones
        guard (0...127).contains(changedPitch) else {
            notationController.report("Die Tonhöhe liegt außerhalb des MIDI-Bereichs.")
            return
        }
        draft.pitches[index] = changedPitch
        draft.pitches.sort()
        let analysis = MusicTheory.analyzeTone(changedPitch, tonic: scene.tonic, sceneScale: scene.scale, trackScale: scene.scale, chord: draft.chord)
        notationController.setSelectedNoteColor(toneRoleCSSColor(analysis.role))
        notationController.updateSelectedPitch(changedPitch)
        commit()
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .global)
            .updating($dragOffset) { value, state, _ in state = value.translation }
            .onEnded { value in
                offset.width += value.translation.width
                offset.height += value.translation.height
            }
    }

}

private struct VoicingPositionLabel: View {
    let chord: TheoryChord
    let prefersFlats: Bool

    var body: some View {
        let analysis = MusicTheory.analyzeVoicing(chord, prefersFlats: prefersFlats)
        Label(MusicTheory.inversionDescription(chord, prefersFlats: prefersFlats), systemImage: "pianokeys")
            .font(.callout.weight(.semibold))
            .foregroundStyle(analysis.role == .altered ? ChordflowDesign.alteredPink : analysis.role == .inversion ? ChordflowDesign.inversionPurple : ChordflowDesign.chordToneBlue)
            .frame(width: 255, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.quaternary.opacity(0.55), in: Capsule())
            .accessibilityLabel("Akkordlage: \(MusicTheory.inversionDescription(chord, prefersFlats: prefersFlats))")
    }
}

private struct ChordTheoryExplanation: View {
    let chord: TheoryChord
    let scene: ScoreScene
    var showsSymbol = true

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if showsSymbol { Text(chord.symbol).font(ChordflowDesign.heading(.title, size: 34)) }
            LabeledContent("Typ", value: chord.quality.title)
            LabeledContent("Töne", value: chord.pitches.map { MusicTheory.pitchName($0) }.joined(separator: " · "))
            LabeledContent("Intervalle", value: chord.intervalLabels.joined(separator: " · "))
            LabeledContent("Stufe", value: MusicTheory.romanDegree(root: chord.root, tonic: scene.tonic, kind: scene.scale) ?? "chromatischer Grundton")
            ForEach(chord.pitches, id: \.self) { pitch in
                let analysis = MusicTheory.analyzeTone(pitch, tonic: scene.tonic, sceneScale: scene.scale, trackScale: scene.scale, chord: chord)
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Circle().fill(toneRoleColor(analysis.role)).frame(width: 8, height: 8)
                    Text("\(MusicTheory.noteName(pitch)): \(analysis.title)").font(.caption.bold())
                    Text(analysis.explanation).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
    }
}

private func toneRoleColor(_ role: ToneRole) -> Color {
    switch role {
    case .chordTone: ChordflowDesign.chordToneBlue
    case .chordColor: ChordflowDesign.tensionOrange
    case .common: ChordflowDesign.commonMint
    case .scene: ChordflowDesign.inversionPurple
    case .track: .cyan
    case .tension: .red
    }
}

private func toneRoleCSSColor(_ role: ToneRole) -> String {
    switch role { case .chordTone: "#0a84ff"; case .chordColor: "#ff9f0a"; case .common: "#30d158"; case .scene: "#bf5af2"; case .track: "#64d2ff"; case .tension: "#ff453a" }
}

private struct ToneRoleLegend: View {
    private let entries: [(ToneRole, String)] = [
        (.chordTone, "Akkordton"), (.chordColor, "erklärte Akkordfarbe"), (.common, "gemeinsam"),
        (.scene, "nur Abschnitt"), (.track, "nur Spur"), (.tension, "offene Spannung")
    ]
    var body: some View {
        HStack(spacing: 12) {
            ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                Label {
                    Text(entry.1)
                } icon: {
                    Circle().fill(toneRoleColor(entry.0)).frame(width: 8, height: 8)
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

private struct VoiceLeadingLegend: View {
    var body: some View {
        HStack(spacing: 14) {
            Label("gemeinsamer Liegeton", systemImage: "link").foregroundStyle(ChordflowDesign.commonMint)
            Label("Halbtonauflösung", systemImage: "arrow.left.arrow.right").foregroundStyle(ChordflowDesign.resolutionGold)
            Text("Die Karte beschreibt den Weg zum jeweils nächsten Akkord.").foregroundStyle(.secondary)
        }
        .font(.caption)
    }
}

private struct VoicingPitchEditor: View {
    let pitches: [Int]
    let tonic: Int
    let scale: ScaleKind
    let onChange: (Int, Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Voicing bearbeiten").font(.headline)
            Text("Ziehe einen Ton oder wähle ihn in der Notenzeile und verschiebe ihn mit ↑/↓ chromatisch. Die Partitur wird sofort neu gesetzt.").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                ForEach(Array(pitches.enumerated()), id: \.offset) { index, pitch in
                    DraggablePitchCard(pitch: pitch, inScale: MusicTheory.contains(pitch, tonic: tonic, kind: scale)) { semitones in
                        onChange(index, max(36, min(88, pitch - semitones)))
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct DraggablePitchCard: View {
    let pitch: Int
    let inScale: Bool
    let moved: (Int) -> Void
    @GestureState private var translation: CGFloat = 0

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "arrow.up.and.down").font(.caption).foregroundStyle(.secondary)
            Text(MusicTheory.pitchName(pitch)).font(.headline.monospaced())
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(inScale ? ChordflowDesign.chordToneBlue.opacity(0.14) : ChordflowDesign.tensionOrange.opacity(0.18), in: RoundedRectangle(cornerRadius: 9))
        .offset(y: translation)
        .gesture(DragGesture()
            .updating($translation) { value, state, _ in state = value.translation.height }
            .onEnded { moved(Int(($0.translation.height / 11).rounded())) })
    }
}

private struct PianoView: View {
    let pitches: [Int]; let scale: Set<Int>; let tonic: Int
    var keyHeight: CGFloat = 105
    var body: some View {
        HStack(spacing: 2) {
            ForEach(48..<73, id: \.self) { pitch in
                let pitchClass = MusicTheory.normalized(pitch)
                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 3).fill(pitches.contains(pitch) ? ChordflowDesign.chordToneBlue : scale.contains(pitchClass) ? ChordflowDesign.chordToneBlue.opacity(0.2) : Color.white).overlay(RoundedRectangle(cornerRadius: 3).stroke(pitchClass == tonic ? ChordflowDesign.actionTeal : .gray))
                    Text(MusicTheory.noteName(pitch)).font(.caption2)
                }.frame(width: 25, height: keyHeight)
            }
        }.padding(10).background(.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct CircleOfFifthsView: View {
    let tonic: Int; let select: (Int) -> Void
    var body: some View {
        GeometryReader { geometry in
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            ZStack {
                Circle().fill(.quaternary.opacity(0.35)); Circle().stroke(.secondary.opacity(0.3), lineWidth: 2)
                ForEach(Array(MusicTheory.circleRoots.enumerated()), id: \.offset) { index, root in
                    let angle = Double(index) / 12 * 2 * Double.pi - Double.pi / 2
                    Button {
                        select(root)
                    } label: {
                        VStack(spacing: 1) {
                            Text(MusicTheory.noteName(root, prefersFlats: index > 6)).font(.headline)
                            Text(MusicTheory.noteName(root + 9, prefersFlats: index > 6) + "m").font(.caption)
                        }.frame(width: 62, height: 48).background(root == tonic ? Color.accentColor : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10)).foregroundStyle(root == tonic ? .white : .primary)
                    }.buttonStyle(.plain).position(x: center.x + cos(angle) * 165, y: center.y + sin(angle) * 165)
                }
                VStack { Text(MusicTheory.noteName(tonic)).font(.system(size: 44, weight: .bold)); Text("Tonales Zentrum").foregroundStyle(.secondary) }
            }
        }
    }
}
