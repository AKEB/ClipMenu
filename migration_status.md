# ClipMenu Migration Status

> **Every agent that completes a migration step MUST update this file before committing.**
> See `.github/copilot-instructions.md` for the full rule.

**Overall progress:** Phase 1 complete — Phase 2 complete — Phase 3 complete (hotkeys wired, ShortcutsPrefsView implemented, settings persistence/startup hydration hardened, build passes)

---

## Completed

### Repository restructure
- [x] All legacy Objective-C source moved to `legacy/` for reference
  - `legacy/Source/` — 40+ ObjC `.h`/`.m` files
  - `legacy/English.lproj/`, `legacy/Japanese.lproj/` — XIB + strings
  - `legacy/resource/` — icons, scripts, DSA keys
  - `legacy/Snippets.xcdatamodel/` — Core Data model
  - `legacy/ClipMenu.xcodeproj/` — original Xcode project
  - `legacy/Info.plist`, `legacy/ClipMenu_Prefix.pch`

### New project bootstrapped
- [x] `Sources/` tree created with stub Swift files (no implementation yet)
- [x] `Assets.xcassets/` with `AppIcon.appiconset`
- [x] `ClipMenu.entitlements` (non-sandboxed, CGEvent automation)
- [x] `project.yml` (XcodeGen spec) — macOS 14.0, Swift 5.9, bundle ID `com.naotaka.ClipMenu`
- [x] `ClipMenu.xcodeproj` generated via `xcodegen generate`
- [x] Build confirmed: project generates without errors

### Documentation
- [x] `BUILD.md` added with modern build commands and legacy release-script notes

---

## In Progress

No tasks currently in progress.

---

## Completed

### Phase 2 — UI

- [x] `ScriptEngine` — JSContext bridge with `clipText`/`clip` globals and `ClipMenu.require()` loader
- [x] `ScriptableClip` — `JSExport` bridge: `text`, `setStringAttributes(_:)`, `addStringAttributes(_:)`, CSS color extension
- [x] `ClipMenuApp` — `MenuBarExtra` + `Settings` scenes wired; `EnvironmentKeys.swift` with service environment keys
- [x] `ClipMenuView` — full history section (inline + folder groups), snippet section (above/below/hidden), clear history, preferences + quit items; `#Preview`
- [x] `ClipMenuItem` — type icon via `NSWorkspace`, thumbnail scaling, trimTitle(), numbering, labels, tooltip, font size, `#Preview`
- [x] `SnippetSection` — enabled folders, single-snippet inline / multi-snippet submenu, paste on select; `#Preview`
- [x] `ActionSection` — folder + leaf node rendering, action dispatch; `#Preview`
- [x] `GeneralPrefsView` — login item, clipboard prefs, store-types grid, exclude-apps editor; `#Preview`
- [x] `MenuPrefsView` — title length, inline/folder counts, numbering, labels, clear-history, tooltips, font size, images, icons; `#Preview`
- [x] `ActionsPrefsView` — enable toggle, modifier-click pickers, invoke-immediately; `#Preview`
- [x] `ShortcutsPrefsView` — `KeyboardShortcuts.Recorder` controls for all three shortcuts (⌘⇧V, ⌘⌃V, ⌘⇧B); `#Preview`
- [x] `PreferencesView` — tab shell; `#Preview`
- [x] `LegacyMigration` — snippet import from `Snippets.xml` added (Core Data XML → SwiftData)
- [x] `SnippetService.paste(snippet:)` — implemented (write to pasteboard + `PasteService.paste()`)
- [x] `ActionService` — builtin actions (`removeAction`, `pasteAsPlainText`, `pasteAsFilePath`, `pasteAsHFSFilePath`); JS script dispatch via `ScriptEngine`
- [x] `ClipsService.clearAll()` and `ClipsService.copyStringToPasteboard(_:)` added

### Phase 3 — Hotkeys + Polish

- [x] `HotkeyService` — `KeyboardShortcuts.Name` extensions (`.openClipMenu` ⌘⇧V, `.openHistory` ⌘⌃V, `.openSnippets` ⌘⇧B) with default combos matching legacy PTHotKey defaults; `register()` / `unregister()` implemented; activates `MenuBarExtra` via KVC status-item lookup + `performClick`
- [x] `AppRuntime` — `hotkeyService: HotkeyService` added
- [x] `AppDelegate` — `hotkeyService.register()` called in `applicationDidFinishLaunching`; `hotkeyService.unregister()` called in `applicationWillTerminate`
- [x] `ShortcutsPrefsView` — `KeyboardShortcuts.Recorder` controls for all three shortcuts (⌘⇧V, ⌘⌃V, ⌘⇧B); `#Preview`
- [x] Build passes (one deprecation warning for `icon(forFileType:)`, no errors)
- [x] `ClipMenuSettings` persistence hardened: replaced `@AppStorage` + `@ObservationIgnored` fields with explicit `UserDefaults`-backed observed properties, added startup reload and value sanitization for stable defaults and app-launch behavior
- [x] `AppDelegate` now calls `settings.reload()` during launch before services start, ensuring settings are loaded/normalized before initial menu and clipboard service usage
- [x] Accessibility prompt no longer triggers unconditionally at launch; permission prompt is now lazy via paste path (`PasteService`) and startup no longer opens System Settings repeatedly
- [x] Settings reload now uses typed fallback defaults (`object(forKey:)` with explicit defaults) rather than raw `bool/integer` reads, improving launch-time hydration correctness when keys are missing or malformed
- [x] SwiftData environment wiring hardened for menu startup: `ClipMenuApp` now injects `.modelContainer(modelContainer)` directly into `ClipMenuView` and `PreferencesView` roots to avoid `@Query` modelContext-missing errors on initial load
- [x] Paste actions no longer force Accessibility permission prompts on each click; `PasteService` now checks `AXIsProcessTrusted()` without opening System Settings, preventing repetitive prompt spam during menu usage
- [x] Hotkey registration reliability improved: `HotkeyService` now dispatches menu activation on the main thread and uses resilient status-item lookup (`statusItems`/`_statusItems`) so Cmd+Shift+V / Cmd+Shift+B consistently open the menu
- [x] Hotkey bootstrap hardening: `HotkeyService.register()` now restores default shortcuts when persisted entries are missing/disabled, preventing inactive Cmd+Shift+V / Cmd+Shift+B on launch
- [x] Hotkey trigger path hardened further: switched handlers to key-down events and made menu activation retry on main-thread with app activation before status-item click, improving global shortcut responsiveness when app is backgrounded
- [x] Launch-order fix: `AppDelegate` now registers hotkeys independently of SwiftData readiness and retries data-service startup until `modelContainer.mainContext` exists, preventing silent startup paths where shortcuts/services were skipped
- [x] Hotkey menu presentation refined: shortcuts now trigger on key-up, menu activation is deferred to next runloop, forced app activation was removed, and status-item targeting/click fallback logic was strengthened to prevent focus-steal without menu display
- [x] Hotkey presentation simplified to one UI path: shortcuts now always open a native `NSMenu` popup at cursor (no status-item click injection, no secondary fallback UI), matching legacy interaction and arrow-key navigation expectations
- [x] Added structured hotkey diagnostics logging (`Logger`) across registration, trigger handling, status-item lookup retries, menu-open detection, and fallback-popup presentation to accelerate runtime troubleshooting
- [x] Fixed hotkey retry exhaustion path: when no status-item button is found after all retries, `HotkeyService` now calls completion with failure so fallback panel presentation always executes
- [x] Fallback panel presentation polished: replaced collapsed non-activating panel layout with a fixed-size utility panel and wrapped SwiftUI root (`FallbackPanelRootView`) so hotkey fallback UI renders at readable width/height

---

## Key Decisions (do not revisit without updating this section)

| Decision | Value | Rationale |
|---|---|---|
| Bundle ID | `com.naotaka.ClipMenu` | Required for UserDefaults migration from legacy app |
| Deployment target | macOS 14.0 | Minimum required for SwiftData |
| Swift version | 5.9+ | SwiftData, @Observable, structured concurrency |
| Sandboxing | **No sandbox** | CGEvent paste requires Accessibility; incompatible with sandbox |
| External deps | `KeyboardShortcuts` only | All other APIs are system-provided |
| Legacy data location reference | `legacy/Source/ClipsController.m`, `SnippetsController.m`, `ActionNodeFactory.m` | Canonical paths for migration import |

---

## Reference Files

| What to check | Where |
|---|---|
| Full architecture plan | `doc/migration.md` |
| All features to preserve | `doc/features.md` |
| Legacy clipboard behavior | `legacy/Source/ClipsController.m` |
| Legacy menu behavior | `legacy/Source/MenuController.m` |
| Legacy action system | `legacy/Source/ActionController.m`, `ActionNodeFactory.m` |
| Legacy JS integration | `legacy/Source/JavaScriptSupport.m` |
| Legacy preferences keys | `legacy/Source/constants.h` |
| Snippet/action data paths | `legacy/Source/SnippetsController.m`, `ActionNodeFactory.m` |
