import CoreGraphics
import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Synthesises a Cmd+V key event to paste the current pasteboard contents
/// into the frontmost application.
///
/// Requires Accessibility permission (`AXIsProcessTrusted()`).  The legacy
/// implementation lives in `legacy/Source/AppController.m -pasteFromClipboard`.
actor PasteService {
    private var cachedVKeyCode: CGKeyCode?

    init() {
        NotificationCenter.default.addObserver(
            forName: NSTextInputContext.keyboardSelectionDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { await self?.invalidateCachedKeyCode() }
        }
    }

    func paste() async {
        guard isAccessibilityTrusted() else { return }
        guard let keyCode = vKeyCode() else { return }
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)

        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    private func isAccessibilityTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    private func invalidateCachedKeyCode() {
        cachedVKeyCode = nil
    }

    private func vKeyCode() -> CGKeyCode? {
        if let cachedVKeyCode {
            return cachedVKeyCode
        }

        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else {
            cachedVKeyCode = 9
            return cachedVKeyCode
        }

        let layout = unsafeBitCast(layoutData, to: CFData.self)
        guard let bytes = CFDataGetBytePtr(layout) else {
            cachedVKeyCode = 9
            return cachedVKeyCode
        }

        let keyboardLayout = UnsafePointer<UCKeyboardLayout>(OpaquePointer(bytes))

        for keyCode in 0..<128 {
            var deadKeyState: UInt32 = 0
            var chars = [UniChar](repeating: 0, count: 4)
            var length = 0

            let status = UCKeyTranslate(
                keyboardLayout,
                UInt16(keyCode),
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                4,
                &length,
                &chars
            )

            guard status == noErr, length > 0 else { continue }
            let mapped = String(utf16CodeUnits: chars, count: Int(length))
            if mapped.caseInsensitiveCompare("v") == .orderedSame {
                cachedVKeyCode = CGKeyCode(keyCode)
                return cachedVKeyCode
            }
        }

        cachedVKeyCode = 9
        return cachedVKeyCode
    }
}
