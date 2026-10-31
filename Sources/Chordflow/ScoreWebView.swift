import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

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
    private weak var webView: WKWebView?

    func attach(_ webView: WKWebView) {
        self.webView = webView
        isReady = false
        errorMessage = nil
    }

    func ready(measures: Int) {
        measureCount = max(0, measures)
        isReady = true
        errorMessage = nil
    }

    func interact() { interactionCount &+= 1 }

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
}

struct ScoreWebView: NSViewRepresentable {
    let abc: String
    @Binding var height: CGFloat
    let controller: ScoreController

    func makeCoordinator() -> Coordinator { Coordinator(height: $height, controller: controller) }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        for name in ["abcNotationHeight", "abcNotationReady", "abcNotationMIDIExport", "abcNotationInteraction"] {
            configuration.userContentController.add(context.coordinator, name: name)
        }
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.setValue(false, forKey: "drawsBackground")
        controller.attach(view)
        return view
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.height = $height
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
        .cartograph-abc--compact{width:320px!important;max-width:100%;height:250px;display:block!important;padding:18px;overflow:hidden;position:relative}
        .cartograph-abc--compact svg{top:58px!important;transform:none}
        .cartograph-abc-compact-header{position:absolute;z-index:1;top:14px;left:18px;right:18px;display:flex;flex-direction:column;align-items:center;line-height:1.05;pointer-events:none}
        .cartograph-abc-compact-symbol{font:700 26px -apple-system,BlinkMacSystemFont,sans-serif}.cartograph-abc-compact-title{margin-top:3px;color:color-mix(in srgb,currentColor 68%,transparent);font-size:12px}
        .cartograph-abc svg{display:block;max-width:100%;height:auto}.abcjs-note,.abcjs-rest{cursor:pointer}
        .cartograph-abc-playing,.cartograph-abc-playing *{fill:#ff3b30!important;stroke:#ff3b30!important}.cartograph-abc-midi-live,.cartograph-abc-midi-live *{fill:#0a84ff!important;stroke:#0a84ff!important}
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
            case "abcNotationMIDIExport": exportMIDI(message.body)
            default: report("Unbekannte Partiturmeldung: \(message.name)")
            }
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
