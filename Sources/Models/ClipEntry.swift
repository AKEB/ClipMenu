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

    var contentHash: Int {
        var h = types.joined().hashValue

        if let imageData {
            h ^= imageData.count
        }

        if let filenames {
            for filename in filenames {
                h ^= filename.hashValue
            }
        } else if let urlStrings {
            for urlString in urlStrings {
                h ^= urlString.hashValue
            }
        } else if let pdfData {
            h ^= pdfData.count
        } else if let stringValue {
            h ^= stringValue.hashValue
        }

        h ^= (rtfData?.count ?? 0)
        return h
    }
}
