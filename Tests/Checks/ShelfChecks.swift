@testable import Ada
@testable import AdaCore
import Foundation
import AppKit
enum ShelfChecks {
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
  restored.addFiles([source])
  restored.addFiles([source])
  let provider = NSItemProvider(item: source as NSURL, typeIdentifier: "public.file-url")
  precondition(restored.receiveProviders([provider]))
  precondition(restored.isImporting && restored.totalCount == 3 && restored.queuedCount == 3)
  for _ in 0..<500 where restored.isImporting { try await Task.sleep(nanoseconds: 10_000_000) }
  precondition(!restored.isImporting && restored.items.count == 3)
  precondition(restored.completedCount == 3 && restored.queuedCount == 0 && restored.errorMessage == nil)
  precondition(!restored.receiveProviders([NSItemProvider(object: "text" as NSString)]))
  let orphan = shelfURL.appendingPathComponent(UUID().uuidString, isDirectory: true)
  let unrelated = shelfURL.appendingPathComponent("keep-me", isDirectory: true)
  let linked = shelfURL.appendingPathComponent(UUID().uuidString, isDirectory: true)
  try FileManager.default.createDirectory(at: orphan, withIntermediateDirectories: true)
  try FileManager.default.createDirectory(at: unrelated, withIntermediateDirectories: true)
  try Data("unfinished".utf8).write(to: orphan.appendingPathComponent("partial.txt"))
  try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: root)
  let cleaned = ShelfStore(storageURL: shelfURL, retentionDays: 0)
  precondition(cleaned.items.count == 3 && cleaned.errorMessage == nil)
  precondition(!FileManager.default.fileExists(atPath: orphan.path))
  precondition(FileManager.default.fileExists(atPath: unrelated.path))
  precondition(FileManager.default.fileExists(atPath: linked.path))
  precondition(FileManager.default.fileExists(atPath: source.path))
  let brokenURL = root.appendingPathComponent("BrokenShelf", isDirectory: true)
  let recoverable = brokenURL.appendingPathComponent(UUID().uuidString, isDirectory: true)
  try FileManager.default.createDirectory(at: recoverable, withIntermediateDirectories: true)
  try Data("broken json".utf8).write(to: brokenURL.appendingPathComponent("items.json"))
  let broken = ShelfStore(storageURL: brokenURL, retentionDays: 0)
  precondition(broken.errorMessage != nil && FileManager.default.fileExists(atPath: recoverable.path))
  let pasteboard = NSPasteboard.withUniqueName()
  defer { pasteboard.releaseGlobally() }
  let copyIDs = Set(cleaned.items.prefix(2).map(\.id))
  precondition(cleaned.copyFiles(copyIDs, to: pasteboard))
  let copied = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
  precondition(copied == cleaned.items.prefix(2).map { cleaned.fileURL(for: $0) })
  precondition(cleaned.availableFiles(for: copyIDs.union([UUID()])).isEmpty, "Stale selections cannot share partial batches")
  pasteboard.clearContents()
  precondition(pasteboard.writeObjects(["https://example.com" as NSString]))
  precondition(!cleaned.pasteFiles(from: pasteboard) && !cleaned.isImporting)
  pasteboard.clearContents()
  precondition(pasteboard.writeObjects([source as NSURL, source as NSURL]))
  precondition(cleaned.pasteFiles(from: pasteboard))
  for _ in 0..<500 where cleaned.isImporting { try await Task.sleep(nanoseconds: 10_000_000) }
  precondition(!cleaned.isImporting && cleaned.items.count == 5)
  print("PASS: Finder file-only paste, ordered multi-file copy, stale selection handling and paste queue")
  print("PASS: shelf copy, duplicate names, persistence, independent content, removal safety, retention safety, missing-file error, concurrent drop queue, aggregate progress and unsupported-drop rejection, orphan cleanup, symlink/unrelated-folder safety and corrupt-manifest preservation")
 }
}
