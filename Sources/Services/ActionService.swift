import SwiftData
import AppKit
import Foundation

/// Manages the action tree and dispatches script execution.
///
/// Reference: `legacy/Source/ActionController.{h,m}`,
///            `ActionNode.{h,m}`, `ActionNodeFactory.{h,m}`,
///            `BuiltInActionController.{h,m}`, `JavaScriptSupport.{h,m}`.
actor ActionService {

    private var context: ModelContext?
    private let engine = ScriptEngine()
    private let paste  = PasteService()

    func start(context: ModelContext) {
        self.context = context
    }

    func availableActions(for entry: ClipEntry) async -> [ActionNode] {
        guard let context else { return [] }
        do {
            return try context.fetch(FetchDescriptor<ActionNode>(
                sortBy: [SortDescriptor(\ActionNode.sortIndex)]
            ))
        } catch {
            return []
        }
    }

    /// Dispatches an action node against a clip entry.
    /// After a successful builtin or script action the result is placed on the
    /// pasteboard and Cmd+V is synthesised.
    func perform(action node: ActionNode, on entry: ClipEntry) async {
        guard node.isEnabled else { return }

        switch node.actionType {

        case "javaScript":
            guard let script = scriptSource(for: node) else { return }
            let scriptableClip = ScriptableClip(entry: entry)
            guard let resultText = engine.run(script: script, clip: scriptableClip) else { return }
            let pboard = NSPasteboard.general
            pboard.clearContents()
            pboard.setString(resultText, forType: .string)
            await paste.paste()

        case "builtin":
            await performBuiltin(name: node.actionName ?? "", on: entry)

        default:
            break
        }
    }

    // MARK: - Built-in actions
    // Keep in sync with legacy/Source/BuiltInActionController.m

    private func performBuiltin(name: String, on entry: ClipEntry) async {
        let pboard = NSPasteboard.general

        switch name {
        case "removeAction":
            guard let context else { return }
            context.delete(entry)
            try? context.save()

        case "pasteAsPlainText":
            guard let text = entry.stringValue else { return }
            pboard.clearContents()
            pboard.setString(text, forType: .string)
            await paste.paste()

        case "pasteAsFilePath":
            guard let files = entry.filenames, !files.isEmpty else { return }
            let text = files.joined(separator: "\n")
            pboard.clearContents()
            pboard.setString(text, forType: .string)
            await paste.paste()

        case "pasteAsHFSFilePath":
            guard let files = entry.filenames, !files.isEmpty else { return }
            let hfsPaths = files.compactMap { posixPath -> String? in
                let url = URL(fileURLWithPath: posixPath) as CFURL
                return CFURLCopyFileSystemPath(url, CFURLPathStyle(rawValue: 1)!) as String?
            }
            let text = hfsPaths.joined(separator: "\n")
            pboard.clearContents()
            pboard.setString(text, forType: .string)
            await paste.paste()

        default:
            break
        }
    }

    // MARK: - Helpers

    private func scriptSource(for node: ActionNode) -> String? {
        if let inline = node.scriptContent, !inline.isEmpty { return inline }
        if let path = node.scriptPath { return try? String(contentsOfFile: path, encoding: .utf8) }
        return nil
    }
}
