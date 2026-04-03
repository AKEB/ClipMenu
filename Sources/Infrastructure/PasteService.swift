import CoreGraphics
import AppKit

/// Synthesises a Cmd+V key event to paste the current pasteboard contents
/// into the frontmost application.
///
/// Requires Accessibility permission (`AXIsProcessTrusted()`).  The legacy
/// implementation lives in `legacy/Source/AppController.m -pasteFromClipboard`.
actor PasteService {

    // TODO: Phase 1 — implement CGEvent Cmd+V synthesis via kCGSessionEventTap.
    //       Request Accessibility permission on first call if not already granted.

    func paste() async {
        // TODO: Phase 1
    }
}
