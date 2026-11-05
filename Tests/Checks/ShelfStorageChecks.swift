@testable import Ada
@testable import AdaCore
import AppKit
import Foundation

enum ShelfStorageChecks {
    @MainActor static func wait(_ store: ShelfStore) async throws {
        for _ in 0..<500 where store.isImporting { try await Task.sleep(nanoseconds: 10_000_000) }
        precondition(!store.isImporting)
    }

    @MainActor static func main() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("AdaShelfBudget-" + UUID().uuidString)
        let suite = "AdaShelfBudget-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { try? fm.removeItem(at: root); defaults.removePersistentDomain(forName: suite) }
        let input = root.appendingPathComponent("input", isDirectory: true)
        try fm.createDirectory(at: input, withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: input.appendingPathComponent("a"))
        try Data([4, 5]).write(to: input.appendingPathComponent(".hidden"))
        let outside = root.appendingPathComponent("outside")
        try Data(repeating: 7, count: 100).write(to: outside)
        try fm.createSymbolicLink(at: input.appendingPathComponent("link"), withDestinationURL: outside)
        precondition(trySize(input) == 5, "Hidden files count; linked targets do not")
        precondition(!ShelfStoragePolicy.fits(current: Int64.max, adding: 1, maximum: 0))
        precondition(ShelfStoragePolicy.fits(current: 3, adding: 2, maximum: 5))
        precondition(!ShelfStoragePolicy.fits(current: 3, adding: 3, maximum: 5))
        var confirmations: [Int64] = []
        var approve = false
        let location = root.appendingPathComponent("shelf")
        let store = ShelfStore(storageURL: location, retentionDays: 0, defaults: defaults,
            confirmationThreshold: 4, confirmLargeImport: { bytes in
                confirmations.append(bytes)
                return approve
            })
        store.maximumBytes = 4
        store.addFiles([input]); try await wait(store)
        precondition(store.items.isEmpty && store.errorMessage != nil && confirmations.isEmpty)
        store.maximumBytes = 100
        store.addFiles([input]); try await wait(store)
        precondition(store.items.isEmpty && confirmations == [5] && store.errorMessage != nil)
        approve = true
        store.addFiles([input]); try await wait(store)
        precondition(store.items.count == 1 && store.totalBytes == 5 && store.errorMessage == nil)
        store.addFiles([input]); try await wait(store)
        precondition(store.items.count == 2 && store.totalBytes == 10 && confirmations.last == 10)
        precondition(fm.fileExists(atPath: input.appendingPathComponent("a").path))
        // Older manifests have no byteSize. Measure those copies without changing originals.
        let manifest = location.appendingPathComponent("items.json")
        var records = try JSONSerialization.jsonObject(with: Data(contentsOf: manifest)) as! [[String: Any]]
        for index in records.indices { records[index].removeValue(forKey: "byteSize") }
        try JSONSerialization.data(withJSONObject: records).write(to: manifest)
        let restored = ShelfStore(storageURL: location, retentionDays: 0, defaults: defaults)
        for _ in 0..<500 where restored.totalBytes == nil { try await Task.sleep(nanoseconds: 10_000_000) }
        precondition(restored.totalBytes == 10 && restored.maximumBytes == 100)
        restored.maximumBytes = 9
        restored.addFiles([input]); try await wait(restored)
        precondition(restored.items.count == 2 && restored.errorMessage != nil)
        let editedCopy = restored.fileURL(for: restored.items[0]).appendingPathComponent("a")
        try Data(repeating: 8, count: 10).write(to: editedCopy)
        restored.maximumBytes = 18
        restored.addFiles([input]); try await wait(restored)
        precondition(restored.items.count == 2 && restored.totalBytes == 17 && restored.errorMessage != nil)
        restored.remove(restored.items[0])
        precondition(restored.totalBytes == 5 && fm.fileExists(atPath: outside.path))
        print("PASS: shelf byte estimates, hidden files, symlinks, overflow, quota rejection, confirmation cancel/accept, projected total, persisted limits, external copy edits and legacy size migration")
    }

    static func trySize(_ url: URL) -> Int64 { try! ShelfStoragePolicy.size(of: url) }
}
