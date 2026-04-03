import SwiftData
import Foundation

/// A single clipboard entry captured from NSPasteboard.
///
/// Equality / deduplication uses `contentHash` which replicates the algorithm
/// from `legacy/Source/Clip.m -hash`.  See that file for the exact XOR
/// sequence before changing this implementation.
@Model
final class ClipEntry {

    var createdAt: Date
    var lastUsedAt: Date

    /// Pasteboard type strings in the order they appeared on the pasteboard.
    var types: [String]

    var stringValue: String?
    /// RTF or RTFD bytes (see `isRTFD` to distinguish).
    var rtfData: Data?
    /// `true` when `rtfData` contains an RTFD document (file-wrapper RTF).
    var isRTFD: Bool
    var pdfData: Data?
    var filenames: [String]?
    var urlStrings: [String]?
    /// TIFF bytes.
    var imageData: Data?

    init() {
        createdAt  = .now
        lastUsedAt = .now
        types      = []
        isRTFD     = false
    }

    // TODO: Phase 1 — implement contentHash replicating legacy/Source/Clip.m -hash
    //       (XOR of types.joined().hashValue, image byte count, filenames, URLs,
    //        PDF byte count, stringValue, RTF byte count).
    var contentHash: Int {
        // Placeholder — replace with real algorithm.
        var h = types.joined().hashValue
        h ^= (imageData?.count ?? 0)
        h ^= (filenames?.reduce(0) { $0 ^ $1.hashValue } ?? 0)
        h ^= (urlStrings?.reduce(0) { $0 ^ $1.hashValue } ?? 0)
        h ^= (pdfData?.count ?? 0)
        h ^= (stringValue?.hashValue ?? 0)
        h ^= (rtfData?.count ?? 0)
        return h
    }
}
