import SwiftData
import Foundation

/// Manages the action tree and dispatches script execution.
///
/// Reference: `legacy/Source/ActionController.{h,m}`,
///            `ActionNode.{h,m}`, `ActionNodeFactory.{h,m}`,
///            `BuiltInActionController.{h,m}`, `JavaScriptSupport.{h,m}`.
actor ActionService {

    private var context: ModelContext?
    private let engine = ScriptEngine()

    func start(context: ModelContext) {
        self.context = context
    }

    func availableActions(for entry: ClipEntry) async -> [ActionNode] {
        _ = entry
        guard let context else { return [] }

        do {
            return try context.fetch(FetchDescriptor<ActionNode>(sortBy: [SortDescriptor(\ActionNode.sortIndex)]))
        } catch {
            return []
        }
    }

    func perform(action node: ActionNode, on entry: ClipEntry) async {
        guard node.isEnabled else { return }

        switch node.actionType {
        case "javaScript":
            guard let script = node.scriptContent else { return }
            _ = engine.run(script: script, clip: ScriptableClip())
        case "builtin":
            _ = entry
            return
        default:
            return
        }
    }
}
