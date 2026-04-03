import SwiftData
import AppKit
import Combine

/// Manages the clipboard history: monitors NSPasteboard, deduplicates entries,
/// enforces the max-history limit, and writes ClipEntry records to SwiftData.
///
/// Reference: `legacy/Source/ClipsController.{h,m}` and `Clip.{h,m}`.
actor ClipsService {

    private let monitor    = ClipboardMonitor()
    private let exclusion  = AppExclusionService()
    private var context:     ModelContext?

    // TODO: Phase 1 — inject ModelContext, subscribe to monitor.pasteboardChanged,
    //       read pasteboard types matching legacy/Source/ClipsController.m,
    //       deduplicate via ClipEntry.contentHash, enforce maxHistorySize setting,
    //       persist via context.insert / context.save.

    func start(context: ModelContext) {
        self.context = context
        monitor.start()
    }

    func stop() {
        monitor.stop()
    }

    /// Copies the given entry back onto the system pasteboard and triggers paste.
    func select(_ entry: ClipEntry) async {
        // TODO: Phase 1 — write entry data to NSPasteboard.general,
        //       update entry.lastUsedAt, then call PasteService.paste().
    }
}
