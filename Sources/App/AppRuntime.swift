import AppKit
import SwiftData
import SwiftUI

final class AppRuntime {
    static let shared = AppRuntime()

    let settings = ClipMenuSettings()
    let clipsService: ClipsService
    let snippetService = SnippetService()
    let actionService = ActionService()
    let loginItemService = LoginItemService()
    let hotkeyService = HotkeyService()
    private let preferencesWindowController = PreferencesWindowController()

    var modelContainer: ModelContainer?

    private init() {
        clipsService = ClipsService(settings: settings)
    }

    @MainActor
    func showPreferences() {
        preferencesWindowController.show(
            settings: settings,
            loginItemService: loginItemService,
            modelContainer: modelContainer
        )
    }
}

@MainActor
private final class PreferencesWindowController: NSWindowController, NSWindowDelegate {
    func show(
        settings: ClipMenuSettings,
        loginItemService: LoginItemService,
        modelContainer: ModelContainer?
    ) {
        let window = window ?? makeWindow()
        let rootView = makePreferencesView(
            settings: settings,
            loginItemService: loginItemService,
            modelContainer: modelContainer
        )
        window.contentViewController = NSHostingController(rootView: rootView)

        NSRunningApplication.current.activate(options: [.activateAllWindows])
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    func windowWillClose(_ notification: Notification) {
        window?.contentViewController = nil
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 520),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Preferences"
        window.setFrameAutosaveName("Preferences")
        window.isReleasedWhenClosed = false
        window.delegate = self
        self.window = window
        return window
    }

    private func makePreferencesView(
        settings: ClipMenuSettings,
        loginItemService: LoginItemService,
        modelContainer: ModelContainer?
    ) -> AnyView {
        let rootView = PreferencesView()
            .environment(settings)
            .environment(\.loginItemService, loginItemService)

        if let modelContainer {
            return AnyView(rootView.modelContainer(modelContainer))
        }

        return AnyView(rootView)
    }
}
