# ClipMenu Migration Status

> **Every agent that completes a migration step MUST update this file before committing.**
> See `.github/copilot-instructions.md` for the full rule.

**Overall progress:** Bootstrapping complete — Phase 1 not started

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

---

## In Progress

_Nothing currently in progress._

---

## Not Started

### Phase 1 — Infrastructure (no UI changes)
See `doc/migration.md` §"Phase 1" for full task list.

- [ ] **1.1** SwiftData models — `ClipEntry.contentHash` algorithm (ref: `legacy/Source/Clip.m -hash`)
- [ ] **1.2** `ClipboardMonitor` — NSPasteboard polling loop + Combine publisher
- [ ] **1.3** `ClipsService` — pasteboard reading, deduplication, SwiftData persistence
- [ ] **1.4** `PasteService` — CGEvent Cmd+V synthesis, Accessibility permission prompt
- [ ] **1.5** `ClipMenuSettings` — `@AppStorage` wrappers for all keys in `legacy/Source/constants.h`
- [ ] **1.6** `LoginItemService` — `SMAppService` wiring in `AppDelegate`
- [ ] **1.7** `AppExclusionService` — frontmost-app exclusion list logic
- [ ] **1.8** `LegacyMigration` — one-time import of `clips.data`, `Snippets.xml`, `actions.plist`
- [ ] **1.9** `SnippetService` — CRUD + sort order
- [ ] **1.10** `ActionService` — action tree loading and dispatch scaffolding
- [ ] **1.11** Wire services into `AppDelegate.applicationDidFinishLaunching`

### Phase 2 — UI
- [ ] `ClipMenuView` — history rows, snippet section, action section, separator items
- [ ] `ClipMenuItem` — type icon + inline preview (ref: `legacy/Source/MenuController.m -imageForClip:`)
- [ ] `SnippetSection` — enabled folders + nested snippet rows
- [ ] `ActionSection` — filtered action tree
- [ ] `PreferencesView` tabs — General, Menu, Actions (full implementation)
- [ ] `ScriptEngine` / `ScriptableClip` — JSContext bridge (ref: `legacy/Source/JavaScriptSupport.m`)
- [ ] `ClipMenuApp+Scenes.swift` — `MenuBarExtra` + `Settings` scenes
- [ ] Update `ClipMenuApp.swift` to inject `ModelContainer` and services

### Phase 3 — Hotkeys + Polish
- [ ] `HotkeyService` — `KeyboardShortcuts` registration for 3 shortcuts
- [ ] `ShortcutsPrefsView` — `KeyboardShortcuts.Recorder` rows
- [ ] End-to-end smoke test: history capture → select → paste

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
