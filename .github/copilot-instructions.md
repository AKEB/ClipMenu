# ClipMenu — Agent Instructions

## Migration Status Rule

**Every agent that completes or advances a migration step MUST update `migration_status.md` before finishing.**

This applies to any work that:
- Implements or stubs a file listed in `Sources/`
- Changes `project.yml` or regenerates `ClipMenu.xcodeproj`
- Adds, removes, or modifies a package dependency
- Makes a structural change to `Sources/` or `legacy/`
- Completes or partially completes any task listed under "Not Started" or "In Progress" in `migration_status.md`

**How to update:**
1. Move the completed task from "Not Started" → "Completed" (or update its checkbox).
2. If a task is partially done, move it to "In Progress" with a short note on what remains.
3. Update the "Overall progress" summary line at the top.
4. Do **not** remove the "Key Decisions" table entries without explicit user instruction.

## Architecture

- New Swift source lives in `Sources/` (see `doc/migration.md` for the full directory spec).
- Legacy Objective-C source is in `legacy/Source/` — treat it as read-only reference; do not modify.
- Build system: XcodeGen — edit `project.yml`, then run `xcodegen generate` to regenerate `ClipMenu.xcodeproj`.
- The `.xcodeproj` is generated output; never hand-edit `project.pbxproj`.

## SwiftUI View Rule

**Every SwiftUI `View` in `Sources/UI/` MUST have at least one `#Preview` block.**

- The preview must compile and render without requiring a live app or device.
- Use in-memory `ModelContainer` when SwiftData models are needed:
  ```swift
  .modelContainer(for: [ClipEntry.self, ...], inMemory: true)
  ```
- Inject required environment values using test instances:
  ```swift
  .environment(ClipMenuSettings())
  .environment(\.clipsService, ClipsService(settings: ClipMenuSettings()))
  ```
- A view file without a `#Preview` block must not be marked completed in `migration_status.md`.

## Build & Verify

```sh
xcodegen generate
xcodebuild -project ClipMenu.xcodeproj -scheme ClipMenu -configuration Debug build \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

Both commands must succeed with no errors before a task is marked completed.

## Behavior Reference

When implementing any feature, consult the corresponding legacy file first:

| Feature | Legacy reference |
|---|---|
| Clipboard capture | `legacy/Source/ClipsController.m` |
| Menu construction | `legacy/Source/MenuController.m` |
| Actions | `legacy/Source/ActionController.m`, `ActionNodeFactory.m` |
| JavaScript scripting | `legacy/Source/JavaScriptSupport.m` |
| Preferences keys | `legacy/Source/constants.h` |
| Paste synthesis | `legacy/Source/AppController.m` |

Do not invent behaviour — read the legacy source.
