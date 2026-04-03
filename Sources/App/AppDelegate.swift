import AppKit

/// Lifecycle hooks that must live in an NSApplicationDelegate rather than the
/// SwiftUI App struct (e.g. applicationWillTerminate, Sparkle delegate).
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let runtime = AppRuntime.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure persisted settings are hydrated and normalized before services read them.
        runtime.settings.reload()

        guard let modelContext = runtime.modelContainer?.mainContext else { return }

        if LegacyMigration.isNeeded {
            LegacyMigration.run(in: modelContext)
        }

        Task {
            await runtime.clipsService.start(context: modelContext)
            await runtime.snippetService.start(context: modelContext)
            await runtime.actionService.start(context: modelContext)
        }

        runtime.hotkeyService.register()

        do {
            try runtime.loginItemService.setEnabled(runtime.settings.launchAtLogin)
        } catch {
            // Keep startup resilient when login item registration fails.
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        runtime.hotkeyService.unregister()
        Task {
            await runtime.clipsService.stop()
        }
    }
}
