import AppKit
import SwiftUI

struct TaskItem: Codable, Identifiable {
    var id = UUID()
    var title: String
    var done = false
}

@MainActor
final class WorkspaceStore: ObservableObject {
    @Published var note = UserDefaults.standard.string(forKey: "workspaceNote") ?? "" {
        didSet { UserDefaults.standard.set(note, forKey: "workspaceNote") }
    }
    @Published var tasks: [TaskItem] = [] { didSet { persistTasks() } }
    @Published var shortcuts: [String] = [] {
        didSet { UserDefaults.standard.set(shortcuts, forKey: "workspaceShortcuts") }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: "workspaceTasks"),
           let saved = try? JSONDecoder().decode([TaskItem].self, from: data) { tasks = saved }
        shortcuts = UserDefaults.standard.stringArray(forKey: "workspaceShortcuts") ?? [
            "/Applications/Safari.app", "/System/Applications/Mail.app", "/System/Applications/Notes.app",
            "/System/Applications/Calendar.app"
        ].filter { FileManager.default.fileExists(atPath: $0) }
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
    func removeTask(_ id: UUID) { tasks.removeAll { $0.id == id } }
    private func persistTasks() {
        if let data = try? JSONEncoder().encode(tasks) { UserDefaults.standard.set(data, forKey: "workspaceTasks") }
    }
    func chooseShortcut() {
        guard shortcuts.count < 6 else { return }
        let dialog = NSOpenPanel()
        dialog.title = "Kısayol ekle"
        dialog.directoryURL = URL(fileURLWithPath: "/Applications")
        dialog.allowedContentTypes = [.applicationBundle]
        dialog.canChooseDirectories = false
        dialog.canChooseFiles = true
        dialog.begin { [weak self] result in
            MainActor.assumeIsolated {
                guard result == .OK, let url = dialog.url, let self, !self.shortcuts.contains(url.path) else { return }
                self.shortcuts.append(url.path)
            }
        }
    }
    func openApp(_ path: String) { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
}
