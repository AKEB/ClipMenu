import SwiftUI
import SwiftData
import Foundation

/// Actions tab in the Preferences window.
///
/// Covers: enable toggle, modifier-click behaviours, invoke-immediately.
/// Reference: `legacy/Source/PrefsWindowController.{h,m}` Actions tab.
struct ActionsPrefsView: View {

    @Environment(ClipMenuSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext

    @Query(filter: #Predicate<ActionNode> { $0.parent == nil },
           sort: \ActionNode.sortIndex)
    private var rootNodes: [ActionNode]

    @State private var selectedNodeID: PersistentIdentifier?
    @State private var selectedCatalogID: String?
    @State private var rightTab: RightTab = .builtin

    private enum RightTab: String, CaseIterable {
        case builtin = "Built-in"
        case javaScript = "JavaScript"
        case users = "User's"
    }

    private struct AvailableActionItem: Identifiable, Hashable {
        var id: String
        var name: String
        var actionType: String
        var actionName: String?
        var scriptPath: String?
    }

    var body: some View {
        @Bindable var s = settings
        VStack(spacing: 12) {
            Form {
                Section("Action System") {
                    Toggle("Enable actions", isOn: $s.enableAction)
                    Toggle("Invoke action immediately when only one is available",
                           isOn: $s.invokeActionImmediately)
                        .disabled(!settings.enableAction)
                }

                Section("Modified-Click Behaviour") {
                    clickBehaviorPicker("Control+click", binding: $s.controlClickBehavior)
                    clickBehaviorPicker("Shift+click",   binding: $s.shiftClickBehavior)
                    clickBehaviorPicker("Option+click",  binding: $s.optionClickBehavior)
                    clickBehaviorPicker("Command+click", binding: $s.commandClickBehavior)
                }
                .disabled(!settings.enableAction)
            }

            Divider()

            Text("Action Menu")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(alignment: .top, spacing: 12) {
                actionTreePane
                    .frame(minWidth: 280, idealWidth: 360, maxWidth: .infinity)

                actionControlsPane
                    .frame(width: 96)

                actionCatalogPane
                    .frame(minWidth: 220, idealWidth: 280, maxWidth: 320)
            }
            .frame(minHeight: 280)

            HStack(spacing: 8) {
                Text("Name:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Action name", text: Binding(
                    get: { selectedNode?.title ?? "" },
                    set: { newValue in
                        guard let selectedNode else { return }
                        selectedNode.title = newValue
                        persist()
                    }
                ))
                .disabled(selectedNode == nil)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            if selectedNodeID == nil {
                selectedNodeID = rootNodes.first?.persistentModelID
            }
        }
        .onChange(of: rootNodes.count) { _, _ in
            if selectedNode == nil {
                selectedNodeID = rootNodes.first?.persistentModelID
            }
        }
    }

    // MARK: - Helpers

    /// Picker that maps between the stored behavior string and a display label.
    /// Legacy values: "" (no-op), "popUpActionMenu" (show action menu).
    @ViewBuilder
    private func clickBehaviorPicker(_ label: String, binding: Binding<String>) -> some View {
        Picker(label, selection: binding) {
            Text("No action").tag("")
            Text("Show action menu").tag("popUpActionMenu")
        }
        .pickerStyle(.menu)
    }

    private var actionTreePane: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Current actions")
                .font(.subheadline)
                .fontWeight(.medium)

            List {
                OutlineGroup(sortedRoots, children: \.sortedChildrenForUI) { node in
                    HStack(spacing: 8) {
                        Toggle("", isOn: Binding(
                            get: { node.isEnabled },
                            set: { newValue in
                                node.isEnabled = newValue
                                persist()
                            }
                        ))
                        .labelsHidden()
                        .toggleStyle(.checkbox)

                        Image(systemName: node.isLeaf ? "bolt.fill" : "folder.fill")
                            .foregroundStyle(node.isLeaf ? .orange : .accentColor)

                        Text(node.title)
                            .lineLimit(1)

                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                    .background(selectionBackground(for: node))
                    .onTapGesture {
                        selectedNodeID = node.persistentModelID
                    }
                }
            }
            .listStyle(.inset)
        }
    }

    private var actionControlsPane: some View {
        VStack(spacing: 8) {
            Button("<<") {
                addSelectedCatalogAction()
            }
            .disabled(selectedCatalogItem == nil)

            Button("Folder") {
                addFolder()
            }

            Button("Remove") {
                removeSelectedNode()
            }
            .disabled(selectedNode == nil)

            Divider()

            Button("Up") {
                moveSelectedNode(delta: -1)
            }
            .disabled(!canMoveSelectedNode(delta: -1))

            Button("Down") {
                moveSelectedNode(delta: 1)
            }
            .disabled(!canMoveSelectedNode(delta: 1))
        }
        .buttonStyle(.bordered)
        .padding(.top, 28)
    }

    private var actionCatalogPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: $rightTab) {
                ForEach(RightTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)

            List(selection: $selectedCatalogID) {
                ForEach(availableItems) { item in
                    Text(item.name)
                        .tag(item.id)
                }
            }
            .listStyle(.inset)
        }
    }

    private var sortedRoots: [ActionNode] {
        rootNodes.sorted { $0.sortIndex < $1.sortIndex }
    }

    private var selectedNode: ActionNode? {
        guard let selectedNodeID else { return nil }
        return allNodes.first { $0.persistentModelID == selectedNodeID }
    }

    private var allNodes: [ActionNode] {
        flatten(nodes: sortedRoots)
    }

    private var selectedCatalogItem: AvailableActionItem? {
        guard let selectedCatalogID else { return nil }
        return availableItems.first { $0.id == selectedCatalogID }
    }

    private var availableItems: [AvailableActionItem] {
        switch rightTab {
        case .builtin:
            return [
                AvailableActionItem(id: "builtin:pasteAsPlainText", name: "Paste as Plain Text", actionType: "builtin", actionName: "pasteAsPlainText"),
                AvailableActionItem(id: "builtin:pasteAsFilePath", name: "Paste as File Path", actionType: "builtin", actionName: "pasteAsFilePath"),
                AvailableActionItem(id: "builtin:pasteAsHFSFilePath", name: "Paste as HFS File Path", actionType: "builtin", actionName: "pasteAsHFSFilePath"),
                AvailableActionItem(id: "builtin:removeAction", name: "Remove", actionType: "builtin", actionName: "removeAction"),
            ]
        case .javaScript:
            let bundleURL = Bundle.main.resourceURL?.appendingPathComponent("scripts/action")
            return scriptItems(in: bundleURL)
        case .users:
            let userURL = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first?
                .appendingPathComponent("ClipMenu/script/action")
            return scriptItems(in: userURL)
        }
    }

    private func scriptItems(in root: URL?) -> [AvailableActionItem] {
        guard let root else { return [] }
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var items: [AvailableActionItem] = []
        for case let url as URL in enumerator {
            guard url.pathExtension.lowercased() == "js" else { continue }
            let relative = url.path.replacingOccurrences(of: root.path + "/", with: "")
            let display = relative.replacingOccurrences(of: ".js", with: "")
            items.append(AvailableActionItem(
                id: "script:\(url.path)",
                name: display,
                actionType: "javaScript",
                actionName: nil,
                scriptPath: url.path
            ))
        }

        return items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func addSelectedCatalogAction() {
        guard let item = selectedCatalogItem else { return }
        let newNode = ActionNode(title: item.name, isLeaf: true, sortIndex: 0)
        newNode.actionType = item.actionType
        newNode.actionName = item.actionName
        newNode.scriptPath = item.scriptPath
        insert(node: newNode, into: selectedFolderTarget)
        selectedNodeID = newNode.persistentModelID
    }

    private func addFolder() {
        let newFolder = ActionNode(title: "New Folder", isLeaf: false, sortIndex: 0)
        insert(node: newFolder, into: selectedFolderTarget)
        selectedNodeID = newFolder.persistentModelID
    }

    private var selectedFolderTarget: ActionNode? {
        guard let selectedNode else { return nil }
        return selectedNode.isLeaf ? selectedNode.parent : selectedNode
    }

    private func insert(node: ActionNode, into folder: ActionNode?) {
        if let folder {
            node.parent = folder
            node.sortIndex = nextSortIndex(in: folder)
            folder.children.append(node)
        } else {
            node.parent = nil
            node.sortIndex = nextRootSortIndex()
        }

        modelContext.insert(node)
        persist()
    }

    private func removeSelectedNode() {
        guard let selectedNode else { return }
        let parent = selectedNode.parent
        let selectedID = selectedNode.persistentModelID

        modelContext.delete(selectedNode)
        normalizeSiblings(in: parent)
        persist()

        if selectedNodeID == selectedID {
            if let parent {
                selectedNodeID = parent.persistentModelID
            } else {
                selectedNodeID = rootNodes.first?.persistentModelID
            }
        }
    }

    private func canMoveSelectedNode(delta: Int) -> Bool {
        guard let selectedNode else { return false }
        let siblings = siblingsOfSelectedNode(selectedNode)
        guard let index = siblings.firstIndex(where: { $0.persistentModelID == selectedNode.persistentModelID }) else {
            return false
        }
        let newIndex = index + delta
        return newIndex >= 0 && newIndex < siblings.count
    }

    private func moveSelectedNode(delta: Int) {
        guard let selectedNode else { return }
        let siblings = siblingsOfSelectedNode(selectedNode)
        guard let index = siblings.firstIndex(where: { $0.persistentModelID == selectedNode.persistentModelID }) else {
            return
        }
        let newIndex = index + delta
        guard newIndex >= 0 && newIndex < siblings.count else { return }

        let other = siblings[newIndex]
        let currentSort = selectedNode.sortIndex
        selectedNode.sortIndex = other.sortIndex
        other.sortIndex = currentSort
        normalizeSiblings(in: selectedNode.parent)
        persist()
    }

    private func siblingsOfSelectedNode(_ node: ActionNode) -> [ActionNode] {
        if let parent = node.parent {
            return parent.children.sorted { $0.sortIndex < $1.sortIndex }
        }
        return sortedRoots
    }

    private func nextRootSortIndex() -> Int {
        (sortedRoots.last?.sortIndex ?? -1) + 1
    }

    private func nextSortIndex(in folder: ActionNode) -> Int {
        let sorted = folder.children.sorted { $0.sortIndex < $1.sortIndex }
        return (sorted.last?.sortIndex ?? -1) + 1
    }

    private func normalizeSiblings(in parent: ActionNode?) {
        if let parent {
            let siblings = parent.children.sorted { $0.sortIndex < $1.sortIndex }
            for (idx, node) in siblings.enumerated() {
                node.sortIndex = idx
            }
            return
        }

        let roots = sortedRoots
        for (idx, node) in roots.enumerated() {
            node.sortIndex = idx
        }
    }

    private func flatten(nodes: [ActionNode]) -> [ActionNode] {
        var result: [ActionNode] = []
        for node in nodes.sorted(by: { $0.sortIndex < $1.sortIndex }) {
            result.append(node)
            result.append(contentsOf: flatten(nodes: node.children))
        }
        return result
    }

    @ViewBuilder
    private func selectionBackground(for node: ActionNode) -> some View {
        if selectedNodeID == node.persistentModelID {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.accentColor.opacity(0.2))
        } else {
            Color.clear
        }
    }

    private func persist() {
        try? modelContext.save()
    }
}

private extension ActionNode {
    var sortedChildrenForUI: [ActionNode]? {
        let sorted = children.sorted { $0.sortIndex < $1.sortIndex }
        return sorted.isEmpty ? nil : sorted
    }
}

// MARK: - Preview

#Preview {
    ActionsPrefsView()
        .environment(ClipMenuSettings())
    .modelContainer(for: [ActionNode.self], inMemory: true)
    .frame(width: 820, height: 620)
}
