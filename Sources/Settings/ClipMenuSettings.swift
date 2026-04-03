import Foundation

/// Strongly-typed wrappers around `@AppStorage` / `UserDefaults`.
///
/// Preserve all existing default-key names from `legacy/Source/constants.h`
/// so that user preferences survive the migration.
///
/// TODO: Phase 1 — add one @AppStorage property for every key in
///       `legacy/Source/constants.h` and migrate their default values.
struct ClipMenuSettings {

    // MARK: - General
    // TODO: loginItemEnabled, maxHistorySize, ...

    // MARK: - Menu
    // TODO: showStatusItem, menuIconStyle, inlinePreviewLength, ...

    // MARK: - Actions
    // TODO: actionsEnabled, ...

    // MARK: - Shortcuts
    // TODO: mainMenuShortcut, historyMenuShortcut, snippetMenuShortcut, ...
}
