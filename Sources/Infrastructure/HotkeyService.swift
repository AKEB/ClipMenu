import Foundation
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Opens the main clipboard history menu.
    static let openMainMenu     = Self("openMainMenu")
    /// Opens the history-only submenu.
    static let openHistoryMenu  = Self("openHistoryMenu")
    /// Opens the snippets submenu.
    static let openSnippetMenu  = Self("openSnippetMenu")
}

/// Registers and unregisters global keyboard shortcuts using the
/// `KeyboardShortcuts` package.
///
/// Default key combinations are defined in `legacy/Source/constants.h`
/// (`kDefaultMainMenuKeyCode`, etc.).  Replicate those defaults when
/// implementing Phase 3.
final class HotkeyService {

    // TODO: Phase 3 — Call KeyboardShortcuts.onKeyDown for each Name above,
    //       wiring into the appropriate service / UI action.

    func register() {
        // TODO: Phase 3
    }

    func unregister() {
        KeyboardShortcuts.removeAllHandlers()
    }
}
