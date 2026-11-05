import AdaCore
import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct TaskItem: Codable, Identifiable {
    var id = UUID()
    var title: String
    var done = false
    var dueDate: Date?

    func isDueToday(on date: Date = .now, calendar: Calendar = .current) -> Bool {
        dueDate.map { calendar.isDate($0, inSameDayAs: date) } ?? false
    }
}

@MainActor
final class WorkspaceStore: ObservableObject {
    @Published var note: String { didSet { scheduleNoteSave() } }
    @Published var tasks: [TaskItem] = [] { didSet { persistTasks() } }
    @Published var shortcuts: [DashboardTile] = [] { didSet { persistShortcuts() } }
    @Published var shortcutError: String?
    @Published private(set) var noteError: String?
    @Published private(set) var noteExportError: String?
    let noteURL: URL
    private let noteWriter: NoteFileWriter
    private var noteRevision: UInt64 = 0
    private var noteNeedsSave = false
    private var noteSaveTask: Task<Void, Never>?
    private let defaults: UserDefaults
    private static let shortcutsKey = "workspaceAppShortcutsV2"

    init(defaults: UserDefaults = .standard, noteURL: URL? = nil) {
        self.defaults = defaults
        let location = noteURL ?? AdaInstallation.storage
            .appendingPathComponent("Notes/current.md")
        let initial = Self.initialNote(at: location, defaults: defaults)
        self.noteURL = location
        self.noteWriter = NoteFileWriter(url: location, recoveryBackupRequired: initial.recovery)
        self.note = initial.text
        self.noteNeedsSave = initial.pending
        self.noteError = initial.error
        if let data = defaults.data(forKey: "workspaceTasks"),
           let saved = try? JSONDecoder().decode([TaskItem].self, from: data) { tasks = saved }
        if let data = defaults.data(forKey: Self.shortcutsKey),
           let saved = try? JSONDecoder().decode([DashboardTile].self, from: data) {
            shortcuts = Self.normalizeShortcuts(saved)
        } else {
            let paths = defaults.stringArray(forKey: "workspaceShortcuts") ?? [
                "/Applications/Safari.app", "/System/Applications/Mail.app", "/System/Applications/Notes.app",
                "/System/Applications/Calendar.app"
            ].filter { FileManager.default.fileExists(atPath: $0) }
            shortcuts = Self.normalizeShortcuts(paths.compactMap { path in
                guard path.hasPrefix("/"), (path as NSString).pathExtension.lowercased() == "app" else { return nil }
                let url = URL(fileURLWithPath: path)
                return DashboardTile.application(at: url) ?? DashboardTile(kind: .app,
                    customName: url.deletingPathExtension().lastPathComponent, appPath: path)
            })
        }
        persistShortcuts()
        defaults.removeObject(forKey: "workspaceShortcuts")
    }

    private static func initialNote(at url: URL, defaults: UserDefaults) -> (text: String, pending: Bool, recovery: Bool, error: String?) {
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                let text = try String(contentsOf: url, encoding: .utf8)
                defaults.removeObject(forKey: "workspaceNote")
                return (text, false, false, nil)
            } catch {
                return (defaults.string(forKey: "workspaceNote") ?? "", false, true,
                    L10n.string("Not dosyası okunamadı: \(error.localizedDescription)"))
            }
        }
        guard let legacy = defaults.string(forKey: "workspaceNote") else { return ("", false, false, nil) }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(legacy.utf8).write(to: url, options: .atomic)
            defaults.removeObject(forKey: "workspaceNote")
            return (legacy, false, false, nil)
        } catch {
            return (legacy, true, false, L10n.string("Not kaydedilemedi: \(error.localizedDescription)"))
        }
    }

    private func scheduleNoteSave() {
        noteRevision &+= 1
        noteNeedsSave = true
        noteSaveTask?.cancel()
        let text = note
        let revision = noteRevision
        noteSaveTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 500_000_000)
                guard let self, !Task.isCancelled, self.noteRevision == revision else { return }
                try await self.noteWriter.write(text, revision: revision)
                if !Task.isCancelled && self.noteRevision == revision {
                    self.noteNeedsSave = false
                    self.noteError = nil
                    self.defaults.removeObject(forKey: "workspaceNote")
                }
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.noteError = L10n.string("Not kaydedilemedi: \(error.localizedDescription)")
            }
        }
    }

    /// Normal app termination awaits this before replying to AppKit.
    func flushNote() async -> Bool {
        noteSaveTask?.cancel()
        while noteNeedsSave {
            let text = note
            let revision = noteRevision
            do {
                try await noteWriter.write(text, revision: revision)
                if noteRevision == revision {
                    noteNeedsSave = false
                    noteError = nil
                    defaults.removeObject(forKey: "workspaceNote")
                }
            } catch {
                noteError = L10n.string("Not kaydedilemedi: \(error.localizedDescription)")
                return false
            }
        }
        return noteError == nil
    }

    func exportNote() {
        noteExportError = nil
        let panel = NSSavePanel()
        panel.title = L10n.string("Notu dışa aktar (.md)")
        panel.nameFieldStringValue = L10n.string("Ada-Not.md")
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        NSApp.activate()
        panel.begin { [weak self] result in
            MainActor.assumeIsolated {
                guard result == .OK, let url = panel.url, let self else { return }
                let text = self.note
                Task {
                    do { try await Task.detached { try NoteFileWriter.export(text, to: url) }.value }
                    catch { self.noteExportError = L10n.string("Not dışa aktarılamadı: \(error.localizedDescription)") }
                }
            }
        }
    }

    func addTask(_ title: String) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        tasks.append(TaskItem(title: title))
    }
    func toggleTask(_ id: UUID) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[i].done.toggle()
    }
    func setTaskDueDate(_ id: UUID, date: Date?) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].dueDate = date.map { Calendar.current.startOfDay(for: $0) }
    }

    func moveTask(_ id: UUID, offset: Int) {
        guard let from = tasks.firstIndex(where: { $0.id == id }),
              tasks.indices.contains(from + offset) else { return }
        var reordered = tasks
        let task = reordered.remove(at: from)
        reordered.insert(task, at: from + offset)
        tasks = reordered
    }

    func removeTask(_ id: UUID) { tasks.removeAll { $0.id == id } }
    func removeShortcut(_ id: UUID) { shortcuts.removeAll { $0.id == id } }

    private func persistTasks() {
        if let data = try? JSONEncoder().encode(tasks) { defaults.set(data, forKey: "workspaceTasks") }
    }
    private func persistShortcuts() {
        if let data = try? JSONEncoder().encode(shortcuts) { defaults.set(data, forKey: Self.shortcutsKey) }
    }
    private static func shortcutIdentity(_ tile: DashboardTile) -> String {
        tile.appBundleID ?? tile.appPath ?? tile.id.uuidString
    }
    private static func normalizeShortcuts(_ input: [DashboardTile]) -> [DashboardTile] {
        var seen = Set<String>()
        return Array(input.filter { tile in
            tile.kind == .app && tile.isWellFormed && seen.insert(shortcutIdentity(tile)).inserted
        }.prefix(6))
    }

    func chooseShortcut() {
        guard shortcuts.count < 6 else { return }
        shortcutError = nil
        let dialog = NSOpenPanel()
        dialog.title = L10n.string("Kısayol ekle")
        dialog.directoryURL = URL(fileURLWithPath: "/Applications")
        dialog.allowedContentTypes = [.applicationBundle]
        dialog.canChooseDirectories = false
        dialog.canChooseFiles = true
        dialog.begin { [weak self] result in
            MainActor.assumeIsolated {
                guard result == .OK, let url = dialog.url, let self,
                      let tile = DashboardTile.application(at: url) else { return }
                self.shortcuts = Self.normalizeShortcuts(self.shortcuts + [tile])
            }
        }
    }
    func openApp(_ tile: DashboardTile) {
        shortcutError = nil
        guard let url = tile.appURL else {
            shortcutError = L10n.string("“\(tile.title)” bulunamadı. Kısayolu yeniden ekle.")
            return
        }
        if !NSWorkspace.shared.open(url) {
            shortcutError = L10n.string("“\(tile.title)” açılamadı. Kısayolu yeniden ekle.")
        }
    }
}
