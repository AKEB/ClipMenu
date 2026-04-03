import SwiftUI
import SwiftData

/// Root content of the status-bar MenuBarExtra.
///
/// Mirrors the menu hierarchy from `legacy/Source/MenuController.m -buildClipMenu`.
struct ClipMenuView: View {
    private let runtime = AppRuntime.shared

    @Query(sort: \ClipEntry.lastUsedAt, order: .reverse) private var clips: [ClipEntry]
    @Query(sort: \SnippetFolder.sortIndex) private var folders: [SnippetFolder]

    @Environment(ClipMenuSettings.self) private var settings
    @Environment(\.clipsService) private var clipsService
    @Environment(\.snippetService) private var snippetService

    var body: some View {
        // Snippets above clips
        if settings.positionOfSnippets == 0 {
            SnippetSection(folders: folders.filter(\.isEnabled))
            Divider()
        }

        // Clip history rows
        clipsSection

        // Snippets below clips (default)
        if settings.positionOfSnippets == 1 {
            Divider()
            SnippetSection(folders: folders.filter(\.isEnabled))
        }

        // Clear History
        if settings.showClearHistoryItem {
            Divider()
            Button("Clear History") { clearHistory() }
        }

        Divider()

        Button("Preferences…") { runtime.showPreferences() }
        Button("Quit ClipMenu") { NSApp.terminate(nil) }
    }

    // MARK: - Clips section

    // Computed outside @ViewBuilder so SwiftUI's dependency tracking reliably
    // sees the @Query `clips` property on every render.

    private var inlineClips: [ClipEntry] {
        let n = settings.numberOfItemsInline
        // Legacy: n == 0 → all items go into folder submenus (mirrors ObjC behaviour).
        return n == 0 ? [] : Array(clips.prefix(n))
    }

    /// Groups of clips that appear inside folder submenus.
    private var folderGroups: [[ClipEntry]] {
        let n = settings.numberOfItemsInline
        let groupSize = max(settings.numberOfItemsInsideFolder, 1)
        let remaining = n == 0 ? clips : Array(clips.dropFirst(n))
        guard !remaining.isEmpty else { return [] }
        return stride(from: 0, to: remaining.count, by: groupSize).map {
            Array(remaining[$0..<min($0 + groupSize, remaining.count)])
        }
    }

    @ViewBuilder
    private var clipsSection: some View {
        let inlineCount = settings.numberOfItemsInline
        let groupSize   = max(settings.numberOfItemsInsideFolder, 1)

        ForEach(Array(inlineClips.enumerated()), id: \.element.id) { index, clip in
            ClipMenuItem(entry: clip, listNumber: listNumber(for: index))
        }

        ForEach(Array(folderGroups.enumerated()), id: \.offset) { groupIndex, group in
            let start = inlineCount + groupIndex * groupSize + 1
            let end   = start + group.count - 1
            Menu("\(start) – \(end)") {
                ForEach(Array(group.enumerated()), id: \.element.id) { idx, clip in
                    ClipMenuItem(
                        entry: clip,
                        listNumber: listNumber(for: inlineCount + groupIndex * groupSize + idx)
                    )
                }
            }
        }
    }

    // MARK: - Helpers

    /// Replicates the numbering logic from legacy MenuController (starting at 0 or 1, wrapping at 10).
    private func listNumber(for index: Int) -> Int {
        if settings.numberingStartsAtZero {
            return index % 10
        } else {
            let n = index + 1
            return n > 10 ? n % 10 : n
        }
    }

    private func clearHistory() {
        if settings.showAlertBeforeClearHistory {
            let alert = NSAlert()
            alert.messageText = "Clear History"
            alert.informativeText = "Are you sure you want to clear all clipboard history?"
            alert.addButton(withTitle: "Clear")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        Task { try? await clipsService.clearAll() }
    }
}

// MARK: - Preview

#Preview {
    ClipMenuView()
        .environment(ClipMenuSettings())
        .environment(\.clipsService, ClipsService(settings: ClipMenuSettings()))
        .environment(\.snippetService, SnippetService())
        .modelContainer(for: [ClipEntry.self, SnippetFolder.self, Snippet.self, ActionNode.self],
                        inMemory: true)
}
