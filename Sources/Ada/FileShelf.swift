import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct ShelfItem: Codable, Identifiable, Equatable {
    let id: UUID
    let name: String
    let addedAt: Date
    let isDirectory: Bool
}

private enum ShelfFailure: LocalizedError {
    case unsupported
    case missing(String)
    case unsafePath
    case recursiveFolder
    var errorDescription: String? {
        switch self {
        case .unsupported: return "Yalnızca Finder’dan sürüklenen dosya ve klasörler eklenebilir."
        case .missing(let name): return "“\(name)” bulunamadı veya artık erişilemiyor."
        case .unsafePath: return "Bu raf kaydı geçerli bir dosyaya işaret etmiyor."
        case .recursiveFolder: return "Rafın bulunduğu üst klasör kendi içine kopyalanamaz. İçindeki dosyalardan birini seç."
        }
    }
}

/// Owns independent copies. Deleting a shelf item never touches the source file.
@MainActor
final class ShelfStore: ObservableObject {
    static let shared = ShelfStore()
    @Published private(set) var items: [ShelfItem] = []
    @Published private(set) var isImporting = false
    @Published var errorMessage: String?
    @Published var retentionDays: Int {
        didSet {
            UserDefaults.standard.set(retentionDays, forKey: "shelfRetentionDays")
            removeExpiredItems()
        }
    }
    let storageURL: URL
    private var expiryTimer: Timer?

    init(storageURL: URL? = nil, retentionDays: Int? = nil) {
        self.storageURL = storageURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("dev.ada.island/Shelf", isDirectory: true)
        self.retentionDays = retentionDays ?? UserDefaults.standard.integer(forKey: "shelfRetentionDays")
        do {
            try FileManager.default.createDirectory(at: self.storageURL, withIntermediateDirectories: true)
            let manifest = self.storageURL.appendingPathComponent("items.json")
            if FileManager.default.fileExists(atPath: manifest.path) {
                items = try JSONDecoder().decode([ShelfItem].self, from: Data(contentsOf: manifest))
            }
            // Never trust names or IDs in a manifest to escape the shelf directory.
            items = items.filter { item in
                !item.name.isEmpty && item.name == URL(fileURLWithPath: item.name).lastPathComponent &&
                FileManager.default.fileExists(atPath: fileURL(for: item).path)
            }
            removeExpiredItems()
        } catch {
            errorMessage = "Dosya rafı açılamadı: \(error.localizedDescription)"
        }
        expiryTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.removeExpiredItems() }
        }
    }

    func fileURL(for item: ShelfItem) -> URL {
        storageURL.appendingPathComponent(item.id.uuidString, isDirectory: true)
            .appendingPathComponent(item.name, isDirectory: item.isDirectory)
    }

    func receiveProviders(_ providers: [NSItemProvider]) {
        guard !isImporting else { return }
        let fileProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !fileProviders.isEmpty else { errorMessage = ShelfFailure.unsupported.localizedDescription; return }
        errorMessage = nil
        isImporting = true
        Task {
            var failures: [String] = []
            for provider in fileProviders {
                do {
                    let url = try await Self.resolveFileURL(provider)
                    try await importCopy(of: url)
                } catch { failures.append(error.localizedDescription) }
            }
            finishImport(failures)
        }
    }

    /// Can also be called by an NSOpenPanel or a parent drop target.
    func addFiles(_ urls: [URL]) {
        guard !isImporting else { return }
        errorMessage = nil
        isImporting = true
        Task {
            var failures: [String] = []
            for url in urls {
                do { try await importCopy(of: url) }
                catch { failures.append(error.localizedDescription) }
            }
            finishImport(failures)
        }
    }

    func chooseFiles() {
        let picker = NSOpenPanel()
        picker.title = "Rafa eklenecek dosyaları seç"
        picker.prompt = "Rafa ekle"
        picker.canChooseDirectories = true
        picker.canChooseFiles = true
        picker.allowsMultipleSelection = true
        NSApp.activate(ignoringOtherApps: true)
        picker.begin { [weak self] result in
            guard result == .OK else { return }
            MainActor.assumeIsolated { self?.addFiles(picker.urls) }
        }
    }

    private func finishImport(_ failures: [String]) {
        isImporting = false
        if !failures.isEmpty {
            errorMessage = failures.prefix(2).joined(separator: "\n") + (failures.count > 2 ? "\n\(failures.count - 2) dosya daha eklenemedi." : "")
        }
    }

    private func importCopy(of source: URL) async throws {
        guard source.isFileURL else { throw ShelfFailure.unsupported }
        let sourcePath = source.standardizedFileURL.path
        let shelfPath = storageURL.standardizedFileURL.path
        guard sourcePath != "/", sourcePath != shelfPath, !shelfPath.hasPrefix(sourcePath + "/") else {
            throw ShelfFailure.recursiveFolder
        }
        let itemID = UUID()
        let itemDirectory = storageURL.appendingPathComponent(itemID.uuidString, isDirectory: true)
        // File copying can be slow; it must not stop the island's animation or focus clock.
        let item = try await Task.detached(priority: .userInitiated) {
            let scoped = source.startAccessingSecurityScopedResource()
            defer { if scoped { source.stopAccessingSecurityScopedResource() } }
            var directoryFlag: ObjCBool = false
            guard FileManager.default.fileExists(atPath: source.path, isDirectory: &directoryFlag) else {
                throw ShelfFailure.missing(source.lastPathComponent)
            }
            let name = source.lastPathComponent
            guard !name.isEmpty, name != ".", name != ".." else { throw ShelfFailure.unsafePath }
            let item = ShelfItem(id: itemID, name: name, addedAt: Date(), isDirectory: directoryFlag.boolValue)
            do {
                try FileManager.default.createDirectory(at: itemDirectory, withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: source, to: itemDirectory.appendingPathComponent(name))
                return item
            } catch {
                try? FileManager.default.removeItem(at: itemDirectory)
                throw error
            }
        }.value
        items.insert(item, at: 0)
        saveManifest()
    }

    private nonisolated static func resolveFileURL(_ provider: NSItemProvider) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { value, error in
                if let error { continuation.resume(throwing: error); return }
                let url: URL?
                if let value = value as? URL { url = value }
                else if let value = value as? Data { url = URL(dataRepresentation: value, relativeTo: nil) }
                else if let value = value as? String { url = URL(string: value) }
                else { url = nil }
                guard let url, url.isFileURL else { continuation.resume(throwing: ShelfFailure.unsupported); return }
                continuation.resume(returning: url)
            }
        }
    }

    func open(_ item: ShelfItem) {
        let url = fileURL(for: item)
        guard FileManager.default.fileExists(atPath: url.path) else {
            errorMessage = ShelfFailure.missing(item.name).localizedDescription
            return
        }
        if !NSWorkspace.shared.open(url) { errorMessage = "“\(item.name)” açılamadı." }
    }

    func reveal(_ item: ShelfItem) { NSWorkspace.shared.activateFileViewerSelecting([fileURL(for: item)]) }

    func remove(_ item: ShelfItem) {
        // Remove only a UUID child under our own storage, never the original input URL.
        let directory = storageURL.appendingPathComponent(item.id.uuidString, isDirectory: true)
        do {
            if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
            items.removeAll { $0.id == item.id }
            saveManifest()
        } catch { errorMessage = "Raftaki kopya kaldırılamadı: \(error.localizedDescription)" }
    }

    func removeAll() {
        for item in items { remove(item) }
    }

    func removeExpiredItems(now: Date = Date()) {
        guard retentionDays > 0 else { return }
        let cutoff = now.addingTimeInterval(-Double(retentionDays) * 86_400)
        for item in items where item.addedAt < cutoff { remove(item) }
    }

    private func saveManifest() {
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: storageURL.appendingPathComponent("items.json"), options: .atomic)
        } catch { errorMessage = "Raf listesi kaydedilemedi: \(error.localizedDescription)" }
    }
}

struct FileShelfView: View {
    @ObservedObject var store: ShelfStore
    var accent: Color = .blue
    var onInteraction: (Bool) -> Void = { _ in }
    @State private var targeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label("Dosyalar", systemImage: "tray.full.fill")
                    .font(.system(size: 12, weight: .semibold))
                Text("\(store.items.count)").font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.white.opacity(0.1), in: Capsule())
                Spacer()
                if store.isImporting { ProgressView().controlSize(.small) }
                Menu {
                    ForEach([0, 1, 2, 3, 7], id: \.self) { days in
                        Button {
                            store.retentionDays = days
                        } label: {
                            if store.retentionDays == days {
                                Label(days == 0 ? "Ben kaldırana kadar" : "\(days) gün", systemImage: "checkmark")
                            } else { Text(days == 0 ? "Ben kaldırana kadar" : "\(days) gün") }
                        }
                    }
                } label: {
                    Label(store.retentionDays == 0 ? "Sakla" : "\(store.retentionDays) gün sakla", systemImage: "clock")
                        .font(.system(size: 10))
                }.menuStyle(.borderlessButton).fixedSize()
                Button("Dosya ekle…", action: store.chooseFiles)
                    .font(.system(size: 10, weight: .medium)).buttonStyle(IslandButtonStyle()).foregroundStyle(accent)
                    .disabled(store.isImporting)
                if !store.items.isEmpty {
                    Button("Tümünü kaldır", action: store.removeAll)
                        .font(.system(size: 10, weight: .medium)).buttonStyle(IslandButtonStyle()).foregroundStyle(.red.opacity(0.85))
                        .disabled(store.isImporting)
                }
            }
            ZStack {
                RoundedRectangle(cornerRadius: 19)
                    .fill(targeted ? accent.opacity(0.2) : .white.opacity(0.035))
                RoundedRectangle(cornerRadius: 19)
                    .strokeBorder(targeted ? accent : .white.opacity(0.16), style: StrokeStyle(lineWidth: targeted ? 2 : 1, dash: targeted ? [6, 4] : []))
                if store.items.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: targeted ? "tray.and.arrow.down.fill" : "tray.and.arrow.down")
                            .font(.system(size: 25, weight: .light)).foregroundStyle(accent)
                        Text(targeted ? "Dosyaları buraya bırak" : "Dosyalarını buraya sürükle")
                            .font(.system(size: 13, weight: .medium))
                        Text("Kopyaları rafta kalır. Orijinalleri yerinde durur.")
                            .font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 14) {
                            ForEach(store.items) { item in ShelfFileTile(item: item, store: store, accent: accent) }
                        }.padding(12)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 125, maxHeight: .infinity)
            .onDrop(of: [UTType.fileURL.identifier], isTargeted: $targeted) { providers in
                store.receiveProviders(providers)
                return true
            }
            if let error = store.errorMessage {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                    Text(error).font(.system(size: 10)).lineLimit(2)
                    Spacer(minLength: 0)
                    Button("Kapat") { store.errorMessage = nil }
                        .font(.system(size: 10)).buttonStyle(IslandButtonStyle()).foregroundStyle(.white.opacity(0.55))
                }
            } else {
                Text("Açmak için tıkla · Kullanmak için dışarı sürükle · Yalnızca raftaki kopya kaldırılır")
                    .font(.system(size: 9)).foregroundStyle(.white.opacity(0.35))
            }
        }
        .foregroundStyle(.white)
        .onChange(of: targeted) { _, _ in onInteraction(targeted || store.isImporting) }
        .onChange(of: store.isImporting) { _, _ in onInteraction(targeted || store.isImporting) }
        .onDisappear { onInteraction(false) }
    }
}

private struct ShelfFileTile: View {
    let item: ShelfItem
    @ObservedObject var store: ShelfStore
    let accent: Color
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 6) {
            Button { store.open(item) } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 15).fill(.white.opacity(hovering ? 0.13 : 0.07))
                    RoundedRectangle(cornerRadius: 15).strokeBorder(.white.opacity(0.12), lineWidth: 1)
                    Image(nsImage: NSWorkspace.shared.icon(forFile: store.fileURL(for: item).path))
                        .resizable().interpolation(.high).scaledToFit().frame(width: 45, height: 45)
                }.frame(width: 68, height: 68)
            }.buttonStyle(IslandButtonStyle(cornerRadius: 15, emphasis: true)).help("\(item.name) dosyasını aç")
            .onDrag { NSItemProvider(contentsOf: store.fileURL(for: item)) ?? NSItemProvider() }
            Text(item.name).font(.system(size: 10, weight: .medium)).lineLimit(2)
                .multilineTextAlignment(.center).frame(width: 86, height: 26, alignment: .top)
            Button("Kaldır") { store.remove(item) }
                .font(.system(size: 9)).buttonStyle(IslandButtonStyle()).foregroundStyle(.white.opacity(hovering ? 0.7 : 0.35))
        }
        .frame(width: 86)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Aç") { store.open(item) }
            Button("Finder’da göster") { store.reveal(item) }
            Divider()
            Button("Raftan kaldır") { store.remove(item) }
        }
    }
}
