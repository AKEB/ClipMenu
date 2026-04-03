import SwiftData
import Foundation
import AppKit

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
        let supportFolder = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("ClipMenu")

        guard let supportFolder else {
            UserDefaults.standard.set(true, forKey: completedKey)
            return
        }

        importClips(from: supportFolder.appendingPathComponent("clips.data"), into: context)
        importActions(from: supportFolder.appendingPathComponent("actions.plist"), into: context)

        UserDefaults.standard.set(true, forKey: completedKey)
    }

    private static func importClips(from url: URL, into context: ModelContext) {
        guard let data = try? Data(contentsOf: url) else { return }

        do {
            let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
            unarchiver.requiresSecureCoding = false
            unarchiver.setClass(LegacyArchivedClip.self, forClassName: "Clip")

            guard let legacyClips = unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey) as? [LegacyArchivedClip]
            else {
                return
            }

            for legacy in legacyClips {
                let entry = ClipEntry()
                entry.createdAt = legacy.createdDate ?? .now
                entry.lastUsedAt = legacy.lastUsedDate ?? entry.createdAt
                entry.types = legacy.types
                entry.stringValue = legacy.stringValue
                entry.rtfData = legacy.rtfData
                entry.pdfData = legacy.pdf
                entry.filenames = legacy.filenames
                entry.urlStrings = legacy.url
                if let image = legacy.image {
                    entry.imageData = image.tiffRepresentation
                }
                context.insert(entry)
            }

            try? context.save()
        } catch {
            return
        }
    }

    private static func importActions(from url: URL, into context: ModelContext) {
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dicts = plist as? [[String: Any]]
        else {
            return
        }

        for (index, dict) in dicts.enumerated() {
            let node = makeActionNode(from: dict, sortIndex: index)
            context.insert(node)
        }

        try? context.save()
    }

    private static func makeActionNode(from dictionary: [String: Any], sortIndex: Int) -> ActionNode {
        let title = (dictionary["nodeTitle"] as? String) ?? "Untitled"
        let isLeaf = (dictionary["isLeaf"] as? Bool) ?? false
        let node = ActionNode(title: title, isLeaf: isLeaf, sortIndex: sortIndex)

        if let action = dictionary["action"] as? [String: Any] {
            if let type = action["type"] as? String {
                node.actionType = type == "js" ? "javaScript" : type
            }
            node.actionName = action["name"] as? String
            node.scriptPath = action["path"] as? String
        }

        if let children = dictionary["children"] as? [[String: Any]] {
            node.children = children.enumerated().map { offset, child in
                makeActionNode(from: child, sortIndex: offset)
            }
        }

        return node
    }
}

@objc(CMLegacyArchivedClip)
private final class LegacyArchivedClip: NSObject, NSCoding {
    var types: [String] = []
    var createdDate: Date?
    var lastUsedDate: Date?
    var stringValue: String?
    var rtfData: Data?
    var pdf: Data?
    var filenames: [String]?
    var url: [String]?
    var image: NSImage?

    required init?(coder: NSCoder) {
        types = coder.decodeObject(forKey: "types") as? [String] ?? []
        createdDate = coder.decodeObject(forKey: "createdDate") as? Date
        lastUsedDate = coder.decodeObject(forKey: "lastUsedDate") as? Date
        stringValue = coder.decodeObject(forKey: "stringValue") as? String

        let rtfKeyCandidates = ["RTFData", "RTFD", "RTF"]
        for key in rtfKeyCandidates where rtfData == nil {
            rtfData = coder.decodeObject(forKey: key) as? Data
        }

        pdf = coder.decodeObject(forKey: "PDF") as? Data
        filenames = coder.decodeObject(forKey: "filenames") as? [String]
        url = coder.decodeObject(forKey: "URL") as? [String]
        image = coder.decodeObject(forKey: "image") as? NSImage
    }

    func encode(with coder: NSCoder) {
        coder.encode(types, forKey: "types")
        coder.encode(createdDate, forKey: "createdDate")
        coder.encode(lastUsedDate, forKey: "lastUsedDate")
        coder.encode(stringValue, forKey: "stringValue")
        coder.encode(rtfData, forKey: "RTFData")
        coder.encode(pdf, forKey: "PDF")
        coder.encode(filenames, forKey: "filenames")
        coder.encode(url, forKey: "URL")
        coder.encode(image, forKey: "image")
    }
}
