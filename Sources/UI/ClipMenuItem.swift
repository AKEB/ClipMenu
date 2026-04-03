import SwiftUI
import AppKit

/// A single row in the clipboard history menu.
///
/// Rendering rules are taken from `legacy/Source/MenuController.m
/// -_makeMenuItemForClip:withCount:andListNumber:`.
struct ClipMenuItem: View {

    let entry: ClipEntry
    /// Numbering prefix (already computed by ClipMenuView).
    let listNumber: Int

    @Environment(ClipMenuSettings.self) private var settings
    @Environment(\.clipsService) private var clipsService

    var body: some View {
        Button(action: select) {
            itemLabel
        }
        .help(tooltip)
    }

    // MARK: - Label

    @ViewBuilder
    private var itemLabel: some View {
        HStack(spacing: 4) {
            // Type icon
            if settings.showIconInMenu, let icon = typeIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: CGFloat(settings.menuIconSize),
                           height: CGFloat(settings.menuIconSize))
            }

            // Image thumbnail
            if settings.showImageInMenu, let thumb = thumbnail {
                Image(nsImage: thumb)
            }

            // Title text
            Text(titleText)
                .font(itemFont)

            // Type label badge
            if settings.showLabelsInMenu, let label = primaryTypeName {
                Text("[\(label)]")
                    .foregroundStyle(.secondary)
                    .font(itemFont)
            }
        }
    }

    // MARK: - Title

    private var titleText: String {
        var t = trimmedTitle
        if settings.numberedMenuItems {
            t = "\(listNumber). \(t)"
        }
        return t
    }

    /// Replicates `trimTitle()` from `legacy/Source/MenuController.m`.
    private var trimmedTitle: String {
        let source = entry.stringValue
            ?? entry.filenames?.first
            ?? entry.urlStrings?.first
            ?? ""
        let stripped = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstLine: String
        if let nl = stripped.firstIndex(of: "\n") {
            firstLine = String(stripped[..<nl])
        } else {
            firstLine = stripped
        }
        let maxLen = settings.maxMenuItemTitleLength
        if firstLine.count > maxLen {
            return String(firstLine.prefix(max(maxLen - 3, 0))) + "..."
        }
        return firstLine.isEmpty ? "(binary)" : firstLine
    }

    // MARK: - Visual properties

    private var thumbnail: NSImage? {
        guard let data = entry.imageData else { return nil }
        guard let img = NSImage(data: data) else { return nil }
        return scaledImage(img,
                           to: NSSize(width: CGFloat(settings.thumbnailWidth),
                                      height: CGFloat(settings.thumbnailHeight)))
    }

    private var typeIcon: NSImage? {
        // Use NSWorkspace to resolve a file-type icon for the primary pasteboard type.
        let ext = iconFileExtension(for: entry.types.first ?? "")
        guard !ext.isEmpty else { return nil }
        let icon = NSWorkspace.shared.icon(forFileType: ext)
        return scaledImage(icon, to: NSSize(width: CGFloat(settings.menuIconSize),
                                             height: CGFloat(settings.menuIconSize)))
    }

    /// Maps a pasteboard type string to the file-extension hint used when
    /// asking NSWorkspace for an icon. Mirrors the per-type prefs in settings.
    private func iconFileExtension(for type: String) -> String {
        switch type {
        case "NSStringPboardType", "public.utf8-plain-text":
            return settings.menuIconOfFileTypeTagForString == 0
                ? settings.menuIconOfFileTypeForString
                : hfsToExt(settings.menuIconOfFileTypeForString)
        case "NeXT Rich Text Format v1.0 pasteboard type", "public.rtf":
            return settings.menuIconOfFileTypeForRTF
        case "NeXT RTFD pasteboard type":
            return settings.menuIconOfFileTypeForRTFD
        case "Apple PDF pasteboard type", "com.adobe.pdf":
            return settings.menuIconOfFileTypeForPDF
        case "NSFilenamesPboardType", "public.file-url":
            return settings.menuIconOfFileTypeForFilenames
        case "Apple URL pasteboard type", "public.url":
            return settings.menuIconOfFileTypeForURL
        case "NeXT TIFF v4.0 pasteboard type", "public.tiff":
            return settings.menuIconOfFileTypeForTIFF
        default:
            return ""
        }
    }

    private func hfsToExt(_ hfs: String) -> String { hfs.lowercased() }

    private var primaryTypeName: String? {
        let map: [String: String] = [
            "NSStringPboardType": "String",
            "public.utf8-plain-text": "String",
            "NeXT Rich Text Format v1.0 pasteboard type": "RTF",
            "NeXT RTFD pasteboard type": "RTFD",
            "Apple PDF pasteboard type": "PDF",
            "NSFilenamesPboardType": "Filenames",
            "Apple URL pasteboard type": "URL",
            "NeXT TIFF v4.0 pasteboard type": "TIFF",
            "Apple PICT pasteboard type": "PICT",
        ]
        return entry.types.compactMap { map[$0] }.first
    }

    private var tooltip: String {
        guard settings.showTooltipsInMenu else { return "" }
        let text = entry.stringValue
            ?? entry.filenames?.joined(separator: "\n")
            ?? ""
        return String(text.prefix(settings.maxTooltipLength))
    }

    private var itemFont: Font {
        guard settings.changeFontSize else { return .body }
        let size: CGFloat = settings.fontSizeMode == 0
            ? CGFloat(settings.menuIconSize)
            : CGFloat(settings.selectedFontSize)
        return .system(size: size)
    }

    // MARK: - Action

    private func select() {
        Task { await clipsService.select(entry) }
    }

    // MARK: - Helpers

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

// MARK: - Preview

#Preview("String clip") {
    let entry = ClipEntry()
    entry.stringValue = "Hello, world! This is a sample clipboard entry."
    entry.types = ["NSStringPboardType"]
    return ClipMenuItem(entry: entry, listNumber: 1)
        .environment(ClipMenuSettings())
        .environment(\.clipsService, ClipsService(settings: ClipMenuSettings()))
        .padding()
}

#Preview("Binary clip") {
    let entry = ClipEntry()
    entry.types = ["NeXT TIFF v4.0 pasteboard type"]
    return ClipMenuItem(entry: entry, listNumber: 2)
        .environment(ClipMenuSettings())
        .environment(\.clipsService, ClipsService(settings: ClipMenuSettings()))
        .padding()
}
