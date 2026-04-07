import AppKit

/// Lifecycle hooks that must live in an NSApplicationDelegate rather than the
/// SwiftUI App struct (e.g. applicationWillTerminate, Sparkle delegate).
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let runtime = AppRuntime.shared
    private var statusItemController: StatusItemController?

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure persisted settings are hydrated and normalized before services read them.
        runtime.settings.reload()
        let statusItemController = StatusItemController(runtime: runtime)
        statusItemController.install(runtime: runtime)
        self.statusItemController = statusItemController

        // Register global hotkeys immediately. This should not depend on
        // SwiftData container readiness.
        runtime.hotkeyService.register()

        do {
            try runtime.loginItemService.setEnabled(runtime.settings.launchAtLogin)
        } catch {
            // Keep startup resilient when login item registration fails.
        }

        startDataServicesWhenReady(retryCount: 10)
    }

    @MainActor
    private func startDataServicesWhenReady(retryCount: Int) {
        guard let modelContext = runtime.modelContainer?.mainContext else {
            guard retryCount > 0 else { return }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 100_000_000)
                startDataServicesWhenReady(retryCount: retryCount - 1)
            }
            return
        }

        if LegacyMigration.isNeeded {
            LegacyMigration.run(in: modelContext)
        }

        Task {
            runtime.clipsService.start(context: modelContext)
            await runtime.snippetService.start(context: modelContext)
            await runtime.actionService.start(context: modelContext)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        runtime.hotkeyService.unregister()
        Task {
            runtime.clipsService.stop()
        }
    }
}

@MainActor
private final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private weak var runtime: AppRuntime?
    private let menu = NSMenu(title: "ClipMenu")

    init(runtime: AppRuntime) {
        self.runtime = runtime
        super.init()
        menu.delegate = self
        statusItem.menu = menu
    }

    func install(runtime: AppRuntime) {
        self.runtime = runtime

        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "clipboard.fill", accessibilityDescription: "ClipMenu")
        button.image?.isTemplate = true
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let runtime, let freshMenu = runtime.hotkeyService.makeStatusMenu() else { return }

        while !freshMenu.items.isEmpty {
            let item = freshMenu.items[0]
            freshMenu.removeItem(item)
            menu.addItem(item)
        }
    }
}
