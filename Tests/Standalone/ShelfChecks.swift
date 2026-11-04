import Foundation
import AppKit
@main struct ShelfChecks {
 @MainActor static func main() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent("AdaShelfChecks-" + UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: root) }
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  let source = root.appendingPathComponent("original.txt")
  try Data("original".utf8).write(to: source)
  let shelfURL = root.appendingPathComponent("Shelf")
  let store = ShelfStore(storageURL: shelfURL, retentionDays: 0)
  store.addFiles([source, source])
  for _ in 0..<500 where store.isImporting { try await Task.sleep(nanoseconds: 10_000_000) }
  precondition(!store.isImporting && store.items.count == 2, "Two same-name source copies must both import")
  precondition(store.errorMessage == nil, "Import should succeed")
  try Data("changed".utf8).write(to: source)
  let first = store.items[0]
  let copyData = try Data(contentsOf: store.fileURL(for: first))
  precondition(String(data: copyData, encoding: .utf8) == "original", "Shelf must own its independent copy")
  let restored = ShelfStore(storageURL: shelfURL, retentionDays: 0)
  precondition(restored.items.count == 2, "Manifest survives reopening")
  restored.remove(first)
  precondition(FileManager.default.fileExists(atPath: source.path), "Removing shelf copy must preserve original")
  precondition(restored.items.count == 1, "Single removal")
  restored.retentionDays = 1
  restored.removeExpiredItems(now: Date().addingTimeInterval(2 * 86_400))
  precondition(restored.items.isEmpty, "Expired copies are removed")
  let sourceData = try Data(contentsOf: source)
  precondition(String(data: sourceData, encoding: .utf8) == "changed", "Retention must not alter source")
  restored.addFiles([root.appendingPathComponent("missing.txt")])
  for _ in 0..<500 where restored.isImporting { try await Task.sleep(nanoseconds: 10_000_000) }
  precondition(restored.errorMessage != nil, "Missing files must produce a visible error")
  print("PASS: shelf copy, duplicate names, persistence, independent content, removal safety, retention safety, missing-file error")
 }
}
