import AdaCore
import AppKit
import Foundation
import Combine
import UniformTypeIdentifiers

struct ShelfItem: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let addedAt: Date
    let isDirectory: Bool
    var byteSize: Int64? = nil
}

private enum ShelfFailure: LocalizedError {
    case unsupported
    case missing(String)
    case unsafePath
    case recursiveFolder
    case capacity
    case diskSpace
    case cancelled
    var errorDescription: String? {
        switch self {
        case .capacity: return L10n.string("Rafın boyut sınırı aşılacak. Ayarlar’dan sınırı değiştir veya raftan dosya kaldır.")
        case .diskSpace: return L10n.string("Kopyalama için yeterli disk alanı yok.")
        case .cancelled: return L10n.string("Büyük dosya kopyalama iptal edildi.")
        case .unsupported: return L10n.string("Yalnızca Finder’dan sürüklenen dosya ve klasörler eklenebilir.")
        case .missing(let name): return L10n.string("“\(name)” bulunamadı veya artık erişilemiyor.")
        case .unsafePath: return L10n.string("Bu raf kaydı geçerli bir dosyaya işaret etmiyor.")
        case .recursiveFolder: return L10n.string("Rafın bulunduğu üst klasör kendi içine kopyalanamaz. İçindeki dosyalardan birini seç.")
        }
    }
}

/// Owns independent copies. Deleting a shelf item never touches the source file.
@MainActor
final class ShelfStore: NSObject, ObservableObject, NSSharingServicePickerDelegate {
    static let shared = ShelfStore()
    @Published private(set) var items: [ShelfItem] = []
    @Published private(set) var isImporting = false
    @Published private(set) var queuedCount = 0
    @Published private(set) var completedCount = 0
    @Published private(set) var totalCount = 0
    private enum ImportInput {
        case file(URL)
        case provider(NSItemProvider)
    }
    private var importQueue: [ImportInput] = []
    private var importTask: Task<Void, Never>?
    private var sharePicker: NSSharingServicePicker?
    weak var shareAnchor: NSView?
    var isSharing: Bool { sharePicker != nil }
    @Published var maximumBytes: Int64 {
        didSet { defaults.set(max(0, maximumBytes), forKey: "shelfMaximumBytes") }
    }
    @Published var errorMessage: String?
    @Published var retentionDays: Int {
        didSet {
            defaults.set(retentionDays, forKey: "shelfRetentionDays")
            removeExpiredItems()
        }
    }
    let storageURL: URL
    private var expiryTimer: Timer?
    private let defaults: UserDefaults
    private let confirmationThreshold: Int64
    private let confirmLargeImport: @MainActor (Int64) -> Bool

    var totalBytes: Int64? {
        guard items.allSatisfy({ $0.byteSize != nil }) else { return nil }
        var total: Int64 = 0
        for item in items {
            let (sum, overflow) = total.addingReportingOverflow(max(0, item.byteSize ?? 0))
            if overflow { return Int64.max }
            total = sum
        }
        return total
    }

    init(storageURL: URL? = nil, retentionDays: Int? = nil, defaults: UserDefaults = .standard,
         confirmationThreshold: Int64 = ShelfStoragePolicy.confirmationThreshold,
         confirmLargeImport: (@MainActor (Int64) -> Bool)? = nil) {
        self.defaults = defaults
        self.confirmationThreshold = confirmationThreshold
        self.confirmLargeImport = confirmLargeImport ?? Self.confirmLargeCopy
        self.maximumBytes = Int64(defaults.integer(forKey: "shelfMaximumBytes"))
        self.storageURL = storageURL ?? AdaInstallation.storage
            .appendingPathComponent("Shelf", isDirectory: true)
        self.retentionDays = retentionDays ?? defaults.integer(forKey: "shelfRetentionDays")
        super.init()
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
            try removeOrphanedDirectories()
            removeExpiredItems()
        } catch {
            errorMessage = L10n.string("Dosya rafı açılamadı: \(error.localizedDescription)")
        }
        refreshSizes()
        expiryTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.removeExpiredItems() }
        }
    }

    private static func confirmLargeCopy(_ bytes: Int64) -> Bool {
        let alert = NSAlert()
        alert.messageText = L10n.string("Büyük dosyaları rafa kopyala?")
        let size = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        alert.informativeText = L10n.string("Bu işlemden sonra raf yaklaşık \(size) yer kullanacak. Orijinaller korunur; raf kendi kopyasını oluşturur.")
        alert.addButton(withTitle: L10n.string("Vazgeç"))
        alert.addButton(withTitle: L10n.string("Kopyala"))
        NSApp.activate()
        return alert.runModal() == .alertSecondButtonReturn
    }

    private func refreshSizes() {
        let pending = items.map { ($0.id, fileURL(for: $0)) }
        guard !pending.isEmpty else { return }
        Task { [weak self] in
            let measured = await Task.detached(priority: .utility) {
                pending.compactMap { id, url -> (UUID, Int64)? in
                    guard let bytes = try? ShelfStoragePolicy.size(of: url) else { return nil }
                    return (id, bytes)
                }
            }.value
            guard let self else { return }
            let sizes = Dictionary(uniqueKeysWithValues: measured)
            self.items = self.items.map { item in
                var updated = item
                if let bytes = sizes[item.id] { updated.byteSize = bytes }
                return updated
            }
            self.saveManifest()
        }
    }

    func fileURL(for item: ShelfItem) -> URL {
        storageURL.appendingPathComponent(item.id.uuidString, isDirectory: true)
            .appendingPathComponent(item.name, isDirectory: item.isDirectory)
    }

    @discardableResult
    func receiveProviders(_ providers: [NSItemProvider]) -> Bool {
        let files = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !files.isEmpty else { errorMessage = ShelfFailure.unsupported.localizedDescription; return false }
        enqueue(files.map(ImportInput.provider))
        return true
    }

    /// Every batch joins the same serial queue, including drops during a copy.
    func addFiles(_ urls: [URL]) { enqueue(urls.map(ImportInput.file)) }

    /// Read only after a deliberate Paste action, and only Finder file URLs.
    @discardableResult
    func pasteFiles(from pasteboard: NSPasteboard = .general) -> Bool {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])?
            .compactMap { $0 as? URL }.filter(\.isFileURL) ?? []
        guard !urls.isEmpty else {
            errorMessage = L10n.string("Finder’da dosyaları kopyalayıp tekrar yapıştır.")
            return false
        }
        addFiles(urls)
        return true
    }

    func availableFiles(for ids: Set<UUID>) -> [URL] {
        let files = items.filter { ids.contains($0.id) }.map { fileURL(for: $0) }
        // Reject a stale selection as a group instead of sharing a partial batch.
        guard !files.isEmpty, files.count == ids.count,
              files.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) else {
            errorMessage = L10n.string("Seçili dosyalardan bazıları artık rafta yok.")
            return []
        }
        return files
    }

    @discardableResult
    func copyFiles(_ ids: Set<UUID>, to pasteboard: NSPasteboard = .general) -> Bool {
        let files = availableFiles(for: ids)
        guard !files.isEmpty else { return false }
        pasteboard.clearContents()
        let copied = pasteboard.writeObjects(files.map { $0 as NSURL })
        errorMessage = copied ? nil : L10n.string("Dosyalar panoya kopyalanamadı.")
        return copied
    }

    func shareFiles(_ ids: Set<UUID>) {
        let files = availableFiles(for: ids)
        guard !files.isEmpty, let view = shareAnchor, view.window?.isVisible == true else { return }
        sharePicker?.close()
        let picker = NSSharingServicePicker(items: files)
        picker.delegate = self
        sharePicker = picker
        let anchor = NSRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
        picker.show(relativeTo: anchor, of: view, preferredEdge: .minY)
    }

    func closeSharing() {
        let picker = sharePicker
        sharePicker = nil
        picker?.close()
    }

    nonisolated func sharingServicePicker(_ picker: NSSharingServicePicker, didChoose service: NSSharingService?) {
        let identity = ObjectIdentifier(picker)
        MainActor.assumeIsolated {
            if sharePicker.map(ObjectIdentifier.init) == identity { sharePicker = nil }
        }
    }

    private func enqueue(_ inputs: [ImportInput]) {
        guard !inputs.isEmpty else { return }
        if !isImporting {
            errorMessage = nil
            completedCount = 0
            totalCount = 0
            isImporting = true
        }
        importQueue.append(contentsOf: inputs)
        totalCount += inputs.count
        queuedCount = importQueue.count
        guard importTask == nil else { return }
        importTask = Task {
            var failures: [String] = []
            while !importQueue.isEmpty {
                let input = importQueue.removeFirst()
                queuedCount = importQueue.count
                do {
                    let url: URL
                    switch input {
                    case .file(let value): url = value
                    case .provider(let provider): url = try await Self.resolveFileURL(provider)
                    }
                    try await importCopy(of: url)
                } catch { failures.append(error.localizedDescription) }
                completedCount += 1
            }
            importTask = nil
            finishImport(failures)
        }
    }

    func chooseFiles() {
        let picker = NSOpenPanel()
        picker.title = L10n.string("Rafa eklenecek dosyaları seç")
        picker.prompt = L10n.string("Rafa ekle")
        picker.canChooseDirectories = true
        picker.canChooseFiles = true
        picker.allowsMultipleSelection = true
        NSApp.activate()
        picker.begin { [weak self] result in
            guard result == .OK else { return }
            MainActor.assumeIsolated { self?.addFiles(picker.urls) }
        }
    }

    private func finishImport(_ failures: [String]) {
        isImporting = false
        if !failures.isEmpty {
            errorMessage = failures.prefix(2).joined(separator: "\n") + (failures.count > 2 ? L10n.string("\n\(failures.count - 2) dosya daha eklenemedi.") : "")
        }
    }

    private func importCopy(of source: URL) async throws {
        guard source.isFileURL else { throw ShelfFailure.unsupported }
        let sourcePath = source.standardizedFileURL.path
        let shelfPath = storageURL.standardizedFileURL.path
        guard sourcePath != "/", sourcePath != shelfPath, !shelfPath.hasPrefix(sourcePath + "/") else {
            throw ShelfFailure.recursiveFolder
        }
        let stored = items.map { ($0.id, fileURL(for: $0)) }
        let estimate = try await Task.detached(priority: .userInitiated) {
            let scoped = source.startAccessingSecurityScopedResource()
            defer { if scoped { source.stopAccessingSecurityScopedResource() } }
            var used: Int64 = 0
            var sizes: [UUID: Int64] = [:]
            for (id, url) in stored {
                let bytes = try ShelfStoragePolicy.size(of: url)
                sizes[id] = bytes
                let (sum, overflow) = used.addingReportingOverflow(max(0, bytes))
                guard !overflow else { throw ShelfFailure.capacity }
                used = sum
            }
            return (used, try ShelfStoragePolicy.size(of: source), sizes)
        }.value
        let measuredItems = items.map { original in
            var item = original
            if let bytes = estimate.2[item.id] { item.byteSize = bytes }
            return item
        }
        if measuredItems != items { items = measuredItems; saveManifest() }
        guard ShelfStoragePolicy.fits(current: estimate.0, adding: estimate.1, maximum: maximumBytes) else {
            throw ShelfFailure.capacity
        }
        if let free = try? storageURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage,
           estimate.1 > free { throw ShelfFailure.diskSpace }
        if !ShelfStoragePolicy.fits(current: estimate.0, adding: estimate.1, maximum: confirmationThreshold) {
            let (projected, overflow) = estimate.0.addingReportingOverflow(estimate.1)
            guard !overflow else { throw ShelfFailure.capacity }
            if !confirmLargeImport(projected) { throw ShelfFailure.cancelled }
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
            var item = ShelfItem(id: itemID, name: name, addedAt: Date(), isDirectory: directoryFlag.boolValue)
            do {
                try FileManager.default.createDirectory(at: itemDirectory, withIntermediateDirectories: true)
                let destination = itemDirectory.appendingPathComponent(name)
                try FileManager.default.copyItem(at: source, to: destination)
                item.byteSize = try ShelfStoragePolicy.size(of: destination)
                return item
            } catch {
                try? FileManager.default.removeItem(at: itemDirectory)
                throw error
            }
        }.value
        guard ShelfStoragePolicy.fits(current: estimate.0, adding: item.byteSize ?? estimate.1, maximum: maximumBytes) else {
            try? FileManager.default.removeItem(at: itemDirectory)
            throw ShelfFailure.capacity
        }
        items.insert(item, at: 0)
        saveManifest()
    }

    private static func resolveFileURL(_ provider: NSItemProvider) async throws -> URL {
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
        if !NSWorkspace.shared.open(url) { errorMessage = L10n.string("“\(item.name)” açılamadı.") }
    }

    func reveal(_ item: ShelfItem) { NSWorkspace.shared.activateFileViewerSelecting([fileURL(for: item)]) }

    func remove(_ item: ShelfItem) {
        // Remove only a UUID child under our own storage, never the original input URL.
        let directory = storageURL.appendingPathComponent(item.id.uuidString, isDirectory: true)
        do {
            if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
            items.removeAll { $0.id == item.id }
            saveManifest()
        } catch { errorMessage = L10n.string("Raftaki kopya kaldırılamadı: \(error.localizedDescription)") }
    }

    func removeAll() {
        for item in items { remove(item) }
    }

    func removeExpiredItems(now: Date = Date()) {
        guard retentionDays > 0 else { return }
        let cutoff = now.addingTimeInterval(-Double(retentionDays) * 86_400)
        for item in items where item.addedAt < cutoff { remove(item) }
    }

    private func removeOrphanedDirectories() throws {
        let liveIDs = Set(items.map(\.id))
        let entries = try FileManager.default.contentsOfDirectory(at: storageURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [])
        for entry in entries {
            guard let id = UUID(uuidString: entry.lastPathComponent), !liveIDs.contains(id) else { continue }
            let values = try entry.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            // Never traverse a symlink or treat unrelated files as owned copies.
            guard values.isDirectory == true, values.isSymbolicLink != true else { continue }
            try FileManager.default.removeItem(at: entry)
        }
    }

    private func saveManifest() {
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: storageURL.appendingPathComponent("items.json"), options: .atomic)
        } catch { errorMessage = L10n.string("Raf listesi kaydedilemedi: \(error.localizedDescription)") }
    }
}
