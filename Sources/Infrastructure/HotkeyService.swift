import AppKit
import KeyboardShortcuts

// MARK: - Shortcut Names

extension KeyboardShortcuts.Name {
    /// Opens the main clipboard history + snippets menu (legacy: "ClipMenu", Cmd+Shift+V).
    static let openClipMenu = Self("openClipMenu",
                                   default: .init(.v, modifiers: [.command, .shift]))
    /// Opens the history-only view (legacy: "HistoryMenu", Cmd+Ctrl+V).
    static let openHistory  = Self("openHistory",
                                   default: .init(.v, modifiers: [.command, .control]))
    /// Opens the snippets view (legacy: "SnippetsMenu", Cmd+Shift+B).
    static let openSnippets = Self("openSnippets",
                                   default: .init(.b, modifiers: [.command, .shift]))
}

// MARK: - HotkeyService

/// Registers and unregisters global keyboard shortcuts using the
/// `KeyboardShortcuts` package.
///
/// Default key combos mirror `legacy/Source/AppController.m
/// +_defaultHotKeyCombos` (keyCode 9 = V, 11 = B; modifiers 768 = ⌘⇧,
/// 4352 = ⌘⌃).
final class HotkeyService {

    func register() {
        // All three shortcuts open the MenuBarExtra menu by simulating a click
        // on its status item button. In the SwiftUI .menu style, the status item
        // is the only one registered with NSStatusBar.
        KeyboardShortcuts.onKeyUp(for: .openClipMenu) { HotkeyService.activateMenu() }
        KeyboardShortcuts.onKeyUp(for: .openHistory)  { HotkeyService.activateMenu() }
        KeyboardShortcuts.onKeyUp(for: .openSnippets) { HotkeyService.activateMenu() }
    }

    func unregister() {
        KeyboardShortcuts.removeAllHandlers()
    }

    // MARK: - Private

    /// Programmatically opens the MenuBarExtra by performing a click on its
    /// status-bar button. `NSStatusBar` does not expose a public `statusItems`
    /// array, so we access it via Objective-C KVC — a stable, widely-used
    /// pattern on macOS 10.x–14.
    private static func activateMenu() {
        guard let items = NSStatusBar.system.value(forKey: "statusItems") as? [NSStatusItem],
              let button = items.first?.button else { return }
        button.performClick(nil)
    }
}
