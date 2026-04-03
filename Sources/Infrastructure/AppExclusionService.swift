import AppKit

/// Provides the bundle identifier of the currently frontmost application so
/// that ClipsService can skip recording clipboard changes triggered by ClipMenu
/// itself.
///
/// Mirrors `legacy/Source/AppController.m -frontmostApplicationBundleIdentifier`.
struct AppExclusionService {

    func frontmostBundleIdentifier() -> String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    /// Returns `true` when clipboard changes should be ignored because
    /// the frontmost app is in the exclusion list stored in user preferences.
    ///
    /// TODO: Phase 1 — compare frontmostBundleIdentifier() against the
    ///       user-configured exclusion list from ClipMenuSettings.
    func shouldExclude() -> Bool {
        // TODO: Phase 1
        return false
    }
}
