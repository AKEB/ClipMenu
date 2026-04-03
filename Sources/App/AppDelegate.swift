import AppKit
import ApplicationServices

/// Lifecycle hooks that must live in an NSApplicationDelegate rather than the
/// SwiftUI App struct (e.g. applicationWillTerminate, Sparkle delegate).
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let runtime = AppRuntime.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)

        guard let modelContext = runtime.modelContainer?.mainContext else { return }

        if LegacyMigration.isNeeded {
            LegacyMigration.run(in: modelContext)
        }

        Task {
            await runtime.clipsService.start(context: modelContext)
            await runtime.snippetService.start(context: modelContext)
            await runtime.actionService.start(context: modelContext)
        }

        do {
            try runtime.loginItemService.setEnabled(runtime.settings.launchAtLogin)
        } catch {
            // Keep startup resilient when login item registration fails.
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        Task {
            await runtime.clipsService.stop()
        }
    }
}
