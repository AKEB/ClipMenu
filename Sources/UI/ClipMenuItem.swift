import SwiftUI

/// A single row in the clipboard history menu.
///
/// TODO: Phase 2 — display type icon + inline text preview.
///       Icon logic mirrors legacy/Source/MenuController.m -imageForClip:.
struct ClipMenuItem: View {

    let entry: ClipEntry

    var body: some View {
        // TODO: Phase 2
        Text(entry.stringValue ?? "(binary)")
    }
}
