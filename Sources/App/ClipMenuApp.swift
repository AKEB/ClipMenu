import SwiftUI
import SwiftData

@main
struct ClipMenuApp: App {

    // TODO: Phase 1 — initialise ModelContainer with all SwiftData models and
    // inject ClipsService, SnippetService, ActionService as environment objects.

    var body: some Scene {
        // TODO: Phase 2 — replace with ClipMenuApp+Scenes.swift scene definitions
        //       (MenuBarExtra + Settings).
        Settings {
            EmptyView()
        }
    }
}
