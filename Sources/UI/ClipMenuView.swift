import SwiftUI
import SwiftData

/// Root content of the status-bar MenuBarExtra.
///
/// Mirrors the menu hierarchy from `legacy/Source/MenuController.m -buildClipMenu`.
struct ClipMenuView: View {

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

        SettingsLink { Text("Preferences…") }
        Button("Quit ClipMenu") { NSApp.terminate(nil) }
    }

    // MARK: - Clips section

    @ViewBuilder
    private var clipsSection: some View {
        let inlineCount = settings.numberOfItemsInline
        let perFolder   = settings.numberOfItemsInsideFolder

        let inlineClips = inlineCount == 0 ? clips : Array(clips.prefix(inlineCount))
        let folderClips = inlineCount == 0 ? [] : Array(clips.dropFirst(inlineCount))

        ForEach(Array(inlineClips.enumerated()), id: \.element.id) { index, clip in
            ClipMenuItem(entry: clip, listNumber: listNumber(for: index))
        }

        if !folderClips.isEmpty {
            let groupSize = max(perFolder, 1)
            let groups = stride(from: 0, to: folderClips.count, by: groupSize).map {
                Array(folderClips[$0..<min($0 + groupSize, folderClips.count)])
            }
            ForEach(Array(groups.enumerated()), id: \.offset) { groupIndex, group in
                let start = inlineCount + groupIndex * groupSize + 1
                let end   = start + group.count - 1
                Menu("\(start)-\(end)") {
                    ForEach(Array(group.enumerated()), id: \.element.id) { idx, clip in
                        ClipMenuItem(
                            entry: clip,
                            listNumber: listNumber(for: inlineCount + groupIndex * groupSize + idx)
                        )
                    }
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

