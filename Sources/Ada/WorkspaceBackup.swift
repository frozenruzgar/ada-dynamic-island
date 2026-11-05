import AdaCore
import SwiftUI
import UniformTypeIdentifiers

struct WorkspaceBackup: Codable {
    static let maximumSize = 5 * 1024 * 1024
    var format = 1
    let preferences: IslandPreferences
    let tiles: [DashboardTile]
    let tasks: [TaskItem]

    @MainActor static func decode(_ data: Data) throws -> Self {
        guard data.count <= maximumSize else { throw CocoaError(.fileReadTooLarge) }
        let value = try JSONDecoder().decode(Self.self, from: data)
        guard value.format == 1, value.preferences.supportsPersistence,
              value.tiles.count <= DashboardLayoutStore.maxTiles,
              value.tiles.allSatisfy(\.isWellFormed),
              Set(value.tiles.map(\.id)).count == value.tiles.count,
              Set(value.tasks.map(\.id)).count == value.tasks.count,
              value.tasks.allSatisfy({ !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return value
    }

    static func merge<T: Identifiable>(_ local: [T], incoming: [T]) -> [T] {
        var ids = Set(local.map(\.id))
        return local + incoming.filter { ids.insert($0.id).inserted }
    }
}

private struct WorkspaceBackupFile: FileDocument {
    static let readableContentTypes: [UTType] = [.json]
    var data: Data

    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let contents = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        data = contents
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { .init(regularFileWithContents: data) }
}

struct WorkspaceBackupView: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var workspace: WorkspaceStore
    @ObservedObject var dashboard: DashboardLayoutStore

    @State private var outgoing: WorkspaceBackupFile?
    @State private var incoming: WorkspaceBackup?
    @State private var exporting = false
    @State private var importing = false
    @State private var confirmImport = false
    @State private var status: String?

    var body: some View {
        Section(L10n.string("Ayar yedeği")) {
            HStack {
                Button(L10n.string("Yedeği dışa aktar…"), action: export)
                Button(L10n.string("Yedeği içe aktar…")) { importing = true }
                    .disabled(!model.preferences.supportsPersistence)
            }
            Text(L10n.string("Yedek, görünüm ve davranış ayarlarını, ana ekran kutucuklarını ve görevleri içerir."))
                .adaFont(size: Typography.caption).foregroundStyle(.secondary)
            if let status { Text(status).adaFont(size: Typography.caption) }
        }
        .fileExporter(isPresented: $exporting, document: outgoing, contentType: .json,
                      defaultFilename: "Ada-Backup") { result in
            status = (try? result.get()) == nil
                ? L10n.string("Yedek dışa aktarılamadı.") : L10n.string("Yedek dışa aktarıldı.")
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json], onCompletion: load)
        .confirmationDialog(L10n.string("Yedeği nasıl içe aktarmak istersin?"), isPresented: $confirmImport,
                            titleVisibility: .visible) {
            Button(L10n.string("Kutucuk ve görevleri birleştir")) { apply(replace: false) }
            Button(L10n.string("Ayarları, kutucukları ve görevleri değiştir"), role: .destructive) { apply(replace: true) }
            Button(L10n.string("Vazgeç"), role: .cancel) { incoming = nil }
        } message: {
            Text(L10n.string("Birleştirme mevcut ayarları ve eşleşen kayıtları korur. Değiştirme yedekteki düzeni kullanır."))
        }
    }

    private func export() {
        do {
            let value = WorkspaceBackup(preferences: model.preferences, tiles: dashboard.tiles, tasks: workspace.tasks)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            outgoing = WorkspaceBackupFile(data: try encoder.encode(value))
            exporting = true
        } catch { status = L10n.string("Yedek dışa aktarılamadı.") }
    }

    private func load(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= WorkspaceBackup.maximumSize else { throw CocoaError(.fileReadTooLarge) }
            incoming = try WorkspaceBackup.decode(Data(contentsOf: url, options: .mappedIfSafe))
            confirmImport = true
        } catch { status = L10n.string("Bu dosya geçerli bir Ada yedeği değil.") }
    }

    private func apply(replace: Bool) {
        guard let incoming, model.preferences.supportsPersistence else { return }
        if replace {
            model.preferences = incoming.preferences
            dashboard.reset(to: incoming.tiles)
            workspace.tasks = incoming.tasks
        } else {
            dashboard.reset(to: WorkspaceBackup.merge(dashboard.tiles, incoming: incoming.tiles))
            workspace.tasks = WorkspaceBackup.merge(workspace.tasks, incoming: incoming.tasks)
        }
        self.incoming = nil
        status = L10n.string("Yedek içe aktarıldı.")
    }
}
