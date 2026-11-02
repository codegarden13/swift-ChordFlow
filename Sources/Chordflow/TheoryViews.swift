import MusicTheoryUI
import SwiftUI

enum WorkspaceMode: String, CaseIterable, Identifiable {
    case arrangement = "Arrangement"
    case chordLab = "Akkordlabor"
    case circle = "Quintenzirkel"
    case tracks = "Spuren"
    var id: String { rawValue }
}

private enum ChordLabDestination: Hashable {
    case append
    case insertBefore(Int64)
    case replace(Int64)
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
    let scoreController: ScoreController
    @Binding var selectedArrangementChord: ChordEvent?
    @State private var root = 0
    @State private var quality = ChordQuality.major
    @State private var pitches = TheoryChord(root: 0, quality: .major).pitches
    @State private var chordDestination = ChordLabDestination.append
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
                Text("Akkordfolge").font(.title2.bold())
                HStack(alignment: .firstTextBaseline) {
                    Text("Ziehe Karten, um die Reihenfolge zu ändern. Die Stufe bezieht sich auf \(MusicTheory.noteName(scene.tonic)) \(scene.scale.title).").foregroundStyle(.secondary)
                    Spacer()
                    Picker("Analyse", selection: $arrangementAnalysisMode) {
                        ForEach(ArrangementAnalysisMode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 230)
                }
                if arrangementAnalysisMode == .roles { ToneRoleLegend() }
                else { VoiceLeadingLegend() }
                if library.chordEvents.isEmpty {
                    ContentUnavailableView("Noch keine Akkorde", systemImage: "rectangle.stack.badge.plus", description: Text("Entwirf einen Akkord im Akkordlabor und füge ihn hier ein."))
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 190, maximum: 240), spacing: 12)], alignment: .leading, spacing: 12) {
                            ForEach(library.chordEvents) { event in chordCard(event) }
                        }.padding(.vertical, 8)
                    }
                }
                Spacer()
        }
        .padding(18)
    }

    private func chordCard(_ event: ChordEvent) -> some View {
        let voicing = MusicTheory.analyzeVoicing(event.chord, prefersFlats: MusicTheory.prefersFlats(tonic: scene.tonic))
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(event.chord.symbol).font(.title2.bold()).foregroundStyle(voicingColor(event))
                Spacer()
                Button("Löschen", systemImage: "xmark.circle", role: .destructive) { library.deleteChord(event.id) }.labelStyle(.iconOnly).buttonStyle(.plain)
            }
            Label(voicing.description, systemImage: voicing.isAltered ? "waveform.badge.exclamationmark" : "pianokeys")
                .font(.caption.weight(.semibold))
                .foregroundStyle(voicing.isAltered ? .orange : .secondary)
                .lineLimit(2)
            Text(MusicTheory.romanDegree(root: event.root, tonic: scene.tonic, kind: scene.scale) ?? "chromatischer Akkord").font(.headline).foregroundStyle(functionColor(event.root))
            Text(event.pitches.map { MusicTheory.pitchName($0, prefersFlats: MusicTheory.prefersFlats(tonic: scene.tonic)) }.joined(separator: " · ")).font(.caption.monospaced())
            if arrangementAnalysisMode == .voiceLeading { voiceLeadingSummary(for: event) }
            Spacer(minLength: 0)
            Stepper("\(event.beats) Zählzeiten", value: Binding(get: { event.beats }, set: { value in
                var changed = event; changed.beats = value; library.updateChord(changed)
            }), in: 1...32)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 220, maxHeight: 220, alignment: .topLeading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
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

    private func voicingColor(_ event: ChordEvent) -> Color {
        switch MusicTheory.analyzeVoicing(event.chord).role {
        case .standard: .blue
        case .inversion: .purple
        case .altered: .orange
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
                        .foregroundStyle(.green)
                }
                if !analysis.semitoneMoves.isEmpty {
                    Label(analysis.semitoneMoves.map { "\(MusicTheory.noteName($0.from))→\(MusicTheory.noteName($0.to))" }.joined(separator: " · "), systemImage: "arrow.left.arrow.right")
                        .foregroundStyle(.orange)
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
                    Text("Akkordlabor").font(.title2.bold())
                    Spacer()
                }
                HStack {
                    Picker("Grundton", selection: Binding(get: { root }, set: { root = $0; resetVoicing() })) { ForEach(0..<12, id: \.self) { Text(MusicTheory.noteName($0, prefersFlats: MusicTheory.prefersFlats(tonic: scene.tonic))).tag($0) } }.frame(maxWidth: 180)
                    Picker("Akkord", selection: Binding(get: { quality }, set: { quality = $0; resetVoicing() })) { ForEach(ChordQuality.allCases) { Text($0.title).tag($0) } }.frame(maxWidth: 240)
                    Spacer()
                }
                HStack {
                    Button("Lage höher ↑") { invert(up: true) }
                        .help("Den tiefsten Akkordton eine Oktave nach oben setzen")
                    Button("Lage tiefer ↓") { invert(up: false) }
                        .help("Den höchsten Akkordton eine Oktave nach unten setzen")
                    Toggle("Beim Ziehen auf Szenentonleiter einrasten", isOn: $snapsToScale).toggleStyle(.switch)
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
                sceneDestinationPanel
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
            root = event.root; quality = event.quality; pitches = event.pitches
        }
        .onChange(of: pitches) { _, _ in if automaticallyPreviewsChord { previewChord() } }
        .onChange(of: automaticallyPreviewsChord) { _, enabled in if enabled { previewChord() } else { MIDIService.shared.stopChordPreview() } }
        .onAppear { if automaticallyPreviewsChord { previewChord() } }
        .onDisappear { MIDIService.shared.stopChordPreview() }
    }

    private var sceneDestinationPanel: some View {
        GroupBox("In Szene übernehmen") {
            VStack(alignment: .leading, spacing: 10) {
                if library.chordEvents.isEmpty {
                    Label("Die Szene ist leer. Dieser Akkord wird der erste Akkord und beginnt in Takt 1.", systemImage: "1.circle.fill")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Aktion und Position", selection: $chordDestination) {
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
                    .frame(maxWidth: 420)
                    Text(destinationExplanation).font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Button(destinationButtonTitle, systemImage: destinationButtonIcon) { applyChordToScene() }
                        .buttonStyle(.borderedProminent)
                    if let sceneActionMessage {
                        Label(sceneActionMessage, systemImage: "checkmark.circle.fill").font(.callout).foregroundStyle(.green)
                    }
                }
            }
            .padding(.top, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var appendMeasure: Int { library.chordEvents.reduce(0) { $0 + $1.beats } / 4 + 1 }
    private func measureNumber(for event: ChordEvent) -> Int {
        library.chordEvents.filter { $0.position < event.position }.reduce(0) { $0 + $1.beats } / 4 + 1
    }
    private var destinationExplanation: String {
        switch chordDestination {
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
        if library.chordEvents.isEmpty { return "Als ersten Akkord in Takt 1 einfügen" }
        switch chordDestination { case .append: return "Am Ende einfügen"; case .insertBefore: return "An Position einfügen"; case .replace: return "Akkord ersetzen" }
    }
    private var destinationButtonIcon: String {
        if case .replace = chordDestination { return "arrow.triangle.2.circlepath" }
        return "plus"
    }
    private func applyChordToScene() {
        if library.chordEvents.isEmpty {
            library.addChord(chord)
            chordDestination = .append
            sceneActionMessage = "\(chord.symbol) beginnt in Takt 1."
            return
        }
        switch chordDestination {
        case .append:
            let measure = appendMeasure
            library.addChord(chord)
            sceneActionMessage = "\(chord.symbol) wurde ab Takt \(measure) angefügt."
        case let .insertBefore(id):
            let measure = library.chordEvents.first(where: { $0.id == id }).map(measureNumber) ?? 1
            library.insertChord(chord, before: id)
            sceneActionMessage = "\(chord.symbol) wurde in Takt \(measure) eingefügt."
        case let .replace(id):
            let measure = library.chordEvents.first(where: { $0.id == id }).map(measureNumber) ?? 1
            library.replaceChord(id: id, with: chord)
            sceneActionMessage = "Akkord in Takt \(measure) wurde durch \(chord.symbol) ersetzt."
        }
    }

    private var circle: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(MusicTheory.noteName(scene.tonic, prefersFlats: MusicTheory.prefersFlats(tonic: scene.tonic))) \(scene.scale.title)").font(.title2.bold())
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
        case 0, 3, 4, 8, 9: .blue
        case 5, 2: .purple
        case 7, 11: .orange
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

struct ArrangementChordDetail: View {
    let event: ChordEvent
    let scene: ScoreScene
    let measure: Int
    let update: (ChordEvent) -> Void
    let close: () -> Void
    @State private var draft: ChordEvent
    @State private var snapsToScale = true
    @State private var notationHeight: CGFloat = 250
    @State private var offset = CGSize.zero
    @GestureState private var dragOffset = CGSize.zero
    @StateObject private var notationController = ScoreController()

    init(event: ChordEvent, scene: ScoreScene, measure: Int, update: @escaping (ChordEvent) -> Void, close: @escaping () -> Void) {
        self.event = event
        self.scene = scene
        self.measure = measure
        self.update = update
        self.close = close
        _draft = State(initialValue: event)
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
                VStack(alignment: .leading, spacing: 2) {
                    Text("Akkord in Takt \(measure)").font(.title2.bold())
                    Text("Position \(event.position + 1) · \(event.beats) Zählzeiten").font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                .contentShape(Rectangle())
                .gesture(moveGesture)
                .help("Zum Verschieben ziehen")
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
                ChordTheoryExplanation(chord: draft.chord, scene: scene, showsSymbol: false)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.top, 8)
            }
            .frame(height: 235, alignment: .top)
            VoicingPitchEditor(pitches: draft.pitches, tonic: scene.tonic, scale: scene.scale) { index, pitch in
                guard draft.pitches.indices.contains(index) else { return }
                draft.pitches[index] = snapsToScale ? MusicTheory.nearestScalePitch(to: pitch, tonic: scene.tonic, kind: scene.scale) : pitch
                draft.pitches.sort()
                commit()
            }
            PianoView(pitches: draft.pitches, scale: Set(MusicTheory.scale(tonic: scene.tonic, kind: scene.scale)), tonic: scene.tonic, keyHeight: 64)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .frame(width: 780, height: 625)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.separator.opacity(0.55)))
        .shadow(color: .black.opacity(0.22), radius: 22, y: 10)
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
        .onChange(of: event) { _, changed in draft = changed }
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
                Toggle("Beim Ziehen auf Szenentonleiter einrasten", isOn: $snapsToScale).toggleStyle(.switch)
                Text(snapsToScale ? "Leiterfremde Halbtöne werden übersprungen; ↑/↓ bleibt chromatisch." : "Alle Eingaben sind chromatisch.")
                    .foregroundStyle(.secondary)
            }
        }
        .controlSize(.small)
    }

    private func commit() { update(draft) }

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
            .foregroundStyle(analysis.role == .altered ? Color.orange : analysis.role == .inversion ? Color.purple : Color.blue)
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
            if showsSymbol { Text(chord.symbol).font(.system(size: 34, weight: .bold)) }
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
    switch role { case .chordTone: .blue; case .chordColor: .orange; case .common: .green; case .scene: .purple; case .track: .cyan; case .tension: .red }
}

private func toneRoleCSSColor(_ role: ToneRole) -> String {
    switch role { case .chordTone: "#0a84ff"; case .chordColor: "#ff9f0a"; case .common: "#30d158"; case .scene: "#bf5af2"; case .track: "#64d2ff"; case .tension: "#ff453a" }
}

private struct ToneRoleLegend: View {
    private let entries: [(ToneRole, String)] = [
        (.chordTone, "Akkordton"), (.chordColor, "erklärte Akkordfarbe"), (.common, "gemeinsam"),
        (.scene, "nur Szene"), (.track, "nur Spur"), (.tension, "offene Spannung")
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
            Label("gemeinsamer Liegeton", systemImage: "link").foregroundStyle(.green)
            Label("Halbtonauflösung", systemImage: "arrow.left.arrow.right").foregroundStyle(.orange)
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
        .background(inScale ? Color.blue.opacity(0.14) : Color.orange.opacity(0.18), in: RoundedRectangle(cornerRadius: 9))
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
                    RoundedRectangle(cornerRadius: 3).fill(pitches.contains(pitch) ? Color.blue : scale.contains(pitchClass) ? Color.blue.opacity(0.2) : Color.white).overlay(RoundedRectangle(cornerRadius: 3).stroke(pitchClass == tonic ? Color.orange : .gray))
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
