import Foundation
import SQLite3

/// Resolves a ClipMenu-specific SwiftData store path.
///
/// ClipMenu previously used SwiftData's implicit `default.store` in Application Support.
/// That generic filename is shared by other apps and can be overwritten, which breaks
/// clipboard history persistence.
enum SwiftDataStoreLocation {
    static let storeFileName = "ClipMenu.store"

    static func storeURL() throws -> URL {
        let fileManager = FileManager.default
        guard let supportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw CocoaError(.fileNoSuchFile)
        }

        let clipMenuDirectory = supportDirectory.appendingPathComponent("ClipMenu", isDirectory: true)
        try fileManager.createDirectory(at: clipMenuDirectory, withIntermediateDirectories: true)
        return clipMenuDirectory.appendingPathComponent(storeFileName)
    }

    /// Copies a known-good legacy store into the dedicated ClipMenu location once.
    static func migrateLegacyStoreIfNeeded(to destination: URL) {
        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: destination.path) else { return }
        guard let supportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return
        }

        let candidates = legacyStoreCandidates(in: supportDirectory)
            .filter { fileManager.fileExists(atPath: $0.path) }
            .filter(isClipMenuStore)

        guard let source = candidates.first else { return }

        do {
            try fileManager.copyItem(at: source, to: destination)
            copySidecarIfPresent(from: source, to: destination, suffix: "-shm")
            copySidecarIfPresent(from: source, to: destination, suffix: "-wal")
        } catch {
            return
        }
    }

    private static func legacyStoreCandidates(in supportDirectory: URL) -> [URL] {
        let fileManager = FileManager.default
        let defaultStore = supportDirectory.appendingPathComponent("default.store")

        var backups: [URL] = []
        if let enumerator = fileManager.enumerator(
            at: supportDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) {
            for case let fileURL as URL in enumerator where fileURL.lastPathComponent.hasPrefix("default.store.before-") {
                backups.append(fileURL)
            }
        }

        backups.sort { lhs, rhs in
            let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return lhsDate > rhsDate
        }

        return backups + [defaultStore]
    }

    private static func isClipMenuStore(_ url: URL) -> Bool {
        guard let database = try? SwiftDataStoreInspector.open(at: url) else { return false }
        return database.containsClipEntryTable
    }

    private static func copySidecarIfPresent(from source: URL, to destination: URL, suffix: String) {
        let fileManager = FileManager.default
        let sourceSidecar = URL(fileURLWithPath: source.path + suffix)
        let destinationSidecar = URL(fileURLWithPath: destination.path + suffix)
        guard fileManager.fileExists(atPath: sourceSidecar.path) else { return }
        try? fileManager.copyItem(at: sourceSidecar, to: destinationSidecar)
    }
}

private enum SwiftDataStoreInspector {
    struct Database {
        let containsClipEntryTable: Bool
    }

    static func open(at url: URL) throws -> Database {
        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            throw CocoaError(.fileReadCorruptFile)
        }
        defer { sqlite3_close(database) }

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        let query = "SELECT name FROM sqlite_master WHERE type='table' AND name='ZCLIPENTRY' LIMIT 1;"
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK else {
            throw CocoaError(.fileReadCorruptFile)
        }

        return Database(containsClipEntryTable: sqlite3_step(statement) == SQLITE_ROW)
    }
}
