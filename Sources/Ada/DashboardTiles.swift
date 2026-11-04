import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum DashboardTileKind: String, Codable, CaseIterable, Identifiable {
    case spotify, appleMusic, chatGPT, claude
    case quickActions, battery, focus, notes, tasks, localMusic
    case files, cloud, system, tools, prompter, airDrop, mirror
    case app, website

    var id: String { rawValue }

    var title: String {
        switch self {
        case .spotify: return "Spotify"
        case .appleMusic: return "Apple Müzik"
        case .chatGPT: return "ChatGPT"
        case .claude: return "Claude"
        case .quickActions: return "Hızlı araçlar"
        case .battery: return "Pil"
        case .focus: return "Odak"
        case .notes: return "Notlar"
        case .tasks: return "Görevler"
        case .localMusic: return "Yerel müzik"
        case .files: return "Dosyalar"
        case .cloud: return "Bulut"
        case .system: return "Sistem"
        case .tools: return "Araçlar"
        case .prompter: return "Teleprompter"
        case .airDrop: return "AirDrop"
        case .mirror: return "Ayna"
        case .app: return "Uygulama"
        case .website: return "Web sitesi"
        }
    }

    var symbol: String {
        switch self {
        case .spotify: return "music.note.list"
        case .appleMusic, .localMusic: return "music.note"
        case .chatGPT, .claude: return "sparkles"
        case .quickActions: return "square.grid.2x2"
        case .battery: return "battery.100percent"
        case .focus: return "timer"
        case .notes: return "note.text"
        case .tasks: return "checklist"
        case .files: return "tray"
        case .cloud: return "icloud"
        case .system: return "cpu"
        case .tools: return "wrench.and.screwdriver"
        case .prompter: return "text.viewfinder"
        case .airDrop: return "airplayaudio"
        case .mirror: return "camera"
        case .app: return "app"
        case .website: return "globe"
        }
    }
}

struct DashboardTile: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var kind: DashboardTileKind
    var customName: String?
    var appBundleID: String?
    var appPath: String?
    var appBookmark: Data?
    var webURL: String?

    var title: String {
        let name = customName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !name.isEmpty { return name }
        if kind == .website, let host = websiteURL?.host { return host }
        return kind.title
    }

    var symbol: String { kind.symbol }

    var websiteURL: URL? { Self.validWebsiteURL(webURL ?? "") }

    var appURL: URL? {
        guard kind == .app else { return nil }
        if let appBookmark {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: appBookmark, options: [.withoutUI],
                                  relativeTo: nil, bookmarkDataIsStale: &stale),
               Self.validApplication(at: url, expectedBundleID: appBundleID) {
                return url
            }
        }
        if let appPath {
            let url = URL(fileURLWithPath: appPath)
            if Self.validApplication(at: url, expectedBundleID: appBundleID) { return url }
        }
        if let appBundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: appBundleID),
           Self.validApplication(at: url, expectedBundleID: appBundleID) {
            return url
        }
        return nil
    }

    var isWellFormed: Bool {
        switch kind {
        case .website: return websiteURL != nil
        case .app:
            // Keep a shortcut when its app is temporarily unavailable.
            return !(appBundleID?.isEmpty ?? true) || !(appPath?.isEmpty ?? true) || appBookmark != nil
        default: return true
        }
    }

    static func validWebsiteURL(_ value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return nil }
        let address = trimmed.contains(":") ? trimmed : "https://" + trimmed
        guard let components = URLComponents(string: address), components.scheme?.lowercased() == "https",
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              let url = components.url else { return nil }
        return url
    }

    static func application(at url: URL) -> DashboardTile? {
        guard validApplication(at: url), let bundle = Bundle(url: url) else { return nil }
        let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
        return DashboardTile(kind: .app, customName: name, appBundleID: bundle.bundleIdentifier,
                             appPath: url.path,
                             appBookmark: try? url.bookmarkData(options: [.minimalBookmark],
                                                               includingResourceValuesForKeys: nil, relativeTo: nil))
    }

    static func validApplication(at url: URL, expectedBundleID: String? = nil) -> Bool {
        guard url.isFileURL, url.pathExtension.lowercased() == "app",
              let bundle = Bundle(url: url),
              bundle.object(forInfoDictionaryKey: "CFBundlePackageType") as? String == "APPL",
              let executable = bundle.executableURL,
              FileManager.default.isExecutableFile(atPath: executable.path) else { return false }
        if let expectedBundleID, !expectedBundleID.isEmpty, bundle.bundleIdentifier != expectedBundleID { return false }
        return true
    }
}

@MainActor
final class DashboardLayoutStore: ObservableObject {
    static let maxTiles = 12
    static let storageKey = "dashboardTilesV1"
    @Published private(set) var tiles: [DashboardTile] { didSet { save() } }
    @Published var isEditing = false
    @Published var errorMessage: String?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard, initialTiles: [DashboardTile]? = nil) {
        self.defaults = defaults
        let seed = initialTiles ?? [
            DashboardTile(kind: .quickActions), DashboardTile(kind: .battery), DashboardTile(kind: .localMusic),
            DashboardTile(kind: .chatGPT), DashboardTile(kind: .focus), DashboardTile(kind: .tasks)
        ]
        if let data = defaults.data(forKey: Self.storageKey),
           let records = (try? JSONSerialization.jsonObject(with: data)) as? [Any] {
            // Decode individually so one corrupt or newer tile cannot erase the rest.
            let restored = records.compactMap { record -> DashboardTile? in
                guard JSONSerialization.isValidJSONObject(record),
                      let data = try? JSONSerialization.data(withJSONObject: record) else { return nil }
                return try? JSONDecoder().decode(DashboardTile.self, from: data)
            }
            tiles = Self.normalize(restored)
        } else {
            tiles = Self.normalize(seed)
        }
        save()
    }

    @discardableResult
    func add(_ tile: DashboardTile) -> Bool {
        guard tiles.count < Self.maxTiles else {
            errorMessage = "En fazla \(Self.maxTiles) kutucuk ekleyebilirsin."
            return false
        }
        guard tile.isWellFormed else {
            errorMessage = "Uygulama veya web adresini kontrol et."
            return false
        }
        var tile = tile
        if tiles.contains(where: { $0.id == tile.id }) { tile.id = UUID() }
        tiles.append(tile)
        errorMessage = nil
        return true
    }

    func remove(id: UUID) { tiles.removeAll { $0.id == id }; errorMessage = nil }

    @discardableResult
    func replace(id: UUID, with replacement: DashboardTile) -> Bool {
        guard let index = tiles.firstIndex(where: { $0.id == id }), replacement.isWellFormed else { return false }
        var tile = replacement
        tile.id = id
        tiles[index] = tile
        errorMessage = nil
        return true
    }

    func move(id: UUID, by amount: Int) {
        guard let index = tiles.firstIndex(where: { $0.id == id }) else { return }
        move(from: index, to: min(max(0, index + amount), tiles.count - 1))
    }

    func move(from source: Int, to destination: Int) {
        guard tiles.indices.contains(source), tiles.indices.contains(destination), source != destination else { return }
        var reordered = tiles
        let tile = reordered.remove(at: source)
        reordered.insert(tile, at: destination)
        tiles = reordered
    }

    func reset(to tiles: [DashboardTile]) {
        self.tiles = Self.normalize(tiles)
        errorMessage = nil
    }

    private static func normalize(_ tiles: [DashboardTile]) -> [DashboardTile] {
        var seen = Set<UUID>()
        return tiles.filter(\.isWellFormed).prefix(maxTiles).map { tile in
            var tile = tile
            if !seen.insert(tile.id).inserted {
                tile.id = UUID()
                seen.insert(tile.id)
            }
            return tile
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(tiles) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}

struct DashboardTilePicker: View {
    var title = "Ne eklemek istersin?"
    var onCancel: () -> Void = {}
    let onChoose: (DashboardTile) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showsWebsite = false
    @State private var websiteName = ""
    @State private var websiteAddress = ""
    @State private var error: String?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)
    private let applications: [DashboardTileKind] = [.spotify, .appleMusic, .chatGPT, .claude]
    private let widgets: [DashboardTileKind] = [.battery, .focus, .notes, .tasks, .localMusic, .quickActions,
                                                .files, .cloud, .system, .tools, .prompter, .airDrop, .mirror]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(title).font(.system(size: 20, weight: .semibold))
                Spacer()
                Button { onCancel(); dismiss() } label: {
                    Image(systemName: "xmark").frame(width: 24, height: 24)
                }.buttonStyle(IslandButtonStyle(cornerRadius: 100))
                    .keyboardShortcut(.cancelAction).accessibilityLabel("Kapat")
            }
            HStack(spacing: 9) {
                Button(action: chooseApplication) { Label("Uygulama seç…", systemImage: "app.badge") }
                Button { showsWebsite.toggle(); error = nil } label: { Label("Web sitesi", systemImage: "globe") }
            }.buttonStyle(IslandButtonStyle(bordered: true)).font(.system(size: 12))
            if showsWebsite {
                VStack(spacing: 8) {
                    TextField("Adı", text: $websiteName)
                    HStack(spacing: 8) {
                        TextField("https://…", text: $websiteAddress).onSubmit(addWebsite)
                        Button("Ekle", action: addWebsite).buttonStyle(IslandButtonStyle(bordered: true))
                    }
                }.textFieldStyle(.roundedBorder)
            }
            if let error { Text(error).font(.system(size: 11)).foregroundStyle(.red) }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    choices(applications)
                    Text("Ada").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                    choices(widgets)
                }.padding(3)
            }.scrollIndicators(.hidden)
        }
        .padding(22)
        .frame(width: 540, height: 500)
    }

    private func choices(_ kinds: [DashboardTileKind]) -> some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(kinds) { kind in
                Button { onChoose(DashboardTile(kind: kind)) } label: {
                    VStack(spacing: 6) {
                        Image(systemName: kind.symbol).font(.system(size: 19)).foregroundStyle(Color.accentColor)
                        Text(kind.title).font(.system(size: 11, weight: .medium)).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity).frame(height: 62)
                    .background(.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
                    .contentShape(RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(IslandButtonStyle(cornerRadius: 12))
            }
        }
    }

    private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.title = "Bir uygulama seç"
        panel.prompt = "Ekle"
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let tile = DashboardTile.application(at: url) else {
            error = "Geçerli bir uygulama seç."
            return
        }
        onChoose(tile)
    }

    private func addWebsite() {
        guard let url = DashboardTile.validWebsiteURL(websiteAddress) else {
            error = "Geçerli bir HTTPS adresi yaz."
            return
        }
        error = nil
        onChoose(DashboardTile(kind: .website, customName: websiteName, webURL: url.absoluteString))
    }
}
