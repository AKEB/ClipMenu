import AppKit
import KeyboardShortcuts
import Foundation
import SwiftUI

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
    private let fallbackPanel = HotkeyMenuPanelController()

    func register() {
        ensureDefaultShortcutsIfMissing()

        // Trigger on key-up to avoid interacting with the menu while modifier
        // keys are still held down.
        KeyboardShortcuts.onKeyUp(for: .openClipMenu) { [weak self] in self?.presentFromHotkey() }
        KeyboardShortcuts.onKeyUp(for: .openHistory)  { [weak self] in self?.presentFromHotkey() }
        KeyboardShortcuts.onKeyUp(for: .openSnippets) { [weak self] in self?.presentFromHotkey() }
    }

    func unregister() {
        KeyboardShortcuts.removeAllHandlers()
    }

    // MARK: - Private

    private func ensureDefaultShortcutsIfMissing() {
        let names: [KeyboardShortcuts.Name] = [.openClipMenu, .openHistory, .openSnippets]

        for name in names {
            // KeyboardShortcuts can persist disabled shortcuts as `nil`.
            // Restore the built-in default when no active shortcut exists.
            if KeyboardShortcuts.getShortcut(for: name) == nil,
               let fallback = name.defaultShortcut {
                KeyboardShortcuts.setShortcut(fallback, for: name)
            }
        }
    }

    private func presentFromHotkey() {
        DispatchQueue.main.async {
            // Defer to the next runloop turn so the global shortcut event
            // finishes before we ask MenuBarExtra to open.
            self.activateMenu(retryCount: 3) { shown in
                guard !shown else { return }
                self.fallbackPanel.show(using: AppRuntime.shared)
            }
        }
    }

    /// Programmatically opens the MenuBarExtra by performing a click on its
    /// status-bar button. `NSStatusBar` does not expose a public `statusItems`
    /// array, so we access it via Objective-C KVC — a stable, widely-used
    /// pattern on macOS 10.x–14.
    private func activateMenu(retryCount: Int, completion: @escaping (Bool) -> Void) {
        guard let button = Self.statusItemButton() else {
            guard retryCount > 0 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self.activateMenu(retryCount: retryCount - 1, completion: completion)
            }
            return
        }

        var didOpenAnyMenu = false
        let observer = NotificationCenter.default.addObserver(
            forName: NSMenu.didBeginTrackingNotification,
            object: nil,
            queue: .main
        ) { _ in
            didOpenAnyMenu = true
        }

        button.performClick(nil)

        // Fallback for cases where performClick does not open the menu due to
        // event-ordering differences.
        if let action = button.action {
            NSApp.sendAction(action, to: button.target, from: button)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            NotificationCenter.default.removeObserver(observer)
            completion(didOpenAnyMenu)
        }
    }

    private static func statusItemButton() -> NSStatusBarButton? {
        let statusBar = NSStatusBar.system
        let items = (statusBar.value(forKey: "statusItems") as? [NSStatusItem])
            ?? (statusBar.value(forKey: "_statusItems") as? [NSStatusItem])
            ?? []

        let buttons = items.compactMap(\.button)
        if let menuBarExtraButton = buttons.first(where: {
            String(describing: type(of: $0.target as Any)).contains("MenuBarExtra")
        }) {
            return menuBarExtraButton
        }

        if let actionableButton = buttons.first(where: { $0.action != nil }) {
            return actionableButton
        }

        return buttons.first
    }
}

@MainActor
private final class HotkeyMenuPanelController: NSWindowController, NSWindowDelegate {
    func show(using runtime: AppRuntime) {
        guard let modelContainer = runtime.modelContainer else { return }

        let window = window ?? makeWindow()
        let rootView = ClipMenuView()
            .modelContainer(modelContainer)
            .environment(runtime.settings)
            .environment(\.clipsService, runtime.clipsService)
            .environment(\.snippetService, runtime.snippetService)
            .environment(\.actionService, runtime.actionService)

        window.contentViewController = NSHostingController(rootView: rootView)
        positionWindowNearMouse(window)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowDidResignKey(_ notification: Notification) {
        window?.orderOut(nil)
    }

    private func makeWindow() -> NSWindow {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 560),
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "ClipMenu"
        panel.hidesOnDeactivate = true
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        self.window = panel
        return panel
    }

    private func positionWindowNearMouse(_ window: NSWindow) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main
        let frame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        var origin = NSPoint(x: mouse.x - window.frame.width / 2,
                             y: mouse.y - window.frame.height / 2)
        origin.x = max(frame.minX, min(origin.x, frame.maxX - window.frame.width))
        origin.y = max(frame.minY, min(origin.y, frame.maxY - window.frame.height))
        window.setFrameOrigin(origin)
    }
}
