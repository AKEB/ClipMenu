import SwiftData
import Foundation

/// One-time migration of user data from the legacy Objective-C app.
///
/// Reads the three legacy data files and inserts equivalent SwiftData records:
///
/// | Legacy file              | Swift model               |
/// |--------------------------|---------------------------|
/// | `~/Library/.../clips.data`   | `ClipEntry`           |
/// | `~/Library/.../Snippets.xml` | `SnippetFolder`, `Snippet` |
/// | `~/Library/.../actions.plist`| `ActionNode`          |
///
/// Reference: `legacy/Source/ClipsController.m` (clips path),
///            `legacy/Source/SnippetsController.m` (snippets path),
///            `legacy/Source/ActionNodeFactory.m` (actions path).
///
/// Migration runs at most once; completion is recorded in UserDefaults under
/// `legacyMigrationCompleted`.
struct LegacyMigration {

    static let completedKey = "legacyMigrationCompleted"

    static var isNeeded: Bool {
        !UserDefaults.standard.bool(forKey: completedKey)
    }

    /// Call from AppDelegate.applicationDidFinishLaunching if `isNeeded`.
    static func run(in context: ModelContext) {
        // TODO: Phase 1 — implement clips, snippets, and actions import.
        //       Mark complete: UserDefaults.standard.set(true, forKey: completedKey)
    }
}
