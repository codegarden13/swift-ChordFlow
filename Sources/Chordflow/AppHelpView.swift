import OSLog
import SwiftUI

struct AppHelpTopic: Identifiable, Hashable {
    let id: String
    let title: String
}

struct AppHelpView: View {
    let repositoryName: String
    let topics: [AppHelpTopic]
    @State private var selectedID: String

    init(repositoryName: String, topics: [AppHelpTopic]) {
        self.repositoryName = repositoryName
        self.topics = topics
        _selectedID = State(initialValue: topics.first?.id ?? "")
    }

    var body: some View {
        NavigationSplitView {
            List(topics, selection: $selectedID) { Text($0.title).tag($0.id) }
                .navigationTitle("App-Hilfe")
        } detail: {
            if let topic = topics.first(where: { $0.id == selectedID }) {
                HelpDocumentView(url: helpDirectory.appending(path: "\(topic.id).md"))
                    .navigationTitle(topic.title)
            }
        }
        .frame(minWidth: 760, minHeight: 520)
    }

    private var helpDirectory: URL {
        if let bundled = Bundle.main.resourceURL?.appending(path: "Help", directoryHint: .isDirectory),
           FileManager.default.fileExists(atPath: bundled.path) {
            return bundled
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "dev-swift/\(repositoryName)/Help", directoryHint: .isDirectory)
    }
}

private struct HelpDocumentView: View {
    private enum LoadResult { case success(String), failure(String) }
    private enum LoadError: LocalizedError {
        case malformedFrontmatter
        case emptyBody

        var errorDescription: String? {
            switch self {
            case .malformedFrontmatter: "Ungültiger oder fehlender YAML-Header"
            case .emptyBody: "Hilfetext ist leer"
            }
        }
    }

    let url: URL

    var body: some View {
        ScrollView {
            switch load() {
            case .success(let markdown):
                Text((try? AttributedString(markdown: markdown)) ?? AttributedString(markdown))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(28)
            case .failure(let message):
                ContentUnavailableView(
                    "Hilfe nicht verfügbar",
                    systemImage: "exclamationmark.triangle",
                    description: Text(message)
                )
                .padding(28)
            }
        }
    }

    private func load() -> LoadResult {
        do {
            let markdown = try String(contentsOf: url, encoding: .utf8)
            guard markdown.hasPrefix("---\n"),
                  let end = markdown.range(
                    of: "\n---\n",
                    range: markdown.index(markdown.startIndex, offsetBy: 4)..<markdown.endIndex
                  ) else {
                throw LoadError.malformedFrontmatter
            }
            let body = String(markdown[end.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { throw LoadError.emptyBody }
            return .success(body)
        } catch {
            let message = "Quelle: \(url.path) · Ursache: \(error.localizedDescription)"
            Logger(subsystem: Bundle.main.bundleIdentifier ?? "Chordflow", category: "help")
                .error("\(message, privacy: .public)")
            return .failure(message)
        }
    }
}

struct AppHelpCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("App-Hilfe") { openWindow(id: "app-help") }
                .keyboardShortcut("?", modifiers: [.command])
        }
    }
}
