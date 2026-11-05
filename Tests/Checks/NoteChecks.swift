@testable import Ada
@testable import AdaCore
import AppKit
import Foundation

enum NoteChecks {
    static func text(_ url: URL) -> String { try! String(contentsOf: url, encoding: .utf8) }
    static func bytes(_ url: URL) -> Data { try! Data(contentsOf: url) }

    @MainActor static func main() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("AdaNoteChecks-" + UUID().uuidString)
        let domain = "AdaNoteChecks-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        defer { try? fm.removeItem(at: root); defaults.removePersistentDomain(forName: domain) }
        let noteURL = root.appendingPathComponent("note/current.md")
        let store = WorkspaceStore(defaults: defaults, noteURL: noteURL)
        store.note = "a"; store.note = "ab"; store.note = "abc"
        try await Task.sleep(nanoseconds: 100_000_000)
        precondition(!fm.fileExists(atPath: noteURL.path), "Keystrokes must be debounced")
        try await Task.sleep(nanoseconds: 600_000_000)
        precondition(text(noteURL) == "abc" && store.noteError == nil)
        store.note = "last edit before quit"
        let flushed = await store.flushNote()
        precondition(flushed && text(noteURL) == "last edit before quit")
        let restored = WorkspaceStore(defaults: defaults, noteURL: noteURL)
        precondition(restored.note == store.note)
        let staleURL = root.appendingPathComponent("stale.md")
        let writer = NoteFileWriter(url: staleURL)
        try await writer.write("new", revision: 2)
        try await writer.write("old", revision: 1)
        precondition(text(staleURL) == "new")
        defaults.set("legacy note", forKey: "workspaceNote")
        let migrationURL = root.appendingPathComponent("migrated.md")
        let migrated = WorkspaceStore(defaults: defaults, noteURL: migrationURL)
        precondition(migrated.note == "legacy note" && text(migrationURL) == "legacy note")
        precondition(defaults.object(forKey: "workspaceNote") == nil)
        let blockedParent = root.appendingPathComponent("not-a-folder")
        try Data("keep this file".utf8).write(to: blockedParent)
        defaults.set("recoverable legacy", forKey: "workspaceNote")
        let failed = WorkspaceStore(defaults: defaults, noteURL: blockedParent.appendingPathComponent("note.md"))
        let failedFlush = await failed.flushNote()
        precondition(!failedFlush && failed.note == "recoverable legacy" && failed.noteError != nil)
        precondition(defaults.string(forKey: "workspaceNote") == "recoverable legacy")
        precondition(text(blockedParent) == "keep this file")
        defaults.removeObject(forKey: "workspaceNote")
        let corruptURL = root.appendingPathComponent("corrupt.md")
        let corrupt = Data([0xff, 0x00])
        try corrupt.write(to: corruptURL)
        let recovery = WorkspaceStore(defaults: defaults, noteURL: corruptURL)
        let refused = await recovery.flushNote()
        precondition(!refused && bytes(corruptURL) == corrupt)
        recovery.note = "recovered text"
        let recovered = await recovery.flushNote()
        precondition(recovered && text(corruptURL) == "recovered text")
        let backups = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("note-recovery-") }
        precondition(backups.count == 1 && bytes(backups[0]) == corrupt)
        let exported = root.appendingPathComponent("export.md")
        let exportText = "Ada\nTürkçe · {1} %@"
        try NoteFileWriter.export(exportText, to: exported)
        precondition(text(exported) == exportText)
        print("PASS: note debounce, final flush, stale-save rejection, file persistence, one-time migration, failed-write preservation, corrupt-note recovery backup and UTF-8 export; temporary files only")
    }
}
