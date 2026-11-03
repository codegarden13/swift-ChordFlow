import AppHelpKit
import SwiftUI

@main
struct ChordflowApp: App {
    @StateObject private var library = ScoreLibrary()

    var body: some Scene {
        WindowGroup { ContentView(library: library) }
            .windowToolbarStyle(.unified(showsTitle: false))
            .commands {
                CommandGroup(replacing: .newItem) {
                    Button("Neue Partitur") { library.addScore() }.keyboardShortcut("n")
                }
                AppHelpCommands()
            }

        Window("App-Hilfe", id: "app-help") {
            AppHelpView(repositoryName: "swift-ChordFlow")
        }
    }
}
