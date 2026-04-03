import Foundation
import Observation
import SwiftUI

@Observable
final class ClipMenuSettings {

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        registerLegacyDefaultsIfNeeded()
    }

    // MARK: - General

    @ObservationIgnored @AppStorage("loginItem")
    var launchAtLogin: Bool = false

    @ObservationIgnored @AppStorage("suppressAlertForLoginItem")
    var suppressLoginItemAlert: Bool = false

    @ObservationIgnored @AppStorage("inputPasteCommand")
    var autoPasteAfterSelection: Bool = true

    @ObservationIgnored @AppStorage("reorderClipsAfterPasting")
    var reorderClipsAfterPasting: Bool = true

    @ObservationIgnored @AppStorage("maxHistorySize")
    var maxHistorySize: Int = 20

    @ObservationIgnored @AppStorage("autosaveDelay")
    var autosaveDelay: Int = 1800

    @ObservationIgnored @AppStorage("saveHistoryOnQuit")
    var saveHistoryOnQuit: Bool = true

    @ObservationIgnored @AppStorage("exportHistoryAsSingleFile")
    var exportHistoryAsSingleFile: Bool = true

    @ObservationIgnored @AppStorage("tagOfSeparatorForExportHistoryToFile")
    var exportSeparatorTag: Int = 1

    @ObservationIgnored @AppStorage("showStatusItem")
    var showStatusItem: Bool = true

    @ObservationIgnored @AppStorage("timeInterval")
    var pollingInterval: Double = 0.75

    var storeTypes: [String: Bool] {
        get {
            (defaults.dictionary(forKey: "storeTypes") as? [String: Bool]) ?? Self.defaultStoreTypes
        }
        set {
            defaults.set(newValue, forKey: "storeTypes")
        }
    }

    var excludeApps: [[String: String]] {
        get {
            defaults.array(forKey: "excludeApps") as? [[String: String]] ?? Self.defaultExcludeApps
        }
        set {
            defaults.set(newValue, forKey: "excludeApps")
        }
    }

    // MARK: - Menu

    @ObservationIgnored @AppStorage("maxMenuItemTitleLength")
    var maxMenuItemTitleLength: Int = 20

    @ObservationIgnored @AppStorage("numberOfItemsPlaceInline")
    var numberOfItemsInline: Int = 0

    @ObservationIgnored @AppStorage("numberOfItemsPlaceInsideFolder")
    var numberOfItemsInsideFolder: Int = 10

    @ObservationIgnored @AppStorage("menuItemsAreMarkedWithNumbers")
    var numberedMenuItems: Bool = true

    @ObservationIgnored @AppStorage("menuItemsTitleStartWithZero")
    var numberingStartsAtZero: Bool = false

    @ObservationIgnored @AppStorage("addNumericKeyEquivalents")
    var numericKeyEquivalents: Bool = false

    @ObservationIgnored @AppStorage("addClearHistoryMenuItem")
    var showClearHistoryItem: Bool = true

    @ObservationIgnored @AppStorage("showAlertBeforeClearHistory")
    var showAlertBeforeClearHistory: Bool = true

    @ObservationIgnored @AppStorage("showLabelsInMenu")
    var showLabelsInMenu: Bool = true

    @ObservationIgnored @AppStorage("showToolTipOnMenuItem")
    var showTooltipsInMenu: Bool = true

    @ObservationIgnored @AppStorage("maxLengthOfToolTipKey")
    var maxTooltipLength: Int = 200

    @ObservationIgnored @AppStorage("changeFontSize")
    var changeFontSize: Bool = false

    @ObservationIgnored @AppStorage("howToChangeFontSize")
    var fontSizeMode: Int = 0

    @ObservationIgnored @AppStorage("selectedFontSize")
    var selectedFontSize: Int = 14

    @ObservationIgnored @AppStorage("showImageInTheMenu")
    var showImageInMenu: Bool = true

    @ObservationIgnored @AppStorage("thumbnailWidth")
    var thumbnailWidth: Int = 100

    @ObservationIgnored @AppStorage("thumbnailHeight")
    var thumbnailHeight: Int = 32

    @ObservationIgnored @AppStorage("showIconInTheMenu")
    var showIconInMenu: Bool = true

    @ObservationIgnored @AppStorage("menuIconSize")
    var menuIconSize: Int = 16

    @ObservationIgnored @AppStorage("menuIconOfFileTypeTagForString")
    var menuIconOfFileTypeTagForString: Int = 1

    @ObservationIgnored @AppStorage("menuIconOfFileTypeForString")
    var menuIconOfFileTypeForString: String = "TEXT"

    @ObservationIgnored @AppStorage("menuIconOfFileTypeTagForRTF")
    var menuIconOfFileTypeTagForRTF: Int = 0

    @ObservationIgnored @AppStorage("menuIconOfFileTypeForRTF")
    var menuIconOfFileTypeForRTF: String = "rtf"

    @ObservationIgnored @AppStorage("menuIconOfFileTypeTagForRTFD")
    var menuIconOfFileTypeTagForRTFD: Int = 0

    @ObservationIgnored @AppStorage("menuIconOfFileTypeForRTFD")
    var menuIconOfFileTypeForRTFD: String = "rtfd"

    @ObservationIgnored @AppStorage("menuIconOfFileTypeTagForPDF")
    var menuIconOfFileTypeTagForPDF: Int = 0

    @ObservationIgnored @AppStorage("menuIconOfFileTypeForPDF")
    var menuIconOfFileTypeForPDF: String = "pdf"

    @ObservationIgnored @AppStorage("menuIconOfFileTypeTagForFilenames")
    var menuIconOfFileTypeTagForFilenames: Int = 1

    @ObservationIgnored @AppStorage("menuIconOfFileTypeForFilenames")
    var menuIconOfFileTypeForFilenames: String = "clpu"

    @ObservationIgnored @AppStorage("menuIconOfFileTypeTagForURL")
    var menuIconOfFileTypeTagForURL: Int = 1

    @ObservationIgnored @AppStorage("menuIconOfFileTypeForURL")
    var menuIconOfFileTypeForURL: String = "gurl"

    @ObservationIgnored @AppStorage("menuIconOfFileTypeTagForTIFF")
    var menuIconOfFileTypeTagForTIFF: Int = 0

    @ObservationIgnored @AppStorage("menuIconOfFileTypeForTIFF")
    var menuIconOfFileTypeForTIFF: String = "tiff"

    @ObservationIgnored @AppStorage("menuIconOfFileTypeTagForPICT")
    var menuIconOfFileTypeTagForPICT: Int = 0

    @ObservationIgnored @AppStorage("menuIconOfFileTypeForPICT")
    var menuIconOfFileTypeForPICT: String = "pict"

    // MARK: - Hot Keys

    var hotKeys: [String: Any] {
        get { defaults.dictionary(forKey: "hotKeys") ?? Self.defaultHotKeys }
        set { defaults.set(newValue, forKey: "hotKeys") }
    }

    // MARK: - Actions

    @ObservationIgnored @AppStorage("enableAction")
    var enableAction: Bool = true

    @ObservationIgnored @AppStorage("invokeActionImmediately")
    var invokeActionImmediately: Bool = false

    @ObservationIgnored @AppStorage("controlClickBehavior")
    var controlClickBehavior: String = "popUpActionMenu"

    @ObservationIgnored @AppStorage("shiftClickBehavior")
    var shiftClickBehavior: String = ""

    @ObservationIgnored @AppStorage("optionClickBehavior")
    var optionClickBehavior: String = ""

    @ObservationIgnored @AppStorage("commandClickBehavior")
    var commandClickBehavior: String = ""

    // MARK: - Snippets

    @ObservationIgnored @AppStorage("positionOfSnippets")
    var positionOfSnippets: Int = 1

    // MARK: - Updates

    @ObservationIgnored @AppStorage("enableAutomaticCheck")
    var enableAutomaticCheck: Bool = true

    @ObservationIgnored @AppStorage("enableAutomaticCheckPreReleaseKey")
    var enableAutomaticCheckPreRelease: Bool = false

    @ObservationIgnored @AppStorage("updateCheckInterval")
    var updateCheckInterval: Int = 86_400

    private func registerLegacyDefaultsIfNeeded() {
        defaults.register(defaults: [
            "hotKeys": Self.defaultHotKeys,
            "loginItem": false,
            "suppressAlertForLoginItem": false,
            "inputPasteCommand": true,
            "reorderClipsAfterPasting": true,
            "maxHistorySize": 20,
            "autosaveDelay": 1_800,
            "saveHistoryOnQuit": true,
            "exportHistoryAsSingleFile": true,
            "tagOfSeparatorForExportHistoryToFile": 1,
            "showStatusItem": true,
            "timeInterval": 0.75,
            "storeTypes": Self.defaultStoreTypes,
            "excludeApps": Self.defaultExcludeApps,
            "maxMenuItemTitleLength": 20,
            "numberOfItemsPlaceInline": 0,
            "numberOfItemsPlaceInsideFolder": 10,
            "menuItemsAreMarkedWithNumbers": true,
            "menuItemsTitleStartWithZero": false,
            "addNumericKeyEquivalents": false,
            "addClearHistoryMenuItem": true,
            "showAlertBeforeClearHistory": true,
            "showLabelsInMenu": true,
            "showToolTipOnMenuItem": true,
            "maxLengthOfToolTipKey": 200,
            "changeFontSize": false,
            "howToChangeFontSize": 0,
            "selectedFontSize": 14,
            "showImageInTheMenu": true,
            "thumbnailWidth": 100,
            "thumbnailHeight": 32,
            "showIconInTheMenu": true,
            "menuIconSize": 16,
            "menuIconOfFileTypeTagForString": 1,
            "menuIconOfFileTypeForString": "TEXT",
            "menuIconOfFileTypeTagForRTF": 0,
            "menuIconOfFileTypeForRTF": "rtf",
            "menuIconOfFileTypeTagForRTFD": 0,
            "menuIconOfFileTypeForRTFD": "rtfd",
            "menuIconOfFileTypeTagForPDF": 0,
            "menuIconOfFileTypeForPDF": "pdf",
            "menuIconOfFileTypeTagForFilenames": 1,
            "menuIconOfFileTypeForFilenames": "clpu",
            "menuIconOfFileTypeTagForURL": 1,
            "menuIconOfFileTypeForURL": "gurl",
            "menuIconOfFileTypeTagForTIFF": 0,
            "menuIconOfFileTypeForTIFF": "tiff",
            "menuIconOfFileTypeTagForPICT": 0,
            "menuIconOfFileTypeForPICT": "pict",
            "enableAction": true,
            "invokeActionImmediately": false,
            "controlClickBehavior": "popUpActionMenu",
            "shiftClickBehavior": "",
            "optionClickBehavior": "",
            "commandClickBehavior": "",
            "positionOfSnippets": 1,
            "enableAutomaticCheck": true,
            "enableAutomaticCheckPreReleaseKey": false,
            "updateCheckInterval": 86_400,
        ])
    }

    private static let defaultStoreTypes: [String: Bool] = [
        "String": true,
        "RTF": true,
        "RTFD": true,
        "PDF": true,
        "Filenames": true,
        "URL": true,
        "TIFF": true,
        "PICT": true,
    ]

    private static let defaultExcludeApps: [[String: String]] = [[
        "bundleIdentifier": "org.openoffice.script",
        "name": "OpenOffice.org",
    ]]

    private static let defaultHotKeys: [String: [String: Int]] = [
        "ClipMenu": ["keyCode": 9, "modifiers": 768],
        "HistoryMenu": ["keyCode": 9, "modifiers": 4352],
        "SnippetsMenu": ["keyCode": 11, "modifiers": 768],
    ]
}
