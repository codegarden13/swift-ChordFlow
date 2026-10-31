import SwiftUI

@main
struct ChordflowApp: App {
    @StateObject private var library = ScoreLibrary()

    var body: some Scene {
        WindowGroup { ContentView(library: library) }
            .commands {
                CommandGroup(replacing: .newItem) {
                    Button("Neue Partitur") { library.addScore() }.keyboardShortcut("n")
                }
                AppHelpCommands()
            }

        Window("App-Hilfe", id: "app-help") {
            AppHelpView(repositoryName: "swift-Chordflow", topics: [
                .init(id: "start", title: "Mit Chordflow beginnen"),
                .init(id: "abc-und-wiedergabe", title: "Partituren und Wiedergabe"),
                .init(id: "musiktheorie", title: "Akkorde und Musiktheorie"),
                .init(id: "midi-und-dateien", title: "MIDI und Speicherung"),
            ])
        }
    }
}
