# ClipMenu — Migration Implementation Plan

This document is a step-by-step implementation guide for an LLM to execute the architectural migration described in `enhancements.md`. It assumes the following setup work has already been completed by a human:

- Legacy Objective-C source has been copied to a `legacy/` folder for reference.
- A new Xcode project has been bootstrapped (Swift, macOS app, `@main` entry point).
- Bundle ID is preserved as `com.naotaka.ClipMenu` (required for UserDefaults migration).
- The project is committed to a branch (e.g., `modernized`).

**Minimum deployment target:** macOS 14.0 (required for SwiftData).  
**Swift version:** 5.9+.  
**Reference files:** All `legacy/Source/*.{h,m}` files and `doc/features.md` are authoritative for behavior. When in doubt about a detail, read those files — do not invent behavior.

---

## Dependencies

Before writing any code, add these Swift Package dependencies to the Xcode project:

| Package | URL | Purpose |
|---|---|---|
| `KeyboardShortcuts` | `github.com/sindresorhus/KeyboardShortcuts` | Global hotkeys (Phase 3) |

No other third-party dependencies are needed. All other APIs are system-provided.

---

## Entitlements

Create `ClipMenu.entitlements` with:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "...">
<plist version="1.0">
<dict>
    <!-- Required: reading from NSPasteboard in background -->
    <key>com.apple.security.temporary-exception.apple-events</key>
    <false/>
    <!-- Required: CGEvent posting for paste -->
    <key>com.apple.security.automation.apple-events</key>
    <true/>
</dict>
</plist>
```

The app must **not** be sandboxed. CGEvent-based paste (`kCGSessionEventTap`) requires Accessibility permission from the user, granted once at runtime via a standard system prompt. Do not request sandbox entitlements.

---

## Proposed File Structure

Create files in this order to respect dependencies:

```
Sources/
├── App/
│   ├── ClipMenuApp.swift          — @main entry point, ModelContainer setup
│   └── AppDelegate.swift          — NSApplicationDelegate (lifecycle hooks)
├── Models/
│   ├── ClipEntry.swift            — SwiftData model for clipboard entries
│   ├── SnippetFolder.swift        — SwiftData model for snippet folders
│   ├── Snippet.swift              — SwiftData model for snippets
│   └── ActionNode.swift           — SwiftData model for action tree
├── Settings/
│   └── ClipMenuSettings.swift     — @AppStorage typed wrappers
├── Infrastructure/
│   ├── ClipboardMonitor.swift     — NSPasteboard KVO → Combine publisher
│   ├── PasteService.swift         — CGEvent Cmd+V synthesis
│   ├── HotkeyService.swift        — KeyboardShortcuts registration
│   ├── LoginItemService.swift     — SMAppService wrappers
│   └── AppExclusionService.swift  — NSWorkspace frontmost app check
├── Scripting/
│   ├── ScriptEngine.swift         — JSContext-based script runner
│   └── ScriptableClip.swift       — JSExport bridge for clip manipulation
├── Services/
│   ├── ClipsService.swift         — Actor: pasteboard → ClipEntry CRUD
│   ├── SnippetService.swift       — Actor: snippet CRUD
│   └── ActionService.swift        — Actor: action tree, script dispatch
├── Migration/
│   └── LegacyMigration.swift      — One-time import of clips.data, Snippets.xml, actions.plist
└── UI/
    ├── ClipMenuApp+Scenes.swift   — MenuBarExtra + Settings scenes
    ├── ClipMenuView.swift         — Root menu content
    ├── ClipMenuItem.swift         — Single clip row
    ├── SnippetSection.swift       — Snippets submenu
    ├── ActionSection.swift        — Actions submenu
    ├── PreferencesView.swift      — Settings scene root (tab container)
    └── Preferences/
        ├── GeneralPrefsView.swift
        ├── MenuPrefsView.swift
        ├── ActionsPrefsView.swift
        └── ShortcutsPrefsView.swift
```

---

## Phase 1 — Infrastructure (No UI Changes)

Phase 1 replaces deprecated and polling-based APIs with modern equivalents. No UI is built in this phase. At the end of Phase 1, the app's core services are functional and testable in isolation.

---

### Task 1.1 — SwiftData Models

**File:** `Sources/Models/ClipEntry.swift`

```swift
import SwiftData
import Foundation

@Model
final class ClipEntry {
    var createdAt: Date
    var lastUsedAt: Date
    var types: [String]          // pasteboard UTI/type strings, order preserved
    var stringValue: String?
    var rtfData: Data?           // RTF or RTFD bytes
    var isRTFD: Bool             // true if rtfData is RTFD (needed for export)
    var pdfData: Data?
    var filenames: [String]?
    var urlStrings: [String]?
    var imageData: Data?         // TIFF bytes

    init() {
        self.createdAt = .now
        self.lastUsedAt = .now
        self.types = []
        self.isRTFD = false
    }
}
```

**Equality note:** Two `ClipEntry` values are considered duplicates if their computed hash matches. Replicate the hash algorithm from `legacy/Source/Clip.m` `-hash`:
- Start with `types.joined()` hash.
- XOR with: image TIFF byte count, each filename's hash, each URL string's hash, PDF byte count, `stringValue` hash, RTF byte count.
- Store this as a computed `var contentHash: Int` on the model.

**File:** `Sources/Models/SnippetFolder.swift`

```swift
import SwiftData

@Model
final class SnippetFolder {
    var title: String
    var isEnabled: Bool
    var sortIndex: Int
    @Relationship(deleteRule: .cascade, inverse: \Snippet.folder)
    var snippets: [Snippet] = []

    init(title: String) {
        self.title = title
        self.isEnabled = true
        self.sortIndex = 0
    }
}
```

**File:** `Sources/Models/Snippet.swift`

```swift
import SwiftData

@Model
final class Snippet {
    var title: String
    var content: String
    var isEnabled: Bool
    var sortIndex: Int
    var folder: SnippetFolder?

    init(title: String, content: String = "") {
        self.title = title
        self.content = content
        self.isEnabled = true
        self.sortIndex = 0
    }
}
```

**File:** `Sources/Models/ActionNode.swift`

```swift
import SwiftData

@Model
final class ActionNode {
    var title: String
    var isLeaf: Bool
    var sortIndex: Int
    var actionType: String?    // "builtin" | "javaScript"
    var actionName: String?    // for builtin: "removeAction", "pasteAsPlainText", etc.
    var scriptPath: String?    // for javaScript: absolute path to .js file
    @Relationship(deleteRule: .cascade)
    var children: [ActionNode] = []

    init(title: String, isLeaf: Bool) {
        self.title = title
        self.isLeaf = isLeaf
    }
}
```

**Verification:** Compile only. No runtime test needed yet.

---

### Task 1.2 — Settings Store

**File:** `Sources/Settings/ClipMenuSettings.swift`

Map every legacy `CMPref*` key from `doc/features.md` § "Complete Preference Key Reference" to a typed `@AppStorage` property. Use **the same string key names** as the legacy app so that existing user preferences are read automatically (the bundle ID is preserved).

```swift
import SwiftUI
import Combine

// Use @Observable so SwiftUI views and service actors can react to changes.
@Observable
final class ClipMenuSettings {

    // MARK: General
    @ObservationIgnored @AppStorage("CMPrefLoginItem")
    var launchAtLogin: Bool = false

    @ObservationIgnored @AppStorage("CMPrefSuppressAlertForLoginItem")
    var suppressLoginItemAlert: Bool = false

    @ObservationIgnored @AppStorage("CMPrefInputPasteCommand")
    var autoPasteAfterSelection: Bool = true

    @ObservationIgnored @AppStorage("CMPrefReorderClipsAfterPasting")
    var reorderClipsAfterPasting: Bool = true

    @ObservationIgnored @AppStorage("CMPrefMaxHistorySize")
    var maxHistorySize: Int = 20

    @ObservationIgnored @AppStorage("CMPrefAutosaveDelay")
    var autosaveDelay: Int = 1800          // seconds

    @ObservationIgnored @AppStorage("CMPrefSaveHistoryOnQuit")
    var saveHistoryOnQuit: Bool = true

    @ObservationIgnored @AppStorage("CMPrefTimeInterval")
    var pollingInterval: Double = 0.75     // kept for fallback timer only

    @ObservationIgnored @AppStorage("CMPrefShowStatusItem")
    var showStatusItem: Bool = true

    @ObservationIgnored @AppStorage("CMPrefExcludeApps")
    private var _excludeAppsData: Data = Data()

    var excludeApps: [[String: String]] {   // array of {bundleIdentifier, name}
        (try? JSONDecoder().decode([[String: String]].self, from: _excludeAppsData)) ?? []
    }

    // MARK: Menu Display
    @ObservationIgnored @AppStorage("CMPrefMaxMenuItemTitleLength")
    var maxMenuItemTitleLength: Int = 20

    @ObservationIgnored @AppStorage("CMPrefNumberOfItemsPlaceInline")
    var numberOfItemsInline: Int = 0

    @ObservationIgnored @AppStorage("CMPrefNumberOfItemsPlaceInsideFolder")
    var numberOfItemsPerFolder: Int = 10

    @ObservationIgnored @AppStorage("CMPrefMenuItemsAreMarkedWithNumbers")
    var numberedMenuItems: Bool = true

    @ObservationIgnored @AppStorage("CMPrefMenuItemsTitleStartWithZero")
    var numberingStartsAtZero: Bool = false

    @ObservationIgnored @AppStorage("CMPrefAddNumericKeyEquivalents")
    var numericKeyEquivalents: Bool = false

    @ObservationIgnored @AppStorage("CMPrefShowLabelsInMenu")
    var showTypeLabels: Bool = true

    @ObservationIgnored @AppStorage("CMPrefAddClearHistoryMenuItem")
    var showClearHistory: Bool = true

    @ObservationIgnored @AppStorage("CMPrefShowAlertBeforeClearHistory")
    var confirmBeforeClear: Bool = true

    @ObservationIgnored @AppStorage("CMPrefShowToolTipOnMenuItem")
    var showTooltips: Bool = true

    @ObservationIgnored @AppStorage("CMPrefMaxLengthOfToolTip")
    var maxTooltipLength: Int = 200

    @ObservationIgnored @AppStorage("CMPrefChangeFontSize")
    var overrideMenuFontSize: Bool = false

    @ObservationIgnored @AppStorage("CMPrefHowToChangeFontSize")
    var fontSizeMode: Int = 0              // 0 = auto (match icon), 1 = manual

    @ObservationIgnored @AppStorage("CMPrefSelectedFontSize")
    var manualFontSize: Int = 14

    @ObservationIgnored @AppStorage("CMPrefShowImageInTheMenu")
    var showImageThumbnails: Bool = true

    @ObservationIgnored @AppStorage("CMPrefThumbnailWidth")
    var thumbnailWidth: Int = 100

    @ObservationIgnored @AppStorage("CMPrefThumbnailHeight")
    var thumbnailHeight: Int = 32

    @ObservationIgnored @AppStorage("CMPrefShowIconInTheMenu")
    var showTypeIcon: Bool = true

    @ObservationIgnored @AppStorage("CMPrefMenuIconSize")
    var menuIconSize: Int = 16             // 16, 32, or 48

    // MARK: Actions
    @ObservationIgnored @AppStorage("CMPrefEnableAction")
    var actionsEnabled: Bool = true

    @ObservationIgnored @AppStorage("CMPrefInvokeActionImmediately")
    var invokeActionImmediately: Bool = false

    // Modifier-click behaviors stored as raw JSON (value is "" | "popUpActionMenu" | action dict)
    @ObservationIgnored @AppStorage("CMPrefContorlClickBehavior")
    var ctrlClickBehavior: String = "popUpActionMenu"

    @ObservationIgnored @AppStorage("CMPrefShiftClickBehavior")
    var shiftClickBehavior: String = ""

    @ObservationIgnored @AppStorage("CMPrefOptionClickBehavior")
    var optionClickBehavior: String = ""

    @ObservationIgnored @AppStorage("CMPrefCommandClickBehavior")
    var commandClickBehavior: String = ""

    // MARK: Snippets
    // 0 = above clips, 1 = below clips, 2 = hidden
    @ObservationIgnored @AppStorage("CMPrefPositionOfSnippets")
    var snippetPosition: Int = 1

    // MARK: Updates
    @ObservationIgnored @AppStorage("CMEnableAutomaticCheck")
    var autoUpdateCheck: Bool = true

    @ObservationIgnored @AppStorage("CMEnableAutomaticCheckPreRelease")
    var usePreReleaseFeed: Bool = false

    @ObservationIgnored @AppStorage("CMUpdateCheckInterval")
    var updateCheckInterval: Int = 86400
}
```

**Important:** The legacy code uses `#define` string constants that must match exactly. Cross-check every key string against `legacy/Source/constants.h` and `legacy/Source/AppController.m` `+initialize` defaults registration. When there is any doubt about a key string, read the legacy source.

**Verification:** Add a unit test that constructs `ClipMenuSettings()` and asserts all defaults match those in `doc/features.md` § "Complete Preference Key Reference".

---

### Task 1.3 — Clipboard Monitor

**File:** `Sources/Infrastructure/ClipboardMonitor.swift`

```swift
import AppKit
import Combine

final class ClipboardMonitor {
    private let pasteboard = NSPasteboard.general
    private var observation: NSKeyValueObservation?
    let clipChanged = PassthroughSubject<NSPasteboard, Never>()

    func start() {
        observation = pasteboard.observe(\.changeCount, options: [.new]) { [weak self] pb, _ in
            self?.clipChanged.send(pb)
        }
    }

    func stop() {
        observation = nil
    }
}
```

No timer. The KVO fires synchronously on the main thread when the pasteboard changes.

**Fallback:** If KVO proves unreliable in testing (it has been reliable on macOS 10.8–14), add an optional `Timer`-based fallback at 250 ms that fires only when the last KVO notification was more than 500 ms ago. This is defensive only; do not add it unless there is a confirmed failure.

**Verification:** Write a unit test that creates a `ClipboardMonitor`, subscribes to `clipChanged`, writes a string to `NSPasteboard.general`, and asserts the publisher fires within 100 ms.

---

### Task 1.4 — App Exclusion Service

**File:** `Sources/Infrastructure/AppExclusionService.swift`

```swift
import AppKit

final class AppExclusionService {
    private var excludedIDs: Set<String> = []

    func update(from settings: ClipMenuSettings) {
        excludedIDs = Set(settings.excludeApps.compactMap { $0["bundleIdentifier"] })
    }

    func frontmostAppIsExcluded() -> Bool {
        guard let id = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return false }
        return excludedIDs.contains(id)
    }

    /// Returns a list of currently running user-facing apps for the exclude list picker.
    func runningUserApps() -> [(name: String, bundleID: String)] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in
                guard let name = app.localizedName, let id = app.bundleIdentifier else { return nil }
                return (name: name, bundleID: id)
            }
            .sorted { $0.name < $1.name }
    }
}
```

**Verification:** Unit test that `frontmostAppIsExcluded()` returns `true` when the set contains the current frontmost app's bundle ID, and `false` otherwise.

---

### Task 1.5 — Paste Service

**File:** `Sources/Infrastructure/PasteService.swift`

```swift
import CoreGraphics
import AppKit

final class PasteService {
    private var cachedVKeyCode: CGKeyCode?

    func paste() {
        guard let keyCode = vKeyCode() else { return }
        let src = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true)
        let up   = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false)
        down?.flags = .maskCommand
        up?.flags   = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    private func vKeyCode() -> CGKeyCode? {
        if let cached = cachedVKeyCode { return cached }

        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return CGKeyCode(9)  // ANSI fallback
        }
        let layout = unsafeBitCast(layoutData, to: CFData.self)
        let layoutPtr = unsafeBitCast(CFDataGetBytePtr(layout), to: UnsafePointer<UCKeyboardLayout>.self)

        for keyCode in 0..<128 as Range<CGKeyCode> {
            var deadKeyState: UInt32 = 0
            var chars = [UniChar](repeating: 0, count: 4)
            var length = 0
            let result = UCKeyTranslate(
                layoutPtr, keyCode,
                UInt16(kUCKeyActionDisplay), 0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState, 4, &length, &chars
            )
            if result == noErr, length > 0 {
                let s = String(utf16CodeUnits: chars, count: length)
                if s.lowercased() == "v" {
                    cachedVKeyCode = keyCode
                    return keyCode
                }
            }
        }
        return CGKeyCode(9)  // ANSI fallback
    }
}
```

This replicates the behavior of `legacy/Source/CMUtilities.m` `postCommandV()`. The keycode cache is per-instance; invalidate `cachedVKeyCode` if you observe `NSTextInputContextKeyboardSelectionDidChangeNotification`.

**Verification:** Manual test only (requires Accessibility permission). Confirm that calling `paste()` while a text field is focused and a string is on the pasteboard inserts the string.

---

### Task 1.6 — Login Item Service

**File:** `Sources/Infrastructure/LoginItemService.swift`

```swift
import ServiceManagement

final class LoginItemService {
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
```

`SMAppService` requires macOS 13+. No entitlement required. Available on macOS 13+.

---

### Task 1.7 — JavaScript Engine

**File:** `Sources/Scripting/ScriptEngine.swift`

```swift
import JavaScriptCore
import Foundation

final class ScriptEngine {
    private let context: JSContext

    init() {
        context = JSContext()
        context.name = "ClipMenu Script Engine"

        // Set up ClipMenu.require(relativePath) — loads a lib script
        let requireBlock: @convention(block) (String) -> Void = { [weak self] relativePath in
            guard let self else { return }
            if let source = self.libSource(for: relativePath) {
                self.context.evaluateScript(source)
            }
        }
        let namespace = JSValue(newObjectIn: context)
        namespace?.setObject(requireBlock, forKeyedSubscript: "require" as NSString)
        context["ClipMenu"] = namespace

        context.exceptionHandler = { _, exception in
            // Exceptions are surfaced through __scriptException; also log here.
            print("[ScriptEngine] exception: \(exception?.toString() ?? "?")")
        }
    }

    /// Runs `script` source code with `clipText` and `clip` injected.
    /// Returns the string result, or nil if the script returned undefined or threw.
    func run(script: String, clipText: String, clip: ScriptableClip) -> String? {
        // Reset exception sentinel
        context.evaluateScript("var __scriptException = '';")
        context["clipText"] = clipText
        context["clip"] = clip

        let wrapped = """
        function __wrapper(clipText, clip) {
            try { \(script) } catch(e) { __scriptException = e.toString(); return; }
        }
        """
        context.evaluateScript(wrapped)

        let result = context.evaluateScript("__wrapper(clipText, clip)")

        // Check for exception
        if let exc = context["__scriptException"]?.toString(), !exc.isEmpty {
            return nil
        }

        guard let result, !result.isUndefined, !result.isNull else { return nil }
        return result.toString()
    }

    // MARK: - Private

    private func libSource(for relativePath: String) -> String? {
        // Search app bundle first, then ~/Library/Application Support/ClipMenu/script/lib/
        let bundleURL = Bundle.main.resourceURL?
            .appendingPathComponent("script/lib")
            .appendingPathComponent(relativePath)
        let userURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("ClipMenu/script/lib")
            .appendingPathComponent(relativePath)

        for url in [bundleURL, userURL].compactMap({ $0 }) {
            if let source = try? String(contentsOf: url, encoding: .utf8) {
                return source
            }
        }
        return nil
    }
}
```

**File:** `Sources/Scripting/ScriptableClip.swift`

```swift
import JavaScriptCore
import AppKit

@objc protocol ScriptableClipExport: JSExport {
    var text: String? { get }
    func setStringAttributes(_ attrs: [String: Any])
    func addStringAttributes(_ attrs: [String: Any])
}

@objc final class ScriptableClip: NSObject, ScriptableClipExport {
    private var entry: ClipEntry

    init(entry: ClipEntry) {
        self.entry = entry
    }

    var text: String? { entry.stringValue }

    func setStringAttributes(_ attrs: [String: Any]) {
        applyAttributes(attrs, mode: .set)
    }

    func addStringAttributes(_ attrs: [String: Any]) {
        applyAttributes(attrs, mode: .add)
    }

    // MARK: - Private

    private enum Mode { case set, add }

    private func applyAttributes(_ attrs: [String: Any], mode: Mode) {
        guard entry.stringValue != nil, let rtfData = entry.rtfData else { return }

        let attrString: NSMutableAttributedString
        if entry.isRTFD {
            attrString = NSMutableAttributedString(rtfd: rtfData, documentAttributes: nil)
                ?? NSMutableAttributedString()
        } else {
            attrString = NSMutableAttributedString(rtf: rtfData, documentAttributes: nil)
                ?? NSMutableAttributedString()
        }

        let range = NSRange(location: 0, length: attrString.length)
        var nsAttrs: [NSAttributedString.Key: Any] = [:]

        // Color
        if let colorDict = attrs["color"] as? [String: Any] {
            if let fg = colorDict["foreground"] as? String,
               let color = NSColor(cssName: fg) {
                nsAttrs[.foregroundColor] = color
            }
            if let bg = colorDict["background"] as? String,
               let color = NSColor(cssName: bg) {
                nsAttrs[.backgroundColor] = color
            }
        }

        // Font
        if let fontDict = attrs["font"] as? [String: Any],
           let name = fontDict["name"] as? String,
           let size = fontDict["size"] as? CGFloat,
           let font = NSFont(name: name, size: size) {
            nsAttrs[.font] = font
        }

        // Underline
        if let ulDict = attrs["underline"] as? [String: Any] {
            var mask: Int = 0
            mask |= underlineStyle(from: ulDict["style"] as? String)
            mask |= underlinePattern(from: ulDict["pattern"] as? String)
            if (ulDict["byWord"] as? Bool) == true { mask |= NSUnderlineStyle.byWord.rawValue }
            nsAttrs[.underlineStyle] = mask
        }

        guard !nsAttrs.isEmpty else { return }
        attrString.beginEditing()
        switch mode {
        case .set: attrString.setAttributes(nsAttrs, range: range)
        case .add: attrString.addAttributes(nsAttrs, range: range)
        }
        attrString.fixAttributes(in: range)
        attrString.endEditing()

        if entry.isRTFD {
            entry.rtfData = attrString.rtfd(from: range, documentAttributes: [:])
        } else {
            entry.rtfData = attrString.rtf(from: range, documentAttributes: [:])
        }
    }

    private func underlineStyle(from name: String?) -> Int {
        switch name?.lowercased() {
        case "single": return NSUnderlineStyle.single.rawValue
        case "thick":  return NSUnderlineStyle.thick.rawValue
        case "double": return NSUnderlineStyle.double.rawValue
        default:       return NSUnderlineStyle.init(rawValue: 0).rawValue  // none
        }
    }

    private func underlinePattern(from name: String?) -> Int {
        switch name?.lowercased() {
        case "dot":        return NSUnderlineStyle.patternDot.rawValue
        case "dash":       return NSUnderlineStyle.patternDash.rawValue
        case "dashdot":    return NSUnderlineStyle.patternDashDot.rawValue
        case "dashdotdot": return NSUnderlineStyle.patternDashDotDot.rawValue
        default:           return NSUnderlineStyle.patternSolid.rawValue
        }
    }
}
```

You will need a small `NSColor` extension that accepts CSS color names and hex strings. Check `legacy/Source/NaoAdditions/NSColor+String.{h,m}` for the exact set of color names supported and replicate that logic.

**Verification:** Unit test `ScriptEngine.run(script:clipText:clip:)` with a simple script like `"return clipText.toUpperCase()"` and assert the result is the uppercased input.

---

## Phase 2 — Data Layer

Phase 2 wires persistence and the service actors. At the end of Phase 2, the app can load, store, and observe clips and snippets using SwiftData, with existing user data migrated.

---

### Task 2.1 — ModelContainer Setup

**File:** `Sources/App/ClipMenuApp.swift`

```swift
import SwiftUI
import SwiftData

@main
struct ClipMenuApp: App {
    let container: ModelContainer = {
        let schema = Schema([
            ClipEntry.self,
            SnippetFolder.self,
            Snippet.self,
            ActionNode.self
        ])
        let config = ModelConfiguration("ClipMenu", schema: schema, isStoredInMemoryOnly: false)
        return try! ModelContainer(for: schema, configurations: config)
    }()

    var body: some Scene {
        // Scenes are wired in Phase 3.
        // For Phase 2, use a placeholder WindowGroup for testing.
        WindowGroup("ClipMenu Debug") {
            Text("Phase 2 in progress")
        }
        .modelContainer(container)
    }
}
```

SwiftData places the store at `~/Library/Application Support/ClipMenu/default.store` automatically when the `ModelConfiguration` name matches the app's application support subdirectory.

---

### Task 2.2 — Legacy Data Migration

**File:** `Sources/Migration/LegacyMigration.swift`

This class runs once on first launch after the modern version is installed. It is guarded by a `UserDefaults` bool key so it never runs twice.

```swift
import Foundation
import SwiftData

final class LegacyMigration {
    static let migrationCompletedKey = "CMModernMigrationCompleted"

    static func runIfNeeded(context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: migrationCompletedKey) else { return }
        migrateClips(context: context)
        migrateSnippets(context: context)
        migrateActions(context: context)
        UserDefaults.standard.set(true, forKey: migrationCompletedKey)
    }

    // MARK: - Clips (NSKeyedArchiver → SwiftData)

    private static func migrateClips(context: ModelContext) {
        let url = appSupportURL().appendingPathComponent("clips.data")
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        // NSKeyedUnarchiver requires the legacy Clip class to be available.
        // Since the legacy Objective-C code is in the project under legacy/,
        // ensure Clip.{h,m} are compiled into the target (add to target membership).
        NSKeyedUnarchiver.setClass(LegacyClip.self, forClassName: "Clip")
        guard let clips = NSKeyedUnarchiver.unarchiveObject(withFile: url.path) as? [LegacyClip] else {
            return
        }

        for legacy in clips {
            let entry = ClipEntry()
            entry.createdAt = legacy.createdDate ?? .now
            entry.lastUsedAt = legacy.lastUsedDate ?? .now
            entry.types = legacy.types as? [String] ?? []
            entry.stringValue = legacy.stringValue
            entry.rtfData = legacy.rtfData
            entry.isRTFD = (legacy.types as? [String] ?? []).contains("NeXT RTFD pasteboard type")
            entry.pdfData = legacy.pdf
            entry.filenames = legacy.filenames as? [String]
            entry.urlStrings = legacy.url as? [String]
            if let image = legacy.image {
                entry.imageData = image.tiffRepresentation
            }
            context.insert(entry)
        }

        try? context.save()
        try? FileManager.default.removeItem(at: url)
    }
```

**Note on `LegacyClip`:** Rather than rewriting the NSCoder deserialization logic, add the legacy `Clip.h` and `Clip.m` files to the new target under the name `LegacyClip` (rename the class in the header, or use a bridging alias). This ensures the archived format is decoded correctly including all backward-compat keys (`lastAccessedDate`, `RTFD`, `RTF`). See `legacy/Source/Clip.m` `-initWithCoder:` for the exact key fallback chain.

```swift
    // MARK: - Snippets (Core Data XML → SwiftData)

    private static func migrateSnippets(context: ModelContext) {
        let storeURL = appSupportURL().appendingPathComponent("Snippets.xml")
        guard FileManager.default.fileExists(atPath: storeURL.path) else { return }

        // Load the legacy Core Data stack read-only
        guard let modelURL = Bundle.main.url(forResource: "Snippets", withExtension: "momd") else {
            return
        }
        let mom = NSManagedObjectModel(contentsOf: modelURL)!
        let psc = NSPersistentStoreCoordinator(managedObjectModel: mom)
        let options = [NSReadOnlyPersistentStoreOption: true]
        guard (try? psc.addPersistentStore(ofType: NSXMLStoreType,
                                           configurationName: nil,
                                           at: storeURL,
                                           options: options)) != nil else { return }

        let ctx = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        ctx.persistentStoreCoordinator = psc

        let folderRequest = NSFetchRequest<NSManagedObject>(entityName: "Folder")
        folderRequest.sortDescriptors = [NSSortDescriptor(key: "index", ascending: true)]
        guard let folders = try? ctx.fetch(folderRequest) else { return }

        for legacyFolder in folders {
            let folder = SnippetFolder(title: legacyFolder.value(forKey: "title") as? String ?? "")
            folder.isEnabled = legacyFolder.value(forKey: "enabled") as? Bool ?? true
            folder.sortIndex = legacyFolder.value(forKey: "index") as? Int ?? 0

            let snippetSet = (legacyFolder.value(forKey: "snippets") as? NSSet)?
                .allObjects as? [NSManagedObject] ?? []
            let sorted = snippetSet.sorted {
                ($0.value(forKey: "index") as? Int ?? 0) < ($1.value(forKey: "index") as? Int ?? 0)
            }

            for legacySnippet in sorted {
                let snippet = Snippet(
                    title: legacySnippet.value(forKey: "title") as? String ?? "",
                    content: legacySnippet.value(forKey: "content") as? String ?? ""
                )
                snippet.isEnabled = legacySnippet.value(forKey: "enabled") as? Bool ?? true
                snippet.sortIndex = legacySnippet.value(forKey: "index") as? Int ?? 0
                snippet.folder = folder
                folder.snippets.append(snippet)
                context.insert(snippet)
            }
            context.insert(folder)
        }

        try? context.save()
        try? FileManager.default.removeItem(at: storeURL)
    }

    // MARK: - Actions (plist → SwiftData)

    private static func migrateActions(context: ModelContext) {
        let url = appSupportURL().appendingPathComponent("actions.plist")
        guard FileManager.default.fileExists(atPath: url.path),
              let array = NSArray(contentsOf: url) as? [[String: Any]] else { return }

        for (idx, dict) in array.enumerated() {
            if let node = actionNode(from: dict, index: idx) {
                context.insert(node)
            }
        }
        try? context.save()
        try? FileManager.default.removeItem(at: url)
    }

    private static func actionNode(from dict: [String: Any], index: Int) -> ActionNode? {
        guard let title = dict["title"] as? String else { return nil }
        let isLeaf = dict["isLeaf"] as? Bool ?? false
        let node = ActionNode(title: title, isLeaf: isLeaf)
        node.sortIndex = index

        if isLeaf, let action = dict["action"] as? [String: Any] {
            node.actionType = action["type"] as? String
            node.actionName = action["name"] as? String
            node.scriptPath = action["path"] as? String
        }

        if let children = dict["children"] as? [[String: Any]] {
            for (childIdx, childDict) in children.enumerated() {
                if let childNode = actionNode(from: childDict, index: childIdx) {
                    node.children.append(childNode)
                    context.insert(childNode)
                }
            }
        }
        return node
    }

    // MARK: - Helpers

    private static func appSupportURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!.appendingPathComponent("ClipMenu")
    }
}
```

**Note:** The legacy `actions.plist` key structure for each node is documented in `doc/features.md` § "Persistence" under ActionController. Keys are `title`, `isLeaf`, `children` (array), and `action` (dict with `type`/`name`/`path`). Read `legacy/Source/ActionController.m` `-dictionaryRepresentationForNode:` if you need to verify the exact serialization format.

**Verification:** Run the migration against a copy of a real user's `~/Library/Application Support/ClipMenu/` directory and assert:
1. `ClipEntry` count matches the number of clips in the old `clips.data`.
2. Each `SnippetFolder` and `Snippet` exists with correct titles and content.
3. The three legacy files are deleted after migration.
4. Running `runIfNeeded` a second time is a no-op.

---

### Task 2.3 — ClipsService Actor

**File:** `Sources/Services/ClipsService.swift`

```swift
import SwiftData
import AppKit
import Combine

actor ClipsService {
    private let context: ModelContext
    private let monitor: ClipboardMonitor
    private let exclusionService: AppExclusionService
    private let settings: ClipMenuSettings
    private var cancellables = Set<AnyCancellable>()

    // Published for UI observation — bridged to MainActor via notification
    nonisolated let clipsDidChange = PassthroughSubject<Void, Never>()

    init(context: ModelContext, monitor: ClipboardMonitor,
         exclusionService: AppExclusionService, settings: ClipMenuSettings) {
        self.context = context
        self.monitor = monitor
        self.exclusionService = exclusionService
        self.settings = settings
    }

    func start() {
        monitor.clipChanged
            .receive(on: DispatchQueue.main)
            .sink { [weak self] pasteboard in
                Task { await self?.handlePasteboardChange(pasteboard) }
            }
            .store(in: &cancellables)
        monitor.start()
    }

    func stop() {
        monitor.stop()
    }

    // MARK: - Pasteboard handling

    private func handlePasteboardChange(_ pasteboard: NSPasteboard) async {
        guard !exclusionService.frontmostAppIsExcluded() else { return }

        guard let entry = makeEntry(from: pasteboard) else { return }

        // Duplicate check: compare contentHash
        let hash = entry.contentHash
        let descriptor = FetchDescriptor<ClipEntry>()
        let existing = (try? context.fetch(descriptor))?.first(where: { $0.contentHash == hash })
        if let dupe = existing {
            dupe.lastUsedAt = .now
            try? context.save()
            await notifyChange()
            return
        }

        context.insert(entry)
        trimHistory()
        try? context.save()
        await notifyChange()
    }

    private func makeEntry(from pasteboard: NSPasteboard) -> ClipEntry? {
        let supportedTypes = availableTypes().filter { type in
            settings.storeTypesDict[typeName(for: type)] ?? true
        }
        let presentTypes = supportedTypes.filter { pasteboard.data(forType: .init($0)) != nil }
        guard !presentTypes.isEmpty else { return nil }

        let entry = ClipEntry()
        entry.types = presentTypes

        for type in presentTypes {
            let pbType = NSPasteboard.PasteboardType(type)
            let data = pasteboard.data(forType: pbType)
            switch type {
            case "public.utf8-plain-text", "NSStringPboardType":
                entry.stringValue = pasteboard.string(forType: pbType)
            case "com.apple.flat-rtfd", "NeXT RTFD pasteboard type":
                entry.rtfData = data; entry.isRTFD = true
            case "com.apple.rtf", "NeXT Rich Text Format v1.0 pasteboard type":
                entry.rtfData = data
            case "com.adobe.pdf", "Apple PDF pasteboard type":
                entry.pdfData = data
            case "NSFilenamesPboardType":
                entry.filenames = pasteboard.propertyList(forType: pbType) as? [String]
            case "public.url", "Apple URL pasteboard type":
                entry.urlStrings = [pasteboard.string(forType: pbType) ?? ""]
            case "public.tiff", "NeXT TIFF v4.0 pasteboard type",
                 "Apple PICT pasteboard type":
                entry.imageData = data
            default: break
            }
        }
        return entry
    }

    // MARK: - History management

    private func trimHistory() {
        let descriptor = FetchDescriptor<ClipEntry>(
            sortBy: [SortDescriptor(\.lastUsedAt, order: .reverse)]
        )
        guard let all = try? context.fetch(descriptor), all.count > settings.maxHistorySize else {
            return
        }
        for entry in all.dropFirst(settings.maxHistorySize) {
            context.delete(entry)
        }
    }

    // MARK: - CRUD

    func sortedClips() throws -> [ClipEntry] {
        let sortKey = settings.reorderClipsAfterPasting ? \ClipEntry.lastUsedAt : \ClipEntry.createdAt
        let descriptor = FetchDescriptor<ClipEntry>(
            sortBy: [SortDescriptor(sortKey, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    func copyToPasteboard(_ entry: ClipEntry) {
        let pb = NSPasteboard.general
        pb.clearContents()
        for type in entry.types {
            let pbType = NSPasteboard.PasteboardType(type)
            if let data = dataForType(type, entry: entry) {
                pb.setData(data, forType: pbType)
            }
        }
        if settings.reorderClipsAfterPasting {
            entry.lastUsedAt = .now
            try? context.save()
        }
    }

    func copyStringToPasteboard(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    func remove(_ entry: ClipEntry) {
        context.delete(entry)
        try? context.save()
        Task { await notifyChange() }
    }

    func clearAll() throws {
        let all = try context.fetch(FetchDescriptor<ClipEntry>())
        for entry in all { context.delete(entry) }
        try context.save()
        Task { await notifyChange() }
    }

    // MARK: - Export

    func exportAsText(separator: String, to url: URL) throws {
        let clips = try sortedClips().compactMap { $0.stringValue }
        let content = clips.joined(separator: separator)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    func exportAsFiles(to directory: URL) throws {
        let clips = try sortedClips().compactMap { $0.stringValue }
        for (i, text) in clips.enumerated() {
            let file = directory.appendingPathComponent("\(i + 1).txt")
            try text.write(to: file, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Private helpers

    private func notifyChange() async {
        await MainActor.run { clipsDidChange.send() }
    }

    private func availableTypes() -> [String] {
        // Match order from legacy/Source/Clip.m +availableTypes
        [
            "NSStringPboardType",
            "NeXT Rich Text Format v1.0 pasteboard type",
            "NeXT RTFD pasteboard type",
            "Apple PDF pasteboard type",
            "NSFilenamesPboardType",
            "Apple URL pasteboard type",
            "NeXT TIFF v4.0 pasteboard type",
            "Apple PICT pasteboard type"
        ]
    }

    private func typeName(for type: String) -> String {
        // Maps pasteboard type to the human-readable name used in CMPrefStoreTypesKey
        // See legacy/Source/Clip.m +availableTypeNames
        let map: [String: String] = [
            "NSStringPboardType": "String",
            "NeXT Rich Text Format v1.0 pasteboard type": "RTF",
            "NeXT RTFD pasteboard type": "RTFD",
            "Apple PDF pasteboard type": "PDF",
            "NSFilenamesPboardType": "Filenames",
            "Apple URL pasteboard type": "URL",
            "NeXT TIFF v4.0 pasteboard type": "TIFF",
            "Apple PICT pasteboard type": "PICT"
        ]
        return map[type] ?? type
    }

    private func dataForType(_ type: String, entry: ClipEntry) -> Data? {
        switch type {
        case "NSStringPboardType": return entry.stringValue?.data(using: .utf8)
        case "NeXT Rich Text Format v1.0 pasteboard type",
             "NeXT RTFD pasteboard type": return entry.rtfData
        case "Apple PDF pasteboard type": return entry.pdfData
        case "NeXT TIFF v4.0 pasteboard type",
             "Apple PICT pasteboard type": return entry.imageData
        default: return nil
        }
    }
}
```

**Note on `storeTypesDict`:** Add a computed property to `ClipMenuSettings` that decodes the `CMPrefStoreTypesKey` dictionary (stored as JSON-encoded `[String: Bool]`) into a `[String: Bool]` Swift dict keyed by human-readable type names (String, RTF, RTFD, PDF, Filenames, URL, TIFF, PICT). Default is all `true`.

**Verification:**
1. Unit test `makeEntry(from:)` with a mock pasteboard containing a known string.
2. Unit test `trimHistory()` confirms that after inserting 25 entries with `maxHistorySize = 20`, only 20 remain.
3. Unit test `clearAll()` confirms the fetch returns empty.

---

### Task 2.4 — SnippetService Actor

**File:** `Sources/Services/SnippetService.swift`

```swift
import SwiftData

actor SnippetService {
    private let context: ModelContext

    init(context: ModelContext) { self.context = context }

    func folders(enabledOnly: Bool = false) throws -> [SnippetFolder] {
        var descriptor = FetchDescriptor<SnippetFolder>(
            sortBy: [SortDescriptor(\.sortIndex)]
        )
        if enabledOnly {
            descriptor.predicate = #Predicate { $0.isEnabled }
        }
        return try context.fetch(descriptor)
    }

    func addFolder(title: String) -> SnippetFolder {
        let folder = SnippetFolder(title: title)
        context.insert(folder)
        try? context.save()
        return folder
    }

    func remove(_ folder: SnippetFolder) {
        context.delete(folder)
        try? context.save()
    }

    func addSnippet(title: String, content: String, to folder: SnippetFolder) -> Snippet {
        let snippet = Snippet(title: title, content: content)
        snippet.folder = folder
        folder.snippets.append(snippet)
        context.insert(snippet)
        try? context.save()
        return snippet
    }

    func remove(_ snippet: Snippet) {
        context.delete(snippet)
        try? context.save()
    }

    // MARK: - XML Import/Export
    // Format documented in doc/features.md § "Import/Export (XML)"

    func exportXML(to url: URL) throws {
        let allFolders = try folders()
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<folders>\n"
        for folder in allFolders {
            xml += "  <folder>\n"
            xml += "    <title>\(folder.title.xmlEscaped)</title>\n"
            xml += "    <snippets>\n"
            for snippet in folder.snippets.sorted(by: { $0.sortIndex < $1.sortIndex }) {
                xml += "      <snippet>\n"
                xml += "        <title>\(snippet.title.xmlEscaped)</title>\n"
                xml += "        <content>\(snippet.content.xmlEscaped)</content>\n"
                xml += "      </snippet>\n"
            }
            xml += "    </snippets>\n"
            xml += "  </folder>\n"
        }
        xml += "</folders>"
        try xml.write(to: url, atomically: true, encoding: .utf8)
    }

    func importXML(from url: URL) throws {
        let data = try Data(contentsOf: url)
        let parser = SnippetXMLParser(data: data)
        try parser.parse()
        for folderData in parser.folders {
            let folder = SnippetFolder(title: folderData.title)
            context.insert(folder)
            for (idx, snippetData) in folderData.snippets.enumerated() {
                let snippet = Snippet(title: snippetData.title, content: snippetData.content)
                snippet.sortIndex = idx
                snippet.folder = folder
                folder.snippets.append(snippet)
                context.insert(snippet)
            }
        }
        try context.save()
    }
}
```

Add a `SnippetXMLParser` class that wraps `XMLParser` and produces a simple `[(title: String, snippets: [(title: String, content: String)])]` structure. Follow the element names from `doc/features.md` § "Import/Export (XML)".

Add a `String.xmlEscaped` extension that escapes `<`, `>`, `&`, `"`, `'`.

---

### Task 2.5 — ActionService Actor

**File:** `Sources/Services/ActionService.swift`

```swift
import SwiftData
import Foundation

actor ActionService {
    private let context: ModelContext
    private let engine: ScriptEngine
    private let settings: ClipMenuSettings

    init(context: ModelContext, engine: ScriptEngine, settings: ClipMenuSettings) {
        self.context = context
        self.engine = engine
        self.settings = settings
    }

    func loadActions() throws {
        // If the DB already has actions, skip discovery
        let existing = try context.fetch(FetchDescriptor<ActionNode>())
        guard existing.isEmpty else { return }
        prepareDefaultActions()
    }

    // MARK: - Built-in actions
    // Keep this list in sync with legacy/Source/BuiltInActionController.m

    func builtinActions() -> [ActionNode] {
        [
            makeBuiltin(title: "Remove",             name: "removeAction"),
            makeBuiltin(title: "Paste as Plain Text", name: "pasteAsPlainText"),
            makeBuiltin(title: "Paste as File Path",  name: "pasteAsFilePath"),
            makeBuiltin(title: "Paste as HFS Path",   name: "pasteAsHFSFilePath")
        ]
    }

    // MARK: - Script execution

    func invokeScript(path: String, on entry: ClipEntry) -> ClipEntry? {
        guard let source = try? String(contentsOfFile: path) else { return nil }
        let clip = ScriptableClip(entry: entry)
        guard let resultText = engine.run(script: source, clipText: entry.stringValue ?? "", clip: clip) else {
            return nil
        }
        let result = ClipEntry()
        result.stringValue = resultText
        result.types = ["NSStringPboardType"]
        return result
    }

    // MARK: - Built-in execution

    func performBuiltin(name: String, on entry: ClipEntry) -> ClipEntry? {
        switch name {
        case "pasteAsPlainText":
            guard let text = entry.stringValue else { return nil }
            let plain = ClipEntry(); plain.stringValue = text; plain.types = ["NSStringPboardType"]
            return plain
        case "pasteAsFilePath":
            guard let files = entry.filenames else { return nil }
            let text = files.joined(separator: "\n")
            let result = ClipEntry(); result.stringValue = text; result.types = ["NSStringPboardType"]
            return result
        case "pasteAsHFSFilePath":
            guard let files = entry.filenames else { return nil }
            let hfsPaths = files.compactMap { posixPath -> String? in
                let url = URL(fileURLWithPath: posixPath) as CFURL
                return CFURLCopyFileSystemPath(url, .hfsStyle) as String?
            }
            let text = hfsPaths.joined(separator: "\n")
            let result = ClipEntry(); result.stringValue = text; result.types = ["NSStringPboardType"]
            return result
        default:
            return nil
        }
    }

    // MARK: - Private

    private func makeBuiltin(title: String, name: String) -> ActionNode {
        let node = ActionNode(title: title, isLeaf: true)
        node.actionType = "builtin"
        node.actionName = name
        return node
    }

    private func prepareDefaultActions() {
        // Built-ins
        for node in builtinActions() {
            context.insert(node)
        }
        // Bundled scripts: walk ClipMenu.app/Contents/Resources/script/action/
        if let resourceURL = Bundle.main.resourceURL?.appendingPathComponent("script/action") {
            let nodes = scriptNodes(in: resourceURL, startIndex: 10)
            nodes.forEach { context.insert($0) }
        }
        // User scripts
        let userURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("ClipMenu/script/action")
        if let userURL {
            let nodes = scriptNodes(in: userURL, startIndex: 1000)
            nodes.forEach { context.insert($0) }
        }
        try? context.save()
    }

    private func scriptNodes(in directory: URL, startIndex: Int) -> [ActionNode] {
        // Recursively walks the directory. Subdirectories → folder nodes. .js files → leaf nodes.
        // This replicates the behavior of legacy/Source/ActionController.m
        // -_prepareBundledScriptActionNodes and -_prepareUsersScriptActionNodes.
        var results: [ActionNode] = []
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]) else { return [] }

        let sorted = contents.sorted { $0.lastPathComponent < $1.lastPathComponent }
        for (idx, url) in sorted.enumerated() {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDir {
                let folder = ActionNode(title: url.lastPathComponent, isLeaf: false)
                folder.sortIndex = startIndex + idx
                folder.children = scriptNodes(in: url, startIndex: 0)
                results.append(folder)
            } else if url.pathExtension == "js" {
                let node = ActionNode(title: url.deletingPathExtension().lastPathComponent, isLeaf: true)
                node.actionType = "javaScript"
                node.scriptPath = url.path
                node.sortIndex = startIndex + idx
                results.append(node)
            }
        }
        return results
    }
}
```

---

### Task 2.6 — App Entry Point Wiring

**File:** `Sources/App/AppDelegate.swift`

```swift
import AppKit
import SwiftData

final class AppDelegate: NSObject, NSApplicationDelegate {
    var container: ModelContainer!
    var clipsService: ClipsService!
    var snippetService: SnippetService!
    var actionService: ActionService!
    var pasteService = PasteService()
    var loginItemService = LoginItemService()
    var settings = ClipMenuSettings()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            let ctx = container.mainContext
            LegacyMigration.runIfNeeded(context: ctx)

            let monitor = ClipboardMonitor()
            let exclusionService = AppExclusionService()
            exclusionService.update(from: settings)

            clipsService = ClipsService(context: ctx, monitor: monitor,
                                        exclusionService: exclusionService, settings: settings)
            snippetService = SnippetService(context: ctx)
            actionService = ActionService(context: ctx, engine: ScriptEngine(), settings: settings)

            async let c: () = clipsService.start()
            async let a: () = actionService.loadActions()
            _ = await (c, a)

            // Phase 3 will add hotkey registration here.
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if settings.saveHistoryOnQuit {
            // SwiftData persists on its own; this is a no-op unless you want a final flush.
            try? container.mainContext.save()
        }
        // Phase 3 will unregister hotkeys here.
    }
}
```

**Verification:** Launch the app. Confirm:
1. Migration runs once (legacy files are gone, SwiftData store is populated).
2. Copying text to the clipboard results in a new `ClipEntry` in the SwiftData store (verify with a debug print in `handlePasteboardChange`).
3. The excluded app list is respected.

---

## Phase 3 — Full Modernisation (UI & Hotkeys)

Phase 3 replaces the NSMenu-based UI with SwiftUI, wires global hotkeys, and completes the preferences window. By the end of Phase 3, the app is fully functional with no legacy API dependencies.

---

### Task 3.1 — MenuBarExtra and App Scenes

**File:** `Sources/App/ClipMenuApp.swift` (update)

```swift
import SwiftUI
import SwiftData

@main
struct ClipMenuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    let container: ModelContainer = { /* same as before */ }()

    var body: some Scene {
        MenuBarExtra {
            ClipMenuView()
                .environmentObject(delegate.clipsService)
                .environmentObject(delegate.snippetService)
                .environmentObject(delegate.actionService)
                .environmentObject(delegate.settings)
        } label: {
            Image("StatusMenuIcon")
        }
        .menuBarExtraStyle(.menu)

        Settings {
            PreferencesView()
                .environmentObject(delegate.settings)
                .environmentObject(delegate.loginItemService)
        }
    }
}
```

Pass `container` to `AppDelegate` from `@NSApplicationDelegateAdaptor` init, or inject it via `environmentObject`. The `@Query` macro in child views requires the `modelContainer` environment, set via `.modelContainer(container)` on the scene.

---

### Task 3.2 — ClipMenuView

**File:** `Sources/UI/ClipMenuView.swift`

This view implements all menu construction rules from `doc/features.md` § "MenuController":

```swift
import SwiftUI
import SwiftData

struct ClipMenuView: View {
    @Query(sort: \ClipEntry.lastUsedAt, order: .reverse) var clips: [ClipEntry]
    @Query(sort: \SnippetFolder.sortIndex) var folders: [SnippetFolder]
    @EnvironmentObject var settings: ClipMenuSettings
    @EnvironmentObject var clipsService: ClipsService
    @EnvironmentObject var actionService: ActionService
    @State private var activeModifiers: NSEvent.ModifierFlags = []

    var body: some View {
        // "Open Snippet Editor" and "Preferences" are at the top
        Button("Open Snippet Editor") { openSnippetEditor() }
        SettingsLink { Text("Preferences…") }
        Divider()

        // Snippets above clips (if configured)
        if settings.snippetPosition == 0 {
            SnippetSection(folders: folders.filter(\.isEnabled))
            Divider()
        }

        // Clips section
        clipsSection

        // Snippets below clips (if configured)
        if settings.snippetPosition == 1 {
            Divider()
            SnippetSection(folders: folders.filter(\.isEnabled))
        }

        if settings.showClearHistory {
            Divider()
            Button("Clear History") { clearHistory() }
        }
    }

    @ViewBuilder
    private var clipsSection: some View {
        let inline = settings.numberOfItemsInline
        let perFolder = settings.numberOfItemsPerFolder
        let inlineClips = inline == 0 ? clips : Array(clips.prefix(inline))
        let folderClips = inline == 0 ? [] : Array(clips.dropFirst(inline))

        ForEach(Array(inlineClips.enumerated()), id: \.element.id) { index, clip in
            ClipMenuItem(clip: clip, number: listNumber(for: index), isInline: true)
        }

        if !folderClips.isEmpty {
            let groups = stride(from: 0, to: folderClips.count, by: perFolder).map {
                Array(folderClips[$0..<min($0 + perFolder, folderClips.count)])
            }
            ForEach(Array(groups.enumerated()), id: \.offset) { groupIndex, group in
                let start = inline + groupIndex * perFolder + 1
                let end = start + group.count - 1
                Menu("\(start)-\(end)") {
                    ForEach(Array(group.enumerated()), id: \.element.id) { idx, clip in
                        ClipMenuItem(clip: clip, number: listNumber(for: inline + groupIndex * perFolder + idx), isInline: false)
                    }
                }
            }
        }
    }

    private func listNumber(for index: Int) -> Int {
        // Implements CMPrefMenuItemsTitleStartWithZeroKey + wrap-at-10 logic from features.md
        let base = settings.numberingStartsAtZero ? index : index + 1
        if !settings.numberingStartsAtZero && base > 10 { return base % 10 }
        return base
    }

    private func clearHistory() {
        if settings.confirmBeforeClear {
            // Show confirmation alert
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("Clear History", comment: "")
            alert.informativeText = NSLocalizedString("Are you sure?", comment: "")
            alert.addButton(withTitle: NSLocalizedString("Clear", comment: ""))
            alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
            if alert.runModal() == .alertFirstButtonReturn {
                Task { try? await clipsService.clearAll() }
            }
        } else {
            Task { try? await clipsService.clearAll() }
        }
    }

    private func openSnippetEditor() {
        // Phase 3: open the SnippetEditorView in a window
        NSApp.sendAction(#selector(AppDelegate.openSnippetEditor), to: nil, from: nil)
    }
}
```

**File:** `Sources/UI/ClipMenuItem.swift`

This view implements all item rendering rules from `doc/features.md` § "Menu Item Construction":

```swift
import SwiftUI
import AppKit

struct ClipMenuItem: View {
    let clip: ClipEntry
    let number: Int
    let isInline: Bool

    @EnvironmentObject var settings: ClipMenuSettings
    @EnvironmentObject var clipsService: ClipsService
    @EnvironmentObject var actionService: ActionService

    var body: some View {
        Button(action: selectClip) {
            HStack {
                if settings.showTypeIcon, let icon = typeIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: CGFloat(settings.menuIconSize),
                               height: CGFloat(settings.menuIconSize))
                }
                if settings.showImageThumbnails, let thumb = thumbnail {
                    Image(nsImage: thumb)
                }
                Text(title)
                    .font(labelFont)
                if settings.showTypeLabels {
                    Text("[\(primaryTypeName)]")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .help(tooltip)
        .keyboardShortcut(keyEquivalent, modifiers: [])
    }

    // MARK: - Title

    private var title: String {
        var t = trimmedTitle
        if settings.numberedMenuItems {
            t = "\(number). \(t)"
        }
        return t
    }

    private var trimmedTitle: String {
        // Implement trimTitle() from features.md § "trimTitle()"
        let source = clip.stringValue ?? (clip.filenames?.first ?? "")
        let stripped = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstLine: String
        if let newline = stripped.firstIndex(of: "\n") {
            firstLine = String(stripped[..<newline])
        } else {
            firstLine = stripped
        }
        let max = settings.maxMenuItemTitleLength
        if firstLine.count > max {
            return String(firstLine.prefix(max - 3)) + "..."
        }
        return firstLine
    }

    // MARK: - Visual properties

    private var thumbnail: NSImage? {
        guard let data = clip.imageData, settings.showImageThumbnails else { return nil }
        guard let img = NSImage(data: data) else { return nil }
        return scaledImage(img, to: NSSize(width: CGFloat(settings.thumbnailWidth),
                                           height: CGFloat(settings.thumbnailHeight)))
    }

    private var typeIcon: NSImage? {
        // Use NSWorkspace to get a file type icon.
        // For each type, look up the icon file type setting in ClipMenuSettings.
        // Simplified: use a generic icon per type. For the full implementation,
        // read legacy/Source/Clip.m +fileTypeIconForPboardType: and replicate.
        return nil  // TODO: full icon lookup
    }

    private var primaryTypeName: String {
        let map: [String: String] = [
            "NSStringPboardType": "String",
            "NeXT Rich Text Format v1.0 pasteboard type": "RTF",
            "NeXT RTFD pasteboard type": "RTFD",
            "Apple PDF pasteboard type": "PDF",
            "NSFilenamesPboardType": "Filenames",
            "Apple URL pasteboard type": "URL",
            "NeXT TIFF v4.0 pasteboard type": "TIFF",
            "Apple PICT pasteboard type": "PICT"
        ]
        return clip.types.compactMap { map[$0] }.first ?? ""
    }

    private var tooltip: String {
        guard settings.showTooltips else { return "" }
        let text = clip.stringValue ?? clip.filenames?.joined(separator: "\n") ?? ""
        return String(text.prefix(settings.maxTooltipLength))
    }

    private var labelFont: Font {
        guard settings.overrideMenuFontSize else { return .body }
        let size = settings.fontSizeMode == 0
            ? CGFloat(settings.menuIconSize)
            : CGFloat(settings.manualFontSize)
        return .system(size: size)
    }

    private var keyEquivalent: KeyEquivalent? {
        guard settings.numericKeyEquivalents, number >= 1, number <= 10 else { return nil }
        let char = number == 10 ? "0" : "\(number)"
        return KeyEquivalent(char.first!)
    }

    // MARK: - Action

    private func selectClip() {
        Task {
            // Check modifier keys — if a modifier action is configured, invoke it
            let event = NSApp.currentEvent
            if let resultEntry = await applyModifierAction(clip: clip, event: event) {
                await clipsService.copyToPasteboard(resultEntry)
            } else {
                await clipsService.copyToPasteboard(clip)
            }
            PasteService().paste()
        }
    }

    private func applyModifierAction(clip: ClipEntry, event: NSEvent?) async -> ClipEntry? {
        // Read modifier flags and look up the configured behavior from settings.
        // Behavior strings: "" = no override, "popUpActionMenu" = show action menu,
        // or a JSON-encoded action dict.
        // This replicates _applyActionToTarget: from legacy/Source/AppController.m.
        // Full implementation: decode behavior string, show action popover if needed.
        return nil  // TODO
    }

    private func scaledImage(_ image: NSImage, to size: NSSize) -> NSImage {
        let ratio = min(size.width / image.size.width, size.height / image.size.height)
        let newSize = NSSize(width: image.size.width * ratio, height: image.size.height * ratio)
        let scaled = NSImage(size: newSize)
        scaled.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize))
        scaled.unlockFocus()
        return scaled
    }
}
```

---

### Task 3.3 — Snippet Section

**File:** `Sources/UI/SnippetSection.swift`

```swift
import SwiftUI

struct SnippetSection: View {
    let folders: [SnippetFolder]
    @EnvironmentObject var clipsService: ClipsService

    var body: some View {
        ForEach(folders) { folder in
            let enabledSnippets = folder.snippets.filter(\.isEnabled)
                                                 .sorted { $0.sortIndex < $1.sortIndex }
            if enabledSnippets.count == 1 {
                // Single snippet shown inline (no submenu)
                snippetButton(enabledSnippets[0])
            } else {
                Menu(folder.title) {
                    ForEach(enabledSnippets) { snippet in
                        snippetButton(snippet)
                    }
                }
            }
        }
    }

    private func snippetButton(_ snippet: Snippet) -> some View {
        Button(snippet.title) {
            Task {
                await clipsService.copyStringToPasteboard(snippet.content)
                PasteService().paste()
            }
        }
    }
}
```

---

### Task 3.4 — Global Hotkeys

**File:** `Sources/Infrastructure/HotkeyService.swift`

```swift
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    // Default combos match legacy PTHotKeys defaults from doc/features.md § "Default Key Combos"
    static let openClipMenu  = Self("openClipMenu",  default: .init(.v, modifiers: [.command, .shift]))
    static let openHistory   = Self("openHistory",   default: .init(.v, modifiers: [.command, .control]))
    static let openSnippets  = Self("openSnippets",  default: .init(.b, modifiers: [.command, .shift]))
}

final class HotkeyService {
    var onOpenClipMenu:  (() -> Void)?
    var onOpenHistory:   (() -> Void)?
    var onOpenSnippets:  (() -> Void)?

    func register() {
        KeyboardShortcuts.onKeyUp(for: .openClipMenu)  { [weak self] in self?.onOpenClipMenu?() }
        KeyboardShortcuts.onKeyUp(for: .openHistory)   { [weak self] in self?.onOpenHistory?() }
        KeyboardShortcuts.onKeyUp(for: .openSnippets)  { [weak self] in self?.onOpenSnippets?() }
    }

    func unregister() {
        KeyboardShortcuts.disable(.openClipMenu)
        KeyboardShortcuts.disable(.openHistory)
        KeyboardShortcuts.disable(.openSnippets)
    }
}
```

**Migration note for hotkey preferences:** The legacy app stores hotkeys in `CMPrefHotKeysKey` as a dict mapping identifier strings to `PTKeyCombo` plist dicts (keys `"keyCode"` and `"modifiers"` as integers). `KeyboardShortcuts` uses its own `UserDefaults` storage format. Write a one-time migration in `LegacyMigration` that reads the old dict, maps key codes to `KeyboardShortcuts.Shortcut`, and registers them via `KeyboardShortcuts.setShortcut(_:for:)`.

The PTKeyCombo key codes are HID/Carbon key codes. The `KeyboardShortcuts` package uses the same underlying key code values in its `KeyboardShortcuts.Key` enum. Map the three identifiers:
- `"ClipMenu"` → `.openClipMenu`
- `"HistoryMenu"` → `.openHistory`
- `"SnippetsMenu"` → `.openSnippets`

---

### Task 3.5 — Preferences Window

**File:** `Sources/UI/PreferencesView.swift`

```swift
import SwiftUI

struct PreferencesView: View {
    var body: some View {
        TabView {
            GeneralPrefsView()
                .tabItem { Label("General", systemImage: "gear") }
            MenuPrefsView()
                .tabItem { Label("Menu", systemImage: "list.bullet") }
            ActionsPrefsView()
                .tabItem { Label("Actions", systemImage: "bolt") }
            ShortcutsPrefsView()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
        }
        .frame(width: 520)
        .padding()
    }
}
```

Each tab view directly binds to `@EnvironmentObject var settings: ClipMenuSettings` using `@AppStorage` bindings. Implement each tab corresponding to the preference groups in `doc/features.md` § "Preferences Window Tabs":

- **GeneralPrefsView:** login item toggle (using `LoginItemService`), paste command, reorder, max history, autosave delay, save-on-quit, status item, store types checkboxes, exclude apps list with Add/Remove buttons.
- **MenuPrefsView:** max title length, inline/folder counts, numbering, labels, clear history, tooltips, font size, thumbnails, icons.
- **ActionsPrefsView:** enable toggle, four modifier-click pickers, invoke-immediately.
- **ShortcutsPrefsView:** Three `KeyboardShortcuts.Recorder` controls, one per hotkey name.

For the **exclude apps** add button, use `AppExclusionService.runningUserApps()` to show a picker and add the selected entry to `settings.excludeApps`.

---

### Task 3.6 — Snippet Editor Window

The snippet editor is a separate window opened from the "Open Snippet Editor" menu item. Implement it as a SwiftUI `View` presented via `openWindow(id:)` (or via `NSApp.sendAction`/`NSWindowController`). It should replicate the functionality of `legacy/Source/SnippetEditorController`:

- Outline view of folders and snippets (use `List` with disclosure groups).
- Add/remove folders and snippets.
- Edit title and content inline.
- Import/Export XML buttons (calls `SnippetService.exportXML`/`importXML`).
- Enable/disable toggles per folder and snippet.

---

### Task 3.7 — Bundled JS Scripts

Copy the contents of `legacy/resource/script/` into the new Xcode project under `Resources/script/` and add them to the app target's bundle resources. The directory structure must be preserved:

```
Resources/
└── script/
    ├── action/
    │   ├── Case/
    │   │   ├── lowercase.js
    │   │   ├── uppercase.js
    │   │   └── capitalize.js
    │   ├── ... (all other categories)
    └── lib/
        ├── inflection.js
        ├── showdown.js
        └── fhconvert.js
```

The `ActionService.prepareDefaultActions()` already looks for these at `Bundle.main.resourceURL/script/action/`. No code changes needed.

---

## Verification Checklist

Use this checklist to confirm the migration is complete and correct before shipping.

### Data Integrity
- [ ] All clips from `clips.data` appear in SwiftData after migration.
- [ ] Clip `createdAt`, `lastUsedAt`, `types`, `stringValue`, `rtfData`, `pdfData`, `filenames`, `urlStrings`, `imageData` all migrate correctly.
- [ ] All snippet folders and snippets migrate with correct titles, content, enabled states, and sort order.
- [ ] All action nodes migrate with correct tree structure.
- [ ] Migration is idempotent: running it twice makes no changes.
- [ ] Legacy files (`clips.data`, `Snippets.xml`, `actions.plist`) are deleted after migration.

### Clipboard Monitoring
- [ ] Copying text triggers a new `ClipEntry` within 100 ms.
- [ ] Copying from an excluded app does not add a clip.
- [ ] Copying the same text twice updates `lastUsedAt` rather than adding a duplicate.
- [ ] History trimming removes oldest entries when count exceeds `maxHistorySize`.

### Menu Behavior
- [ ] Menu reflects current clips immediately after a copy.
- [ ] Inline clip count and folder grouping follow preference settings.
- [ ] Item numbering starts at 0 or 1 per setting, wraps at 10 correctly.
- [ ] Tooltips show the correct truncated text.
- [ ] Thumbnails appear for image clips.
- [ ] Selecting a clip pastes it into the previously active app.

### Snippets
- [ ] Enabled snippets appear in the menu at the configured position (above/below/hidden).
- [ ] Selecting a snippet pastes it into the previously active app.
- [ ] Snippet editor shows all folders and snippets.
- [ ] XML export round-trips through XML import without data loss.

### Actions
- [ ] All four built-in actions work correctly (Remove, Paste as Plain Text, Paste as File Path, Paste as HFS Path).
- [ ] Bundled JS scripts appear in the action menu and produce correct output.
- [ ] `ClipMenu.require()` loads a library and makes it available to the script.
- [ ] A script that throws shows an error alert and does not crash the app.

### Hotkeys
- [ ] Default combos (`Cmd+Shift+V`, `Cmd+Ctrl+V`, `Cmd+Shift+B`) open the correct menus.
- [ ] Hotkeys can be rebound in preferences and the new binding takes effect immediately.
- [ ] Legacy hotkey preferences are migrated to `KeyboardShortcuts` format.

### Preferences
- [ ] All 40+ preference keys read the correct values from `UserDefaults` after upgrading.
- [ ] Changing a preference takes effect immediately without restarting.
- [ ] Login item toggle registers/unregisters via `SMAppService`.

### Regressions to Watch
- [ ] RTF and RTFD clips render correctly in the menu (attributed title, if applicable).
- [ ] PDF clips are stored and can be pasted back.
- [ ] File path clips show the filename and paste POSIX or HFS path correctly.
- [ ] Modifier-click behaviors (Ctrl, Shift, Option, Cmd) pop the action menu or invoke the configured action.
- [ ] The frontmost app is correctly restored after a paste.

---

## Reference

| Topic | Source |
|---|---|
| All feature behaviors | `doc/features.md` |
| All enhancement designs | `doc/enhancements.md` |
| Clip NSCoder keys | `legacy/Source/Clip.m` `-initWithCoder:` |
| Preference key strings | `legacy/Source/constants.h`, `legacy/Source/AppController.m` `+initialize` |
| JS bridge implementation | `legacy/Source/ScriptableClip.m`, `legacy/Source/ActionController.m` |
| Pasteboard type strings | `legacy/Source/Clip.m` `+availableTypes` |
| Menu construction rules | `legacy/Source/MenuController.m` |
| Built-in action selectors | `legacy/Source/BuiltInActionController.m` |
| Snippet XML format | `legacy/Source/SnippetEditorController.m`, `doc/features.md` § "Import/Export" |
| Hotkey default combos | `doc/features.md` § "Default Key Combos" |

---

## Phase 4 — Actions System

This phase completes the actions feature end-to-end: default data seeding, modifier-click dispatch, the preferences editor, and numeric key equivalents. It also includes a bug fix for the legacy snippets migration that was silently skipped in Phases 1–3.

---

### Bug Fix: Snippets Migration (prerequisite)

**File:** `Sources/Migration/LegacyMigration.swift`

`importSnippets()` has two bugs that make it silently no-op for every user:

1. `Bundle.main.url(forResource: "Snippets", withExtension: "momd")` always returns `nil` — `legacy/Snippets.xcdatamodel` was never added to `project.yml` sources and therefore is never compiled into the bundle.
2. Even if bundled, the extension is wrong: a flat `.xcdatamodel` compiles to `.mom`, not `.momd` (`.momd` is produced only by versioned `.xcdatamodeld` packages).

**Fix:** Replace the bundle model load with a programmatically constructed `NSManagedObjectModel`. The schema is simple and stable, so hardcoding it eliminates all bundle path dependencies. No changes to `project.yml` needed.

Replace the guard block that loads the model from bundle:

```swift
// DELETE these lines:
guard let modelURL = Bundle.main.url(forResource: "Snippets", withExtension: "momd") else {
    return
}
guard let mom = NSManagedObjectModel(contentsOf: modelURL) else { return }

// REPLACE WITH:
let mom = makeLegacySnippetModel()
```

Add this private helper to `LegacyMigration`:

```swift
private static func makeLegacySnippetModel() -> NSManagedObjectModel {
    let model = NSManagedObjectModel()

    let folderEntity = NSEntityDescription()
    folderEntity.name = "Folder"
    folderEntity.managedObjectClassName = "NSManagedObject"

    let snippetEntity = NSEntityDescription()
    snippetEntity.name = "Snippet"
    snippetEntity.managedObjectClassName = "NSManagedObject"

    func attr(_ name: String, _ type: NSAttributeType) -> NSAttributeDescription {
        let a = NSAttributeDescription()
        a.name = name; a.attributeType = type; a.isOptional = true
        return a
    }

    folderEntity.properties = [
        attr("title", .stringAttributeType),
        attr("index", .integer32AttributeType),
        attr("enabled", .booleanAttributeType),
    ]
    snippetEntity.properties = [
        attr("title", .stringAttributeType),
        attr("content", .stringAttributeType),
        attr("index", .integer32AttributeType),
        attr("enabled", .booleanAttributeType),
    ]

    let folderSnippets = NSRelationshipDescription()
    folderSnippets.name = "snippets"
    folderSnippets.isOptional = true
    folderSnippets.minCount = 0
    folderSnippets.maxCount = 0  // to-many
    folderSnippets.destinationEntity = snippetEntity

    let snippetFolder = NSRelationshipDescription()
    snippetFolder.name = "folder"
    snippetFolder.isOptional = true
    snippetFolder.minCount = 0
    snippetFolder.maxCount = 1   // to-one
    snippetFolder.destinationEntity = folderEntity

    folderSnippets.inverseRelationship = snippetFolder
    snippetFolder.inverseRelationship = folderSnippets

    folderEntity.properties += [folderSnippets]
    snippetEntity.properties += [snippetFolder]

    model.entities = [folderEntity, snippetEntity]
    return model
}
```

**Verification:** Copy a `Snippets.xml` from `~/Library/Application Support/ClipMenu/` on a machine that ran the legacy app → delete the `legacyMigrationCompleted` key from UserDefaults (or use `defaults delete app.eetr.ClipMenu legacyMigrationCompleted`) → relaunch → confirm folders and snippets appear in the Snippets prefs editor.

---

### Step 4A: Default Action Seeding

**New file:** `Sources/Services/DefaultActionSeeder.swift`  
**Modified files:** `Sources/App/AppDelegate.swift`, `project.yml`, `migration_status.md`

On a fresh install there is no `actions.plist` to migrate and `ActionService.availableActions()` returns empty. This step seeds a sensible default action tree into SwiftData on first launch.

**Bundled scripts:** Copy the full `legacy/resource/script/` tree (subdirs `action/` and `lib/`) into `Resources/scripts/` in the new project root. Add a folder reference in `project.yml` so XcodeGen includes it in the Copy Bundle Resources build phase:

```yaml
sources:
  - path: Sources
  - path: Assets.xcassets
    buildPhase: resources
  - path: Resources/scripts
    buildPhase: resources
    type: folder
```

**`DefaultActionSeeder.swift`:**

```swift
import SwiftData
import Foundation

struct DefaultActionSeeder {

    static func seedIfNeeded(in context: ModelContext) {
        let count = (try? context.fetchCount(FetchDescriptor<ActionNode>())) ?? 0
        guard count == 0 else { return }
        seed(in: context)
    }

    // MARK: - Private

    private static func seed(in context: ModelContext) {
        var idx = 0

        func leaf(title: String, type: String, name: String? = nil, path: String? = nil) -> ActionNode {
            let node = ActionNode(title: title, isLeaf: true, sortIndex: idx)
            idx += 1
            node.actionType = type
            node.actionName = name
            node.scriptPath = path ?? (type == "javaScript" ? bundlePath(for: title) : nil)
            return node
        }

        func folder(title: String, children: [ActionNode]) -> ActionNode {
            let node = ActionNode(title: title, isLeaf: false, sortIndex: idx)
            idx += 1
            for (i, child) in children.enumerated() {
                child.sortIndex = i
                child.parent = node
            }
            node.children = children
            return node
        }

        let roots: [ActionNode] = [
            leaf(title: "Paste as Plain Text", type: "builtin", name: "pasteAsPlainText"),
            leaf(title: "Paste as File Path",  type: "builtin", name: "pasteAsFilePath"),
            leaf(title: "Paste as HFS File Path", type: "builtin", name: "pasteAsHFSFilePath"),
            leaf(title: "Remove",              type: "builtin", name: "removeAction"),
            folder(title: "Case", children: [
                leaf(title: "Capitalize",  type: "javaScript"),
                leaf(title: "Title Case",  type: "javaScript"),
                leaf(title: "UPPERCASE",   type: "javaScript"),
                leaf(title: "lowercase",   type: "javaScript"),
            ]),
            folder(title: "Trim", children: [
                leaf(title: "Trim",  type: "javaScript"),
                leaf(title: "LTrim", type: "javaScript"),
                leaf(title: "RTrim", type: "javaScript"),
            ]),
            folder(title: "Crypt", children: [
                leaf(title: "Encode to Base64",    type: "javaScript"),
                leaf(title: "Decode from Base64",  type: "javaScript"),
                leaf(title: "Calculate MD5 hash",  type: "javaScript"),
                leaf(title: "Calculate SHA-1 hash", type: "javaScript"),
            ]),
            folder(title: "HTML", children: [
                leaf(title: "Escape HTML characters",   type: "javaScript"),
                leaf(title: "Unescape HTML characters", type: "javaScript"),
                leaf(title: "Encode URI component",     type: "javaScript"),
                leaf(title: "Decode URI component",     type: "javaScript"),
                leaf(title: "Strip Tags",               type: "javaScript"),
            ]),
            leaf(title: "Collapse Spaces", type: "javaScript"),
            leaf(title: "Reverse",         type: "javaScript"),
            folder(title: "Surround with", children: [
                leaf(title: "\" \"", type: "javaScript"),
                leaf(title: "' '",   type: "javaScript"),
                leaf(title: "( )",   type: "javaScript"),
                leaf(title: "[ ]",   type: "javaScript"),
                leaf(title: "{ }",   type: "javaScript"),
                leaf(title: "< >",   type: "javaScript"),
                leaf(title: "` `",   type: "javaScript"),
            ]),
        ]

        for node in roots { context.insert(node) }
        try? context.save()
    }

    // MARK: - Script path resolution
    //
    // Walk the bundle scripts/action/ tree to find a .js file matching the node title.
    // For short scripts, prefer reading content inline (scriptContent) over scriptPath
    // to avoid path fragility when the app bundle moves.

    private static func bundlePath(for title: String) -> String? {
        guard let base = Bundle.main.resourceURL?
            .appendingPathComponent("scripts/action") else { return nil }
        // Search subdirectories for a file named "<title>.js"
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: base,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]) else { return nil }
        for case let url as URL in enumerator
            where url.deletingPathExtension().lastPathComponent == title
                && url.pathExtension == "js" {
            return url.path
        }
        return nil
    }
}
```

**AppDelegate integration** — inside `applicationDidFinishLaunching`, after the SwiftData container is ready and `LegacyMigration.run()` has been called:

```swift
DefaultActionSeeder.seedIfNeeded(in: context)
```

**ScriptEngine `require()` path:** `ScriptEngine.libSource(for:)` already searches `Bundle.main.resourceURL?.appendingPathComponent("script/lib")`. The bundled scripts are placed at `Resources/scripts/lib/`, so update the bundle search path in `ScriptEngine` to `scripts/lib` (note the plural `scripts`) to match the new location.

**Verification:** Delete the app container, build fresh → launch → open a clip → Control+click (if configured) → action menu shows 4 built-ins + JS folders.

---

### Step 4B: Modifier-Click Action Dispatch

**New file:** `Sources/UI/ActionMenuBuilder.swift`  
**Modified files:** `Sources/UI/ClipMenuItem.swift`, `Sources/Services/ActionService.swift`

#### ActionService additions

Add two methods to `ActionService` (existing `actor`):

```swift
/// Root-level nodes only (no parent), sorted by sortIndex.
func rootActions() async -> [ActionNode] {
    guard let context else { return [] }
    var desc = FetchDescriptor<ActionNode>(
        predicate: #Predicate { $0.parent == nil },
        sortBy: [SortDescriptor(\ActionNode.sortIndex)]
    )
    return (try? context.fetch(desc)) ?? []
}

func rootActionCount() async -> Int {
    guard let context else { return 0 }
    let desc = FetchDescriptor<ActionNode>(predicate: #Predicate { $0.parent == nil })
    return (try? context.fetchCount(desc)) ?? 0
}
```

#### ActionMenuBuilder

`ActionSection` is SwiftUI and cannot be embedded in an `NSMenu`. Extract shared NSMenu construction into a new helper:

**File:** `Sources/UI/ActionMenuBuilder.swift`

```swift
import AppKit

/// Builds a native NSMenu from an ActionNode tree for use in modifier-click popups.
///
/// Mirrors ActionSection rendering but produces NSMenu/NSMenuItem instead of SwiftUI views.
enum ActionMenuBuilder {

    static func makeMenu(
        from roots: [ActionNode],
        target: ClipEntry,
        service: ActionService
    ) -> NSMenu {
        let menu = NSMenu()
        for node in roots.filter(\.isEnabled).sorted(by: { $0.sortIndex < $1.sortIndex }) {
            menu.addItem(makeItem(for: node, target: target, service: service))
        }
        return menu
    }

    // MARK: - Private

    private static func makeItem(
        for node: ActionNode,
        target: ClipEntry,
        service: ActionService
    ) -> NSMenuItem {
        if node.isLeaf {
            let item = NSMenuItem(title: node.title, action: nil, keyEquivalent: "")
            item.representedObject = node
            // Use a block-based action via associated closure stored on the item
            item.target = ActionMenuTarget.shared
            item.action = #selector(ActionMenuTarget.perform(_:))
            ActionMenuTarget.shared.register(node: node, target: target, service: service)
            return item
        } else {
            let submenu = NSMenu(title: node.title)
            let children = node.children
                .filter(\.isEnabled)
                .sorted { $0.sortIndex < $1.sortIndex }
            for child in children where child.isLeaf {
                submenu.addItem(makeItem(for: child, target: target, service: service))
            }
            let item = NSMenuItem(title: node.title, action: nil, keyEquivalent: "")
            item.submenu = submenu
            return item
        }
    }
}

/// NSObject target that bridges NSMenuItem actions to async ActionService calls.
///
/// Uses a dictionary keyed by ActionNode.id so multiple menus can coexist.
final class ActionMenuTarget: NSObject {
    static let shared = ActionMenuTarget()
    private var handlers: [ObjectIdentifier: () -> Void] = [:]

    func register(node: ActionNode, target: ClipEntry, service: ActionService) {
        handlers[ObjectIdentifier(node)] = {
            Task { await service.perform(action: node, on: target) }
        }
    }

    @objc func perform(_ sender: NSMenuItem) {
        guard let node = sender.representedObject as? ActionNode else { return }
        handlers[ObjectIdentifier(node)]?()
    }
}
```

#### ClipMenuItem changes

Add `@Environment(\.actionService) private var actionService` and replace `select()`:

```swift
@Environment(\.actionService) private var actionService

private func select() {
    let flags = NSEvent.modifierFlags.intersection([.control, .shift, .option, .command])

    if settings.enableAction {
        let behavior: String
        switch flags {
        case .control: behavior = settings.controlClickBehavior
        case .shift:   behavior = settings.shiftClickBehavior
        case .option:  behavior = settings.optionClickBehavior
        case .command: behavior = settings.commandClickBehavior
        default:       behavior = ""
        }

        if behavior == "popUpActionMenu" {
            showActionMenu()
            return
        }
    }

    Task { await clipsService.select(entry) }
}

private func showActionMenu() {
    Task {
        let roots = await actionService.rootActions()

        // invokeActionImmediately: skip menu when exactly one root-level leaf action exists
        if settings.invokeActionImmediately, roots.count == 1, roots[0].isLeaf {
            await actionService.perform(action: roots[0], on: entry)
            return
        }

        await MainActor.run {
            let menu = ActionMenuBuilder.makeMenu(from: roots, target: entry, service: actionService)
            menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        }
    }
}
```

**Verification:** Set Control+Click → "Show action menu" in Action prefs. Control+click a clip → native NSMenu appears. Select "Paste as Plain Text" → result pasted. Enable `invokeActionImmediately`, remove all but one root action → modifier-click fires directly.

---

### Step 4C: Actions Preferences Editor

**Modified file:** `Sources/UI/Preferences/ActionsPrefsView.swift`

Expand the existing 54-line file to include a full CRUD tree editor below the settings form, matching the legacy reference UI. The editor uses `@Query` for live SwiftData updates.

**High-level layout:**

```
VStack {
    Form { ... existing enable/modifier-click sections ... }

    Divider()

    Text("Action Menu").font(.headline)

    HStack(alignment: .top) {
        // ── LEFT: active action tree ──────────────────────────
        List(selection: $selectedLeft) {
            OutlineGroup(rootNodes, children: \.sortedEnabledChildren) { node in
                ActionTreeRow(node: node, isEditing: $editingNode)
            }
        }
        .frame(minWidth: 200)

        // ── CENTER: add/folder/remove controls ────────────────
        VStack(spacing: 8) {
            Button("<<") { addSelectedAction() }
                .disabled(selectedRight == nil)
            Button("Folder") { addFolder() }
            Button("Remove") { removeSelected() }
                .disabled(selectedLeft == nil)
        }
        .padding(.top, 40)

        // ── RIGHT: available action catalog ───────────────────
        VStack {
            Picker("", selection: $rightTab) {
                Text("Built-in").tag(RightTab.builtin)
                Text("JavaScript").tag(RightTab.javaScript)
                Text("User's").tag(RightTab.users)
            }
            .pickerStyle(.segmented)

            List(availableItems, selection: $selectedRight) { item in
                Text(item.name)
            }
        }
        .frame(minWidth: 180)
    }
    .frame(minHeight: 280)

    // ── STATUS BAR ────────────────────────────────────────────
    HStack {
        Text("Name:")
        Text(selectedLeft?.title ?? selectedRight?.name ?? "")
        Spacer()
    }
    .padding(.horizontal)
}
```

**Supporting types:**

```swift
enum RightTab { case builtin, javaScript, users }

struct AvailableActionItem: Identifiable, Hashable {
    var id: String
    var name: String
    var actionType: String   // "builtin" | "javaScript"
    var actionName: String?  // built-in only
    var scriptPath: String?  // javaScript only
}
```

**Built-in catalog** (static):

```swift
static let builtinItems: [AvailableActionItem] = [
    .init(id: "pasteAsPlainText",   name: "Paste as Plain Text",   actionType: "builtin", actionName: "pasteAsPlainText"),
    .init(id: "pasteAsFilePath",    name: "Paste as File Path",    actionType: "builtin", actionName: "pasteAsFilePath"),
    .init(id: "pasteAsHFSFilePath", name: "Paste as HFS File Path",actionType: "builtin", actionName: "pasteAsHFSFilePath"),
    .init(id: "removeAction",       name: "Remove",                actionType: "builtin", actionName: "removeAction"),
]
```

**JavaScript catalog** — enumerate `Bundle.main.urls(forResourcesWithExtension: "js", subdirectory: "scripts/action")` for bundled scripts. Computed lazily.

**User's catalog** — enumerate `~/Library/Application Support/ClipMenu/script/action/*.js`.

**Operations:**

```swift
// Add selected right-panel item to the left tree
func addSelectedAction() {
    guard let item = selectedRight else { return }
    let node = ActionNode(title: item.name, isLeaf: true, sortIndex: nextRootSortIndex())
    node.actionType = item.actionType
    node.actionName = item.actionName
    node.scriptPath = item.scriptPath
    if let folder = selectedLeft, !folder.isLeaf {
        node.parent = folder
        folder.children.append(node)
    }
    context.insert(node)
    try? context.save()
}

// Add new folder at root (or inside selected folder)
func addFolder() {
    let node = ActionNode(title: "New Folder", isLeaf: false, sortIndex: nextRootSortIndex())
    if let folder = selectedLeft, !folder.isLeaf {
        node.parent = folder
        folder.children.append(node)
    }
    context.insert(node)
    try? context.save()
}

// Remove selected node (cascade deletes children via SwiftData relationship rule)
func removeSelected() {
    guard let node = selectedLeft else { return }
    context.delete(node)
    selectedLeft = nil
    try? context.save()
}
```

**Rename:** `ActionTreeRow` renders a `Text` in normal state and a `TextField` when double-tapped (manage with `@State var isRenaming: Bool` per row). On commit, set `node.title` and save context.

**Reorder:** Use `.onMove` on the `List`. After move, update `sortIndex` of all affected siblings to reflect new order.

**`@Environment(\.modelContext) private var context`** — use this for all mutations. `@Query(filter: #Predicate<ActionNode> { $0.parent == nil }, sort: \ActionNode.sortIndex)` for root nodes.

**`sortedEnabledChildren` computed property on `ActionNode`** (add as `extension ActionNode`):

```swift
extension ActionNode {
    var sortedEnabledChildren: [ActionNode]? {
        let c = children.filter(\.isEnabled).sorted { $0.sortIndex < $1.sortIndex }
        return c.isEmpty ? nil : c
    }
}
```

Returning `nil` instead of `[]` tells `OutlineGroup` the node is a leaf from the UI perspective (no disclosure arrow).

**Verification:** Open Prefs → Action tab → add "Paste as Plain Text" from Built-in panel → it appears in left tree. Add a folder, drag an action into it. Remove an action. Reopen prefs → changes persisted.

---

### Step 4D: Numeric Key Equivalents

**Modified files:** `Sources/UI/ClipMenuItem.swift`, `Sources/Infrastructure/HotkeyService.swift`

When `settings.numericKeyEquivalents` is `true`, history items gain keyboard shortcuts matching their list number (1–9 for items 1–9, 0 for item 10).

#### ClipMenuItem

Add a `ViewModifier` (private, local to the file) and apply it:

```swift
private struct NumericShortcut: ViewModifier {
    let number: Int
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled, (0...9).contains(number) {
            content.keyboardShortcut(KeyEquivalent(Character(String(number))), modifiers: [])
        } else {
            content
        }
    }
}
```

```swift
var body: some View {
    Button(action: select) { itemLabel }
        .help(tooltip)
        .modifier(NumericShortcut(number: listNumber % 10,
                                  enabled: settings.numericKeyEquivalents))
}
```

#### HotkeyService NSMenu construction

In the section that creates `NSMenuItem` objects for history clips, add:

```swift
if settings.numericKeyEquivalents {
    item.keyEquivalent = String(listNumber % 10)
    item.keyEquivalentModifierMask = []
}
```

**Verification:** Enable "Number keys select items" in Menu prefs → open history menu → press `1` → first clip is pasted.

---

### Phase 4 Completion Checklist

Update `migration_status.md` with the following when each item is done:

- [ ] Snippets migration bug fixed (`makeLegacySnippetModel()` replaces bundle load)
- [ ] `Resources/scripts/` folder created from `legacy/resource/script/` and wired in `project.yml`
- [ ] `DefaultActionSeeder.seedIfNeeded(in:)` implemented and called from `AppDelegate`
- [ ] `ActionService.rootActions()` and `rootActionCount()` added
- [ ] `ActionMenuBuilder.makeMenu(from:target:service:)` implemented
- [ ] `ClipMenuItem.select()` reads modifier flags and calls `showActionMenu()` when configured
- [ ] `ActionsPrefsView` expanded with full CRUD action tree editor
- [ ] `NumericShortcut` modifier wired in `ClipMenuItem` and `HotkeyService`
- [ ] Build passes (`xcodegen generate && xcodebuild -scheme ClipMenu build`)
