import ABCNotationKit
import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

struct ScoreNoteSelection: Equatable {
    var trackIndex: Int
    var noteIndex: Int
    var measure: Int
    var pitchIndex: Int
    var midi: Int
}

struct ScoreChordStyle: Equatable {
    let trackIndex: Int
    let noteIndex: Int
    let role: ChordVoicingRole
}

@MainActor
final class ScoreController: ObservableObject {
    enum Command {
        case play, stop, playMeasure(Int), exportMIDI

        var script: String {
            switch self {
            case .play: "return await CartoGraphABC.playAll()"
            case .stop: "return CartoGraphABC.stopPlayback()"
            case .playMeasure(let index): "return await CartoGraphABC.playMeasure(\(index))"
            case .exportMIDI: "return CartoGraphABC.exportMidi()"
            }
        }
    }

    @Published private(set) var isReady = false
    @Published private(set) var measureCount = 0
    @Published private(set) var interactionCount = 0
    @Published private(set) var errorMessage: String?
    @Published private(set) var selectedNotes: [ScoreNoteSelection] = []
    var selectedNote: ScoreNoteSelection? { selectedNotes.first }
    var transposeHandler: ((ScoreNoteSelection, Int) -> Void)?
    var multiTransposeHandler: (([ScoreNoteSelection], Int) -> Void)?
    var selectionHandler: ((ScoreNoteSelection) -> Void)?
    private weak var webView: WKWebView?
    private var highlightedChord: (measure: Int, pitches: [Int])?
    private var revealedMeasure: Int?
    private var selectedPitch: Int?
    private var marqueeSelectionEnabled = false
    private var selectedNoteColor = "#0a84ff"
    private var chordStyles: [ScoreChordStyle] = []

    func attach(_ webView: WKWebView) {
        self.webView = webView
        isReady = false
        errorMessage = nil
    }

    func ready(measures: Int) {
        measureCount = max(0, measures)
        isReady = true
        errorMessage = nil
        applyHighlight()
        applyChordStyles()
        applySelectedNoteColor()
        setMarqueeSelectionEnabled(marqueeSelectionEnabled)
        if selectedPitch != nil { applySelectedPitch() } else { applySelectedNote() }
        applyRevealedMeasure()
    }

    func interact() { interactionCount &+= 1 }

    func setChordStyles(_ styles: [ScoreChordStyle]) {
        guard chordStyles != styles else { return }
        chordStyles = styles
        applyChordStyles()
    }

    private func applyChordStyles() {
        guard let webView, isReady else { return }
        let values = chordStyles.map { ["trackIndex": $0.trackIndex, "noteIndex": $0.noteIndex, "role": $0.role.rawValue] as [String: Any] }
        webView.callAsyncJavaScript(
            "return CartoGraphABC.setChordStyles(styles)",
            arguments: ["styles": values],
            in: nil,
            in: .page
        ) { [weak self] result in
            if case .failure(let error) = result { DispatchQueue.main.async { self?.report("Akkordfarben fehlgeschlagen: \(error.localizedDescription)") } }
        }
    }

    func selectNote(_ selection: ScoreNoteSelection) { selectNotes([selection]) }

    func selectNotes(_ selections: [ScoreNoteSelection]) {
        selectedNotes = selections
        selectedPitch = nil
        selections.first.map { selectionHandler?($0) }
    }

    func clearSelectedNote() { selectedNotes = []; selectedPitch = nil }

    func requestTranspose(_ selection: ScoreNoteSelection, semitones: Int) {
        requestTranspose([selection], semitones: semitones)
    }

    func requestTranspose(_ selections: [ScoreNoteSelection], semitones: Int) {
        guard abs(semitones) == 1 else { report("Ungültiger Transpositionsschritt: \(semitones)"); return }
        guard !selections.isEmpty else { report("Die Notenauswahl ist leer."); return }
        if selections.count == 1, let selection = selections.first { transposeHandler?(selection, semitones) }
        else { multiTransposeHandler?(selections, semitones) }
    }

    func updateSelectedNote(_ selection: ScoreNoteSelection) { updateSelectedNotes([selection]) }

    func updateSelectedNotes(_ selections: [ScoreNoteSelection]) {
        selectedNotes = selections
        applySelectedNote()
    }

    func updateSelectedPitch(_ midi: Int) {
        selectedNotes = []
        selectedPitch = midi
        applySelectedPitch()
    }

    func setSelectedNoteColor(_ cssColor: String) {
        selectedNoteColor = cssColor
        applySelectedNoteColor()
    }

    private func applySelectedNoteColor() {
        guard let webView, isReady else { return }
        webView.callAsyncJavaScript(
            "return CartoGraphABC.setEditedSelectionColor(color)",
            arguments: ["color": selectedNoteColor],
            in: nil,
            in: .page
        ) { [weak self] result in
            if case .failure(let error) = result { DispatchQueue.main.async { self?.report("Auswahlfarbe fehlgeschlagen: \(error.localizedDescription)") } }
        }
    }

    func report(_ text: String) {
        NSLog("Chordflow score error: %@", text)
        errorMessage = text
    }

    func run(_ command: Command) {
        guard let webView, isReady else { errorMessage = "Partitur ist noch nicht bereit."; return }
        webView.callAsyncJavaScript(command.script, arguments: [:], in: nil, in: .page) { [weak self] result in
            DispatchQueue.main.async {
                if case .failure(let error) = result { self?.errorMessage = error.localizedDescription }
            }
        }
    }

    func showMIDINotes(_ notes: [UInt8]) {
        guard let webView, isReady else { return }
        webView.callAsyncJavaScript(
            "return CartoGraphABC.setLiveMIDINotes(notes)",
            arguments: ["notes": notes.map(Int.init)],
            in: nil,
            in: .page
        ) { _ in }
    }

    func highlightChord(measure: Int, pitches: [Int]) {
        guard measure >= 0 else { return }
        highlightedChord = (measure, pitches)
        applyHighlight()
    }

    func revealMeasure(_ measure: Int) {
        guard measure >= 0 else { return }
        revealedMeasure = measure
        applyRevealedMeasure()
    }

    private func applyRevealedMeasure() {
        guard let webView, isReady, let revealedMeasure else { return }
        webView.callAsyncJavaScript(
            "return revealScoreMeasure(measure)",
            arguments: ["measure": revealedMeasure],
            in: nil,
            in: .page
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let value):
                    guard value is [String: Any] else {
                        self.report("Takt \(revealedMeasure + 1) konnte in der Partitur nicht gefunden werden.")
                        return
                    }
                    self.errorMessage = nil
                case .failure(let error):
                    self.report("Taktposition konnte nicht angezeigt werden: \(error.localizedDescription)")
                }
            }
        }
    }

    func clearHighlight() {
        highlightedChord = nil
        guard let webView, isReady else { return }
        webView.callAsyncJavaScript("CartoGraphABC.clearSelection(); clearActiveMeasureLabel(); return true", arguments: [:], in: nil, in: .page) { _ in }
    }

    private func applyHighlight() {
        guard let webView, isReady, let highlightedChord else { return }
        webView.callAsyncJavaScript(
            "const highlighted=CartoGraphABC.highlightChord(measure, pitches); showActiveMeasureLabel(measure); return highlighted",
            arguments: ["measure": highlightedChord.measure, "pitches": highlightedChord.pitches],
            in: nil,
            in: .page
        ) { [weak self] result in
            DispatchQueue.main.async {
                switch result { case .success: self?.errorMessage = nil; case .failure(let error): self?.report("Akkordmarkierung fehlgeschlagen: \(error.localizedDescription)") }
            }
        }
    }

    private func applySelectedNote() {
        guard let webView, isReady, !selectedNotes.isEmpty else { return }
        let values = selectedNotes.map { selection in
            ["trackIndex": selection.trackIndex, "noteIndex": selection.noteIndex, "measure": selection.measure, "pitchIndex": selection.pitchIndex, "midi": selection.midi]
        }
        webView.callAsyncJavaScript(
            "return CartoGraphABC.showEditedSelections(selections)",
            arguments: ["selections": values],
            in: nil,
            in: .page
        ) { [weak self] result in
            DispatchQueue.main.async {
                switch result { case .success: self?.errorMessage = nil; case .failure(let error): self?.report("Notenauswahl fehlgeschlagen: \(error.localizedDescription)") }
            }
        }
    }

    func selectMatchingNotes() {
        guard let webView, isReady, selectedNote != nil else { report("Wähle zuerst eine Note in der Partitur aus."); return }
        webView.callAsyncJavaScript("return CartoGraphABC.selectMatchingNotes()", arguments: [:], in: nil, in: .page) { [weak self] result in
            if case .failure(let error) = result { DispatchQueue.main.async { self?.report("Gleiche Noten konnten nicht ausgewählt werden: \(error.localizedDescription)") } }
        }
    }

    func setMarqueeSelectionEnabled(_ enabled: Bool) {
        marqueeSelectionEnabled = enabled
        guard let webView, isReady else { return }
        webView.callAsyncJavaScript("return CartoGraphABC.setMarqueeSelectionEnabled(enabled)", arguments: ["enabled": enabled], in: nil, in: .page) { [weak self] result in
            if case .failure(let error) = result { DispatchQueue.main.async { self?.report("Auswahlrahmen konnte nicht umgeschaltet werden: \(error.localizedDescription)") } }
        }
    }

    private func applySelectedPitch() {
        guard let webView, isReady, let selectedPitch else { return }
        webView.callAsyncJavaScript(
            "return CartoGraphABC.showPitchSelection(midi)",
            arguments: ["midi": selectedPitch],
            in: nil,
            in: .page
        ) { [weak self] result in
            DispatchQueue.main.async {
                switch result { case .success: self?.errorMessage = nil; case .failure(let error): self?.report("Tonhöhenauswahl fehlgeschlagen: \(error.localizedDescription)") }
            }
        }
    }

}

struct ScoreWebView: NSViewRepresentable {
    let abc: String
    @Binding var height: CGFloat
    let controller: ScoreController
    var chordStyles: [ScoreChordStyle] = []

    func makeCoordinator() -> Coordinator { Coordinator(height: $height, controller: controller) }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        for name in ["abcNotationHeight", "abcNotationReady", "abcNotationMIDIExport", "abcNotationInteraction", "abcNotationSelection", "abcNotationTranspose"] {
            configuration.userContentController.add(context.coordinator, name: name)
        }
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.setValue(false, forKey: "drawsBackground")
        controller.attach(view)
        return view
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.height = $height
        controller.setChordStyles(chordStyles)
        guard abc != context.coordinator.loadedABC else { return }
        context.coordinator.loadedABC = abc
        webView.loadHTMLString(Self.html(abc), baseURL: Self.scoreResourceURL)
    }

    private static var scoreResourceURL: URL? { ABCNotationDocument.resourceURL }

    private static func html(_ source: String) -> String {
        let bridge = """
        <script>function reportHeight(){requestAnimationFrame(()=>webkit.messageHandlers.abcNotationHeight.postMessage(Math.ceil(document.body.scrollHeight)))}
        function clearActiveMeasureLabel(){document.getElementById('chordflow-active-measure')?.remove()}
        function showActiveMeasureLabel(measure){
          clearActiveMeasureLabel();
          const elements=Array.from(document.querySelectorAll('.cartograph-abc-selected-measure'));
          if(!elements.length)return null;
          const rect=elements.reduce((result,element)=>{
            const current=element.getBoundingClientRect();
            return {top:Math.min(result.top,current.top),left:Math.min(result.left,current.left)};
          },{top:Number.POSITIVE_INFINITY,left:Number.POSITIVE_INFINITY});
          const label=document.createElement('div');
          label.id='chordflow-active-measure';
          label.textContent=`Takt ${Number(measure)+1}`;
          Object.assign(label.style,{position:'absolute',zIndex:'20',left:`${Math.max(8,rect.left+window.scrollX)}px`,top:`${Math.max(4,rect.top+window.scrollY-27)}px`,padding:'3px 8px',borderRadius:'7px',background:'rgba(10,132,255,.92)',color:'white',font:'600 13px -apple-system,BlinkMacSystemFont,sans-serif',boxShadow:'0 2px 6px rgba(0,0,0,.18)',pointerEvents:'none'});
          document.body.appendChild(label);
          const target=elements.reduce((best,element)=>element.getBoundingClientRect().top<best.getBoundingClientRect().top?element:best,elements[0]);
          requestAnimationFrame(()=>target.scrollIntoView({block:'center',inline:'nearest',behavior:'smooth'}));
          return label;
        }
        function revealScoreMeasure(measure){
          CartoGraphABC.highlightChord(Number(measure),[]);
          showActiveMeasureLabel(measure);
          const elements=Array.from(document.querySelectorAll('.cartograph-abc-selected-measure'));
          if(!elements.length)return null;
          const rect=elements.reduce((result,element)=>{
            const current=element.getBoundingClientRect();
            return {top:Math.min(result.top,current.top),bottom:Math.max(result.bottom,current.bottom)};
          },{top:Number.POSITIVE_INFINITY,bottom:Number.NEGATIVE_INFINITY});
          return {top:rect.top+window.scrollY,height:Math.max(1,rect.bottom-rect.top)};
        }
        cartoGraphABCReady.then(()=>{new ResizeObserver(reportHeight).observe(document.body);document.addEventListener('pointerdown',()=>webkit.messageHandlers.abcNotationInteraction.postMessage(true),{capture:true});reportHeight();webkit.messageHandlers.abcNotationReady.postMessage({measures:CartoGraphABC.measureCount()})})</script>
        """
        return ABCNotationDocument.html(source: source, bridgeScript: bridge)
    }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        var height: Binding<CGFloat>
        var loadedABC: String?
        let controller: ScoreController

        init(height: Binding<CGFloat>, controller: ScoreController) {
            self.height = height
            self.controller = controller
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.name {
            case "abcNotationHeight":
                guard let value = message.body as? NSNumber else { return report("Ungültige Vorschauhöhe.") }
                height.wrappedValue = CGFloat(truncating: value)
            case "abcNotationReady":
                guard let body = message.body as? [String: Any], let count = body["measures"] as? NSNumber else { return report("Ungültiger Bereitschaftsstatus.") }
                controller.ready(measures: count.intValue)
            case "abcNotationInteraction": controller.interact()
            case "abcNotationSelection": receiveSelection(message.body)
            case "abcNotationTranspose": receiveTranspose(message.body)
            case "abcNotationMIDIExport": exportMIDI(message.body)
            default: report("Unbekannte Partiturmeldung: \(message.name)")
            }
        }

        private func receiveSelection(_ body: Any) {
            if let value = body as? [String: Any], let rawSelections = value["selections"] as? [Any] {
                let selections = rawSelections.compactMap(Self.selection(from:))
                guard selections.count == rawSelections.count, !selections.isEmpty else { return report("Ungültige Mehrfachauswahl aus der Partitur.") }
                controller.selectNotes(selections)
                return
            }
            guard let selection = Self.selection(from: body) else { return report("Ungültige Notenauswahl aus der Partitur.") }
            controller.selectNote(selection)
        }

        private func receiveTranspose(_ body: Any) {
            guard let value = body as? [String: Any], let delta = value["delta"] as? NSNumber else { return report("Ungültige Notentransposition aus der Partitur.") }
            if let rawSelections = value["selections"] as? [Any] {
                let selections = rawSelections.compactMap(Self.selection(from:))
                guard selections.count == rawSelections.count, !selections.isEmpty else { return report("Ungültige gemeinsame Notentransposition aus der Partitur.") }
                controller.requestTranspose(selections, semitones: delta.intValue)
                return
            }
            guard let selection = Self.selection(from: value["selection"] as Any) else { return report("Ungültige Notentransposition aus der Partitur.") }
            controller.requestTranspose(selection, semitones: delta.intValue)
        }

        private static func selection(from body: Any) -> ScoreNoteSelection? {
            guard let value = body as? [String: Any],
                  let track = value["trackIndex"] as? NSNumber, let note = value["noteIndex"] as? NSNumber,
                  let measure = value["measure"] as? NSNumber, let pitch = value["pitchIndex"] as? NSNumber,
                  let midi = value["midi"] as? NSNumber else { return nil }
            return ScoreNoteSelection(trackIndex: track.intValue, noteIndex: note.intValue, measure: measure.intValue, pitchIndex: pitch.intValue, midi: midi.intValue)
        }

        private func exportMIDI(_ body: Any) {
            guard let value = body as? [String: Any], let name = value["filename"] as? String,
                  let numbers = value["bytes"] as? [NSNumber], !numbers.isEmpty else { return report("MIDI-Export enthält keine Daten.") }
            let panel = NSSavePanel()
            panel.nameFieldStringValue = name
            panel.allowedContentTypes = [UTType.midi]
            panel.begin { response in
                guard response == .OK, let url = panel.url else { return }
                do { try Data(numbers.map { UInt8(clamping: $0.intValue) }).write(to: url, options: .atomic) }
                catch { self.report("MIDI-Datei konnte nicht gespeichert werden: \(error.localizedDescription)") }
            }
        }

        private func report(_ text: String) {
            controller.report(text)
        }
    }
}
