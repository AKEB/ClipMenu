import SwiftData

/// A node in the action tree (folder or leaf action).
///
/// Mirrors the data shape in `legacy/Source/ActionNode.{h,m}`.
/// See those files and `legacy/Source/ActionNodeFactory.m` before
/// modifying the tree structure.
@Model
final class ActionNode {

    var title: String
    var isEnabled: Bool
    var sortIndex: Int

    /// `nil` for folder nodes; populated for leaf action nodes.
    var actionType: String?
    var scriptContent: String?

    @Relationship(deleteRule: .cascade)
    var children: [ActionNode] = []

    var parent: ActionNode?

    init(title: String, sortIndex: Int = 0) {
        self.title     = title
        self.isEnabled = true
        self.sortIndex = sortIndex
    }
}
