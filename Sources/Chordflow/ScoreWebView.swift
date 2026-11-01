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
    @Published private(set) var selectedNote: ScoreNoteSelection?
    var transposeHandler: ((ScoreNoteSelection, Int) -> Void)?
    var selectionHandler: ((ScoreNoteSelection) -> Void)?
    private weak var webView: WKWebView?
    private var highlightedChord: (measure: Int, pitches: [Int])?
    private var selectedPitch: Int?
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
        if selectedPitch != nil { applySelectedPitch() } else { applySelectedNote() }
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

    func selectNote(_ selection: ScoreNoteSelection) { selectedNote = selection; selectedPitch = nil; selectionHandler?(selection) }

    func clearSelectedNote() { selectedNote = nil; selectedPitch = nil }

    func requestTranspose(_ selection: ScoreNoteSelection, semitones: Int) {
        guard abs(semitones) == 1 else { report("Ungültiger Transpositionsschritt: \(semitones)"); return }
        transposeHandler?(selection, semitones)
    }

    func updateSelectedNote(_ selection: ScoreNoteSelection) { selectedNote = selection; applySelectedNote() }

    func updateSelectedPitch(_ midi: Int) {
        selectedNote = nil
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

    func clearHighlight() {
        highlightedChord = nil
        guard let webView, isReady else { return }
        webView.callAsyncJavaScript("return CartoGraphABC.clearSelection()", arguments: [:], in: nil, in: .page) { _ in }
    }

    private func applyHighlight() {
        guard let webView, isReady, let highlightedChord else { return }
        webView.callAsyncJavaScript(
            "return CartoGraphABC.highlightChord(measure, pitches)",
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
        guard let webView, isReady, let selectedNote else { return }
        webView.callAsyncJavaScript(
            "return CartoGraphABC.showEditedSelection(selection)",
            arguments: ["selection": ["trackIndex": selectedNote.trackIndex, "noteIndex": selectedNote.noteIndex, "measure": selectedNote.measure, "pitchIndex": selectedNote.pitchIndex, "midi": selectedNote.midi]],
            in: nil,
            in: .page
        ) { [weak self] result in
            DispatchQueue.main.async {
                switch result { case .success: self?.errorMessage = nil; case .failure(let error): self?.report("Notenauswahl fehlgeschlagen: \(error.localizedDescription)") }
            }
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

    private static var scoreResourceURL: URL? {
        if let installed = Bundle.main.resourceURL,
           FileManager.default.fileExists(atPath: installed.appending(path: "cartograph-abc.js").path) {
            return installed
        }
        return Bundle.module.resourceURL
    }

    private static func html(_ source: String) -> String {
        let encoded = source
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        return """
        <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>
        *{box-sizing:border-box}html,body{margin:0;background:transparent;color:CanvasText;font-family:-apple-system;overflow:hidden}body{padding:8px}
        .cartograph-abc{width:100%;padding:12px;border:1px solid color-mix(in srgb,currentColor 14%,transparent);border-radius:10px;background:color-mix(in srgb,Canvas 96%,CanvasText 4%)}
        .cartograph-abc--compact{width:320px!important;max-width:100%;height:205px;display:block!important;padding:18px;overflow:hidden;position:relative}
        .cartograph-abc--compact svg{top:48px!important;transform:none}
        .cartograph-abc-compact-header{position:absolute;z-index:1;top:14px;left:18px;right:18px;display:flex;flex-direction:column;align-items:center;line-height:1.05;pointer-events:none}
        .cartograph-abc-compact-symbol{font:700 26px -apple-system,BlinkMacSystemFont,sans-serif}.cartograph-abc-compact-title{margin-top:3px;color:color-mix(in srgb,currentColor 68%,transparent);font-size:12px}
        .cartograph-abc svg{display:block;max-width:100%;height:auto}.abcjs-note,.abcjs-rest{cursor:pointer}
        .cartograph-abc-chord-standard,.cartograph-abc-chord-standard *{fill:#0a84ff!important;stroke:#0a84ff!important}.cartograph-abc-chord-inversion,.cartograph-abc-chord-inversion *{fill:#bf5af2!important;stroke:#bf5af2!important}.cartograph-abc-chord-altered,.cartograph-abc-chord-altered *{fill:#ff9f0a!important;stroke:#ff9f0a!important}.cartograph-abc-selected-measure,.cartograph-abc-selected-measure *{fill:#ff9f0a!important;stroke:#ff9f0a!important}.cartograph-abc-playing,.cartograph-abc-playing *,.cartograph-abc-selected-chord,.cartograph-abc-selected-chord *{fill:#ff3b30!important;stroke:#ff3b30!important}.cartograph-abc-midi-live,.cartograph-abc-midi-live *{fill:#0a84ff!important;stroke:#0a84ff!important}.cartograph-abc-edit-selected{filter:drop-shadow(0 0 1px #fff) drop-shadow(0 0 3px #007aff)}.cartograph-abc-edit-selected,.cartograph-abc-edit-selected *{fill:var(--cartograph-edit-color,#0a84ff)!important;stroke:var(--cartograph-edit-color,#0a84ff)!important}
        .cartograph-abc--error{color:#b42318}.cartograph-abc-guide--middle{stroke:#af52de;stroke-width:2;opacity:.55}.cartograph-abc-guide--g{stroke:#007aff;stroke-width:2.4;opacity:.85}.cartograph-abc-guide-label{font:700 9px -apple-system;text-anchor:end;paint-order:stroke fill;stroke:Canvas;stroke-width:3px}.cartograph-abc-guide-label--middle{fill:#af52de}.cartograph-abc-guide-label--g{fill:#007aff}
        </style><script src="abcjs-basic-6.7.2.min.js"></script></head><body>
        <div class="cartograph-abc" data-cartograph-abc data-source="\(encoded)"></div><script src="cartograph-abc.js"></script>
        <script>function reportHeight(){requestAnimationFrame(()=>webkit.messageHandlers.abcNotationHeight.postMessage(Math.ceil(document.body.scrollHeight)))}
        cartoGraphABCReady.then(()=>{new ResizeObserver(reportHeight).observe(document.body);document.addEventListener('pointerdown',()=>webkit.messageHandlers.abcNotationInteraction.postMessage(true),{capture:true});reportHeight();webkit.messageHandlers.abcNotationReady.postMessage({measures:CartoGraphABC.measureCount()})})</script>
        </body></html>
        """
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
            guard let selection = Self.selection(from: body) else { return report("Ungültige Notenauswahl aus der Partitur.") }
            controller.selectNote(selection)
        }

        private func receiveTranspose(_ body: Any) {
            guard let value = body as? [String: Any], let selection = Self.selection(from: value["selection"] as Any), let delta = value["delta"] as? NSNumber else { return report("Ungültige Notentransposition aus der Partitur.") }
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
