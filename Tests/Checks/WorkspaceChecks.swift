@testable import Ada
@testable import AdaCore
import AppKit
import Foundation

enum WorkspaceChecks {
    @MainActor static func main() throws {
        let domain = "AdaWorkspace-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(domain)
        let noteURL = root.appendingPathComponent("note.md")
        defer { try? FileManager.default.removeItem(at: root) }
        defer { defaults.removePersistentDomain(forName: domain) }
        let notes = "/System/Applications/Notes.app"
        defaults.set([notes, notes, "/missing/Unavailable.app"], forKey: "workspaceShortcuts")
        defaults.set("keep my note", forKey: "workspaceNote")
        let store = WorkspaceStore(defaults: defaults, noteURL: noteURL)
        precondition(store.note == "keep my note" && store.shortcuts.count == 2)
        precondition(store.shortcuts.allSatisfy { $0.kind == .app })
        precondition(store.shortcuts[0].appBundleID == "com.apple.Notes")
        precondition(store.shortcuts[0].appBookmark != nil)
        precondition(defaults.object(forKey: "workspaceShortcuts") == nil)
        let savedIDs = store.shortcuts.map(\.id)
        let restored = WorkspaceStore(defaults: defaults, noteURL: noteURL)
        precondition(restored.shortcuts.map(\.id) == savedIDs)
        var moved = restored.shortcuts[0]
        moved.appBookmark = nil
        moved.appPath = "/missing/Notes.app"
        restored.shortcuts = [moved]
        precondition(restored.shortcuts[0].appURL != nil, "Bundle ID recovers a shortcut after its path changes")
        restored.removeShortcut(moved.id)
        precondition(WorkspaceStore(defaults: defaults, noteURL: noteURL).shortcuts.isEmpty)
        precondition(store.shortcuts[1].appURL == nil, "Unavailable legacy apps stay removable without launching")
        let oldTask = try JSONDecoder().decode(TaskItem.self, from: Data(#"{"id":"63D0EA64-F947-49A9-B777-07DCDA7F56D8","title":"Old task","done":false}"#.utf8))
        precondition(oldTask.dueDate == nil)
        store.tasks = [oldTask]
        store.addTask("Second")
        store.setTaskDueDate(oldTask.id, date: .now)
        precondition(store.tasks[0].isDueToday() && !store.tasks[1].isDueToday())
        store.moveTask(oldTask.id, offset: 1)
        precondition(store.tasks[1].id == oldTask.id)
        precondition(WorkspaceStore(defaults: defaults, noteURL: noteURL).tasks[1].isDueToday())
        precondition(CommandCalculation.evaluate("2 + 3 * 4") == "14")
        precondition(CommandCalculation.evaluate("-(2 + 3) * 4") == "-20")
        precondition(CommandCalculation.evaluate("100 °C to °F") == "212 °f")
        precondition(CommandCalculation.evaluate("1/0") == nil)
        precondition(CommandCalculation.evaluate("2 + open()") == nil)
        let backup = WorkspaceBackup(preferences: IslandPreferences(), tiles: [DashboardTile(kind: .focus)], tasks: store.tasks)
        let roundTrip = try WorkspaceBackup.decode(JSONEncoder().encode(backup))
        precondition(roundTrip.tiles == backup.tiles && roundTrip.tasks.map(\.id) == backup.tasks.map(\.id))
        precondition(WorkspaceBackup.merge(store.tasks, incoming: roundTrip.tasks).count == store.tasks.count)
        var wrongVersion = backup
        wrongVersion.format = 99
        let invalidBackup = try JSONEncoder().encode(wrongVersion)
        precondition((try? WorkspaceBackup.decode(invalidBackup)) == nil)
        print("PASS: one-time shortcut migration, bookmarks, stable identities, duplicate removal, moved-app recovery and empty-layout persistence; no apps launched")
    }
}
