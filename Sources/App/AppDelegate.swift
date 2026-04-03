import AppKit

/// Lifecycle hooks that must live in an NSApplicationDelegate rather than the
/// SwiftUI App struct (e.g. applicationWillTerminate, Sparkle delegate).
final class AppDelegate: NSObject, NSApplicationDelegate {

    // TODO: Phase 1 — wire ClipsService start/stop, HotkeyService registration,
    //       LoginItemService, and legacy data migration trigger.

    func applicationDidFinishLaunching(_ notification: Notification) {
        // TODO: Phase 1 — request Accessibility permission for CGEvent paste.
    }

    func applicationWillTerminate(_ notification: Notification) {
        // TODO: Phase 1 — flush in-flight clipboard writes.
    }
}
