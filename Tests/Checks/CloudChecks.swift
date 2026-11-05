@testable import Ada
@testable import AdaCore
import Foundation
import AppKit
enum CloudChecks {
 @MainActor static func main() throws {
  let domain = "AdaCloudChecks-" + UUID().uuidString
  let defaults = UserDefaults(suiteName: domain)!
  defer { defaults.removePersistentDomain(forName: domain) }
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(domain)
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let source = root.appendingPathComponent("FavoriteA", isDirectory: true)
  try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
  let content = source.appendingPathComponent("keep.txt")
  try Data("Keep me".utf8).write(to: content)
  let store = CloudWorkspaceStore(defaults: defaults, homeDirectory: root)
  precondition(!store.iCloudDriveAvailable)
  store.addFolders([source, source])
  precondition(store.favorites.count == 1)
  precondition(store.favorites[0].name == "FavoriteA")
  precondition(store.favorites[0].bookmark != nil)
  let restored = CloudWorkspaceStore(defaults: defaults, homeDirectory: root)
  precondition(restored.favorites == store.favorites)
  restored.removeFavorite(restored.favorites[0].id)
  precondition(restored.favorites.isEmpty)
  precondition(FileManager.default.fileExists(atPath: source.path))
  let preserved = try String(contentsOf: content, encoding: .utf8)
  precondition(preserved == "Keep me")
  let reread = CloudWorkspaceStore(defaults: defaults, homeDirectory: root)
  precondition(reread.favorites.isEmpty)
  reread.addFolders([content])
  precondition(reread.favorites.isEmpty && reread.errorMessage != nil)
  let cloud = root.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
  try FileManager.default.createDirectory(at: cloud, withIntermediateDirectories: true)
  reread.refreshAvailability()
  precondition(reread.iCloudDriveAvailable)
  precondition(CloudWebService.all.count == 4 && CloudWebService.all.allSatisfy { $0.url.scheme == "https" })
  print("PASS: folder bookmarks, duplicates, persistence, shortcut-only removal, source preservation, invalid folder errors, iCloud existence and HTTPS services")
 }
}
