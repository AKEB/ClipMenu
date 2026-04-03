import AppKit
import Combine

/// Publishes `NSPasteboard` change events as a Combine stream.
///
/// Uses a timer-based polling approach (matching legacy behaviour) rather than
/// KVO, because NSPasteboard does not expose a reliable change notification API.
/// Check `legacy/Source/ClipsController.m` for the polling interval and the
/// change-count comparison logic before changing this implementation.
final class ClipboardMonitor {

    // TODO: Phase 1 — implement NSPasteboard polling with a Combine Timer publisher.
    //       Emit the current pasteboard only when changeCount advances.
    //       Interval: replicate legacy value from ClipsController.m.

    let pasteboardChanged = PassthroughSubject<NSPasteboard, Never>()

    private var cancellables = Set<AnyCancellable>()
    private var lastChangeCount: Int = 0

    func start() {
        // TODO: Phase 1 — start polling timer.
    }

    func stop() {
        cancellables.removeAll()
    }
}
