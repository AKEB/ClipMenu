import SwiftUI
import SwiftData

/// Snippets tab in the Preferences window.
///
/// Provides basic folder/snippet editing so users can manage items shown
/// in the Snippets menu.
struct SnippetsPrefsView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \SnippetFolder.sortIndex) private var folders: [SnippetFolder]

    @State private var selectedFolderID: PersistentIdentifier?
    @State private var selectedSnippetID: PersistentIdentifier?

    private var selectedFolder: SnippetFolder? {
        folders.first { $0.persistentModelID == selectedFolderID }
    }

    private var selectedSnippets: [Snippet] {
        guard let selectedFolder else { return [] }
        return selectedFolder.snippets.sorted { $0.sortIndex < $1.sortIndex }
    }

    private var selectedSnippet: Snippet? {
        selectedSnippets.first { $0.persistentModelID == selectedSnippetID }
    }

    var body: some View {
        HStack(spacing: 12) {
            foldersPane
            snippetsPane
        }
        .padding()
        .onAppear { ensureSelection() }
        .onChange(of: folders.count) { _, _ in ensureSelection() }
        .onChange(of: selectedFolderID) { _, _ in
            guard let selectedFolder else {
                selectedSnippetID = nil
                return
            }
            if !selectedFolder.snippets.contains(where: { $0.persistentModelID == selectedSnippetID }) {
                selectedSnippetID = selectedFolder.snippets.sorted { $0.sortIndex < $1.sortIndex }.first?.persistentModelID
            }
        }
    }

    private var foldersPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Folders")
                .font(.headline)

            List {
                ForEach(folders) { folder in
                    HStack {
                        Image(systemName: "folder")
                        Text(folder.title)
                        Spacer()
                        if !folder.isEnabled {
                            Text("Disabled")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedFolderID = folder.persistentModelID
                    }
                    .listRowBackground(folder.persistentModelID == selectedFolderID ? Color.accentColor.opacity(0.15) : Color.clear)
                }
            }
            .frame(minWidth: 240)

            HStack {
                Button("Add Folder") { addFolder() }
                Button("Remove") { removeSelectedFolder() }
                    .disabled(selectedFolder == nil)
            }

            Toggle("Enable selected folder", isOn: Binding(
                get: { selectedFolder?.isEnabled ?? true },
                set: { newValue in
                    guard let selectedFolder else { return }
                    selectedFolder.isEnabled = newValue
                    persist()
                }
            ))
            .disabled(selectedFolder == nil)

            TextField("Folder name", text: Binding(
                get: { selectedFolder?.title ?? "" },
                set: { newValue in
                    guard let selectedFolder else { return }
                    selectedFolder.title = newValue
                    persist()
                }
            ))
            .disabled(selectedFolder == nil)
        }
    }

    private var snippetsPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Snippets")
                .font(.headline)

            if let selectedFolder {
                List {
                    ForEach(selectedSnippets) { snippet in
                        HStack {
                            Text(snippet.title)
                            Spacer()
                            if !snippet.isEnabled {
                                Text("Disabled")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedSnippetID = snippet.persistentModelID
                        }
                        .listRowBackground(snippet.persistentModelID == selectedSnippetID ? Color.accentColor.opacity(0.15) : Color.clear)
                    }
                }
                .frame(minWidth: 320)

                HStack {
                    Button("Add Snippet") { addSnippet(to: selectedFolder) }
                    Button("Remove") { removeSelectedSnippet() }
                        .disabled(selectedSnippet == nil)
                }

                GroupBox("Editor") {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Title", text: Binding(
                            get: { selectedSnippet?.title ?? "" },
                            set: { newValue in
                                guard let selectedSnippet else { return }
                                selectedSnippet.title = newValue
                                persist()
                            }
                        ))
                        .disabled(selectedSnippet == nil)

                        Toggle("Enabled", isOn: Binding(
                            get: { selectedSnippet?.isEnabled ?? true },
                            set: { newValue in
                                guard let selectedSnippet else { return }
                                selectedSnippet.isEnabled = newValue
                                persist()
                            }
                        ))
                        .disabled(selectedSnippet == nil)

                        TextEditor(text: Binding(
                            get: { selectedSnippet?.content ?? "" },
                            set: { newValue in
                                guard let selectedSnippet else { return }
                                selectedSnippet.content = newValue
                                persist()
                            }
                        ))
                        .frame(minHeight: 180)
                        .disabled(selectedSnippet == nil)
                    }
                }
            } else {
                ContentUnavailableView("No Folder Selected", systemImage: "text.badge.plus", description: Text("Create a folder to start adding snippets."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func addFolder() {
        let nextIndex = (folders.map(\.sortIndex).max() ?? -1) + 1
        let folder = SnippetFolder(title: "New Folder", sortIndex: nextIndex)
        modelContext.insert(folder)
        persist()
        selectedFolderID = folder.persistentModelID
        selectedSnippetID = nil
    }

    private func removeSelectedFolder() {
        guard let selectedFolder else { return }
        modelContext.delete(selectedFolder)
        persist()
        selectedFolderID = nil
        selectedSnippetID = nil
        ensureSelection()
    }

    private func addSnippet(to folder: SnippetFolder) {
        let nextIndex = (folder.snippets.map(\.sortIndex).max() ?? -1) + 1
        let snippet = Snippet(title: "New Snippet", content: "", sortIndex: nextIndex)
        snippet.folder = folder
        folder.snippets.append(snippet)
        modelContext.insert(snippet)
        persist()
        selectedSnippetID = snippet.persistentModelID
    }

    private func removeSelectedSnippet() {
        guard let selectedSnippet else { return }
        modelContext.delete(selectedSnippet)
        persist()
        selectedSnippetID = selectedSnippets.first?.persistentModelID
    }

    private func ensureSelection() {
        if selectedFolder == nil {
            selectedFolderID = folders.first?.persistentModelID
        }

        guard let selectedFolder else {
            selectedSnippetID = nil
            return
        }

        if !selectedFolder.snippets.contains(where: { $0.persistentModelID == selectedSnippetID }) {
            selectedSnippetID = selectedFolder.snippets.sorted { $0.sortIndex < $1.sortIndex }.first?.persistentModelID
        }
    }

    private func persist() {
        try? modelContext.save()
    }
}

// MARK: - Preview

#Preview {
    let folder = SnippetFolder(title: "Templates", sortIndex: 0)
    let snippet = Snippet(title: "Greeting", content: "Hello from ClipMenu!", sortIndex: 0)
    snippet.folder = folder
    folder.snippets = [snippet]

    return SnippetsPrefsView()
        .modelContainer(for: [SnippetFolder.self, Snippet.self], inMemory: true)
}
