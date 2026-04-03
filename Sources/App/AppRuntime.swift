import SwiftData

final class AppRuntime {
    static let shared = AppRuntime()

    let settings = ClipMenuSettings()
    let clipsService: ClipsService
    let snippetService = SnippetService()
    let actionService = ActionService()
    let loginItemService = LoginItemService()
    let hotkeyService = HotkeyService()

    var modelContainer: ModelContainer?

    private init() {
        clipsService = ClipsService(settings: settings)
    }
}
