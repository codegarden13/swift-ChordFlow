import SwiftUI

enum WorkspaceMode: String, CaseIterable, Identifiable {
    case arrangement = "Arrangement"
    case chordLab = "Akkordlabor"
    case circle = "Quintenzirkel"
    case tracks = "Spuren"
    var id: String { rawValue }
}

struct TheoryWorkspaceView: View {
    @ObservedObject var library: ScoreLibrary
    let scene: ScoreScene
    let mode: WorkspaceMode
    @State private var root = 0
    @State private var quality = ChordQuality.major
    @State private var pitches = TheoryChord(root: 0, quality: .major).pitches

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
        .onChange(of: root) { _, _ in resetVoicing() }
        .onChange(of: quality) { _, _ in resetVoicing() }
    }

    private var arrangement: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Akkordfolge").font(.title2.bold())
            Text("Ziehe Karten, um die Reihenfolge zu ändern. Die Stufe bezieht sich auf \(MusicTheory.noteName(scene.tonic)) \(scene.scale.title).").foregroundStyle(.secondary)
            if library.chordEvents.isEmpty {
                ContentUnavailableView("Noch keine Akkorde", systemImage: "rectangle.stack.badge.plus", description: Text("Entwirf einen Akkord im Akkordlabor und füge ihn hier ein."))
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(library.chordEvents) { event in chordCard(event) }
                    }.padding(.vertical, 8)
                }
            }
            Spacer()
        }.padding(18)
    }

    private func chordCard(_ event: ChordEvent) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(event.chord.symbol).font(.title2.bold())
                Spacer()
                Button("Löschen", systemImage: "xmark.circle", role: .destructive) { library.deleteChord(event.id) }.labelStyle(.iconOnly).buttonStyle(.plain)
            }
            Text(MusicTheory.romanDegree(root: event.root, tonic: scene.tonic, kind: scene.scale) ?? "leiterfremd").font(.headline).foregroundStyle(MusicTheory.contains(event.root, tonic: scene.tonic, kind: scene.scale) ? .blue : .orange)
            Text(event.pitches.map { MusicTheory.pitchName($0, prefersFlats: MusicTheory.prefersFlats(tonic: scene.tonic)) }.joined(separator: " · ")).font(.caption.monospaced())
            Stepper("\(event.beats) Zählzeiten", value: Binding(get: { event.beats }, set: { value in
                var changed = event; changed.beats = value; library.updateChord(changed)
            }), in: 1...32)
        }
        .padding(14).frame(width: 190).frame(minHeight: 150).background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
        .draggable(String(event.id))
        .dropDestination(for: String.self) { values, _ in
            guard let raw = values.first, let source = Int64(raw) else { return false }
            library.moveChord(source, before: event.id); return true
        }
    }

    private var chordLab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("Akkordlabor").font(.title2.bold())
                    Spacer()
                    Button("In Szene einfügen", systemImage: "plus") { library.addChord(chord) }.buttonStyle(.borderedProminent)
                }
                HStack {
                    Picker("Grundton", selection: $root) { ForEach(0..<12, id: \.self) { Text(MusicTheory.noteName($0, prefersFlats: MusicTheory.prefersFlats(tonic: scene.tonic))).tag($0) } }.frame(width: 150)
                    Picker("Akkord", selection: $quality) { ForEach(ChordQuality.allCases) { Text($0.title).tag($0) } }.frame(width: 220)
                    Button("Umkehrung ↑") { invert(up: true) }
                    Button("Umkehrung ↓") { invert(up: false) }
                }
                HStack(alignment: .top, spacing: 18) {
                    ChordNoteCanvas(pitches: pitches, tonic: scene.tonic, scale: scene.scale) { index, pitch in pitches[index] = pitch; pitches.sort() }
                    chordExplanation
                }
                PianoView(pitches: pitches, scale: Set(MusicTheory.scale(tonic: scene.tonic, kind: scene.scale)), tonic: scene.tonic)
                Text("Ziehe einen Notenkopf im Notenfeld nach oben oder unten. Er rastet chromatisch auf der nächstgelegenen Tonhöhe ein.").font(.caption).foregroundStyle(.secondary)
            }.padding(18)
        }
    }

    private var chordExplanation: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(chord.symbol).font(.system(size: 34, weight: .bold))
            LabeledContent("Typ", value: quality.title)
            LabeledContent("Töne", value: pitches.map { MusicTheory.pitchName($0) }.joined(separator: " · "))
            LabeledContent("Intervalle", value: chord.intervalLabels.joined(separator: " · "))
            LabeledContent("Stufe", value: MusicTheory.romanDegree(root: root, tonic: scene.tonic, kind: scene.scale) ?? "leiterfremd")
            let foreign = pitches.filter { !MusicTheory.contains($0, tonic: scene.tonic, kind: scene.scale) }
            Label(foreign.isEmpty ? "Alle Töne liegen in der Tonleiter" : "Leiterfremd: \(foreign.map { MusicTheory.noteName($0) }.joined(separator: ", "))", systemImage: foreign.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill").foregroundStyle(foreign.isEmpty ? .green : .orange)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
    }

    private var circle: some View {
        HStack(spacing: 30) {
            CircleOfFifthsView(tonic: scene.tonic) { newTonic in
                var changed = scene; changed.tonic = newTonic; library.updateScene(changed)
            }.frame(width: 440, height: 440)
            VStack(alignment: .leading, spacing: 14) {
                Text("\(MusicTheory.noteName(scene.tonic, prefersFlats: MusicTheory.prefersFlats(tonic: scene.tonic))) \(scene.scale.title)").font(.largeTitle.bold())
                Text(MusicTheory.scaleNames(tonic: scene.tonic, kind: scene.scale).joined(separator: " – ")).font(.title3)
                Text("Klicke eine Tonart im Kreis. Die Szene übernimmt das tonale Zentrum; vorhandene Noten werden dabei nicht ungefragt transponiert.").foregroundStyle(.secondary)
                Divider()
                Text("Verwandte Funktionen").font(.headline)
                LabeledContent("Dominante", value: MusicTheory.noteName(scene.tonic + 7))
                LabeledContent("Subdominante", value: MusicTheory.noteName(scene.tonic + 5))
                LabeledContent("Paralleltonart", value: MusicTheory.noteName(scene.tonic + (scene.scale == .major ? 9 : 3)) + (scene.scale == .major ? " Moll" : " Dur"))
            }.frame(maxWidth: 420)
            Spacer(minLength: 0)
        }
        .padding(.leading, 4)
        .padding(.top, 12)
        .padding(.trailing, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func resetVoicing() { pitches = TheoryChord(root: root, quality: quality).pitches }
    private func invert(up: Bool) {
        guard !pitches.isEmpty else { return }
        if up { pitches[0] += 12; pitches.sort() } else { pitches[pitches.count - 1] -= 12; pitches.sort() }
    }
}

private struct ChordNoteCanvas: View {
    let pitches: [Int]
    let tonic: Int
    let scale: ScaleKind
    let onChange: (Int, Int) -> Void
    private let step: CGFloat = 11

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(.background).stroke(.quaternary)
                ForEach(0..<5) { line in Path { path in let y = 92 + CGFloat(line) * step * 2; path.move(to: CGPoint(x: 22, y: y)); path.addLine(to: CGPoint(x: geometry.size.width - 22, y: y)) }.stroke(.secondary, lineWidth: 1) }
                Text("𝄞").font(.system(size: 74)).position(x: 48, y: 132)
                ForEach(Array(pitches.enumerated()), id: \.offset) { index, pitch in
                    DraggableNoteHead(label: MusicTheory.pitchName(pitch), inScale: MusicTheory.contains(pitch, tonic: tonic, kind: scale), step: step) { semitones in
                        onChange(index, max(36, min(88, pitch - semitones)))
                    }
                        .position(x: 115 + CGFloat(index) * 58, y: y(for: pitch))
                }
            }
        }.frame(width: 360, height: 260)
    }
    private func y(for pitch: Int) -> CGFloat { 70 + CGFloat(72 - pitch) * step }
}

private struct NoteHead: View {
    let label: String; let inScale: Bool
    var body: some View { VStack(spacing: 2) { Ellipse().fill(inScale ? Color.blue : .orange).frame(width: 25, height: 17); Text(label).font(.caption2.bold()) } }
}

private struct DraggableNoteHead: View {
    let label: String; let inScale: Bool; let step: CGFloat; let moved: (Int) -> Void
    @GestureState private var translation: CGFloat = 0
    var body: some View {
        NoteHead(label: label, inScale: inScale)
            .offset(y: translation)
            .gesture(DragGesture()
                .updating($translation) { value, state, _ in state = value.translation.height }
                .onEnded { moved(Int(($0.translation.height / step).rounded())) })
    }
}

private struct PianoView: View {
    let pitches: [Int]; let scale: Set<Int>; let tonic: Int
    var body: some View {
        HStack(spacing: 2) {
            ForEach(48..<73, id: \.self) { pitch in
                let pitchClass = MusicTheory.normalized(pitch)
                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 3).fill(pitches.contains(pitch) ? Color.blue : scale.contains(pitchClass) ? Color.blue.opacity(0.2) : Color.white).overlay(RoundedRectangle(cornerRadius: 3).stroke(pitchClass == tonic ? Color.orange : .gray))
                    Text(MusicTheory.noteName(pitch)).font(.caption2)
                }.frame(width: 25, height: 105)
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
