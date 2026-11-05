import AdaCore
import Foundation

/// Logical sizes are conservative on APFS clones. Symlinks are copied as links
/// and never traversed while estimating a folder.
enum ShelfStoragePolicy {
    static let confirmationThreshold: Int64 = 2_000_000_000

    static func fits(current: Int64, adding: Int64, maximum: Int64) -> Bool {
        let (total, overflow) = max(0, current).addingReportingOverflow(max(0, adding))
        return !overflow && (maximum <= 0 || total <= maximum)
    }

    static func size(of url: URL) throws -> Int64 {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey]
        let values = try url.resourceValues(forKeys: keys)
        if values.isSymbolicLink == true { return 0 }
        if values.isDirectory != true { return max(0, Int64(values.fileSize ?? 0)) }
        var failure: Error?
        guard let iterator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys),
            errorHandler: { _, error in failure = error; return false }) else {
            throw CocoaError(.fileReadNoPermission)
        }
        var total: Int64 = 0
        for case let child as URL in iterator {
            let entry = try child.resourceValues(forKeys: keys)
            if entry.isSymbolicLink == true { iterator.skipDescendants(); continue }
            if entry.isDirectory == true { continue }
            let (sum, overflow) = total.addingReportingOverflow(max(0, Int64(entry.fileSize ?? 0)))
            guard !overflow else { throw CocoaError(.fileReadTooLarge) }
            total = sum
        }
        if let failure { throw failure }
        return total
    }
}
