import SwiftData

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

    /// Returns the action nodes applicable to the given clip entry.
    ///
    /// TODO: Phase 2 — replicate the type-filtering logic from
    ///       ActionNodeController.m before returning nodes.
    func availableActions(for entry: ClipEntry) async -> [ActionNode] {
        // TODO: Phase 2
        return []
    }

    /// Executes the action identified by `node` on `entry`.
    ///
    /// TODO: Phase 2 — dispatch to ScriptEngine for JS actions or to
    ///       BuiltInActionController equivalents for built-in types.
    func perform(action node: ActionNode, on entry: ClipEntry) async {
        // TODO: Phase 2
    }
}
