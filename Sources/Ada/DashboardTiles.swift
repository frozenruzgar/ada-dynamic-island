import AdaCore
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
        case .spotify: return L10n.string("Spotify")
        case .appleMusic: return L10n.string("Apple Müzik")
        case .chatGPT: return L10n.string("ChatGPT")
        case .claude: return L10n.string("Claude")
        case .quickActions: return L10n.string("Hızlı araçlar")
        case .battery: return L10n.string("Pil")
        case .focus: return L10n.string("Odak")
        case .notes: return L10n.string("Notlar")
        case .tasks: return L10n.string("Görevler")
        case .localMusic: return L10n.string("Yerel müzik")
        case .files: return L10n.string("Dosyalar")
        case .cloud: return L10n.string("Bulut")
        case .system: return L10n.string("Sistem")
        case .tools: return L10n.string("Araçlar")
        case .prompter: return L10n.string("Teleprompter")
        case .airDrop: return L10n.string("AirDrop")
        case .mirror: return L10n.string("Ayna")
        case .app: return L10n.string("Uygulama")
        case .website: return L10n.string("Web sitesi")
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
    @Published var focusedTileID: UUID?
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
        var tile = Self.canonicalTile(tile)
        if tile.kind == .spotify, let existing = tiles.first(where: { $0.kind == .spotify }) {
            focusedTileID = existing.id
            errorMessage = nil
            return true
        }
        guard tiles.count < Self.maxTiles else {
            errorMessage = L10n.string("En fazla \(Self.maxTiles) kutucuk ekleyebilirsin.")
            return false
        }
        guard tile.isWellFormed else {
            errorMessage = L10n.string("Uygulama veya web adresini kontrol et.")
            return false
        }
        if tiles.contains(where: { $0.id == tile.id }) { tile.id = UUID() }
        tiles.append(tile)
        focusedTileID = tile.id
        errorMessage = nil
        return true
    }

    func remove(id: UUID) { tiles.removeAll { $0.id == id }; errorMessage = nil }

    @discardableResult
    func replace(id: UUID, with replacement: DashboardTile) -> Bool {
        var tile = Self.canonicalTile(replacement)
        guard let index = tiles.firstIndex(where: { $0.id == id }), tile.isWellFormed else { return false }
        tile.id = id
        var updated = tiles
        updated[index] = tile
        if tile.kind == .spotify {
            updated.removeAll { $0.kind == .spotify && $0.id != id }
        }
        tiles = updated
        focusedTileID = id
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
        var hasSpotify = false
        return Array(tiles.compactMap { original -> DashboardTile? in
            var tile = canonicalTile(original)
            guard tile.isWellFormed else { return nil }
            if tile.kind == .spotify {
                guard !hasSpotify else { return nil }
                hasSpotify = true
            }
            if !seen.insert(tile.id).inserted {
                tile.id = UUID()
                seen.insert(tile.id)
            }
            return tile
        }.prefix(maxTiles))
    }

    private static func canonicalTile(_ original: DashboardTile) -> DashboardTile {
        var tile = original
        if tile.kind == .app && tile.appBundleID == "com.spotify.client" { tile.kind = .spotify }
        return tile
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(tiles) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}

struct DashboardTilePicker: View {
    var title = L10n.string("Ne eklemek istersin?")
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
                Text(title).adaFont(size: 20, weight: .semibold)
                Spacer()
                Button { onCancel(); dismiss() } label: {
                    Image(systemName: "xmark").frame(width: 24, height: 24)
                }.buttonStyle(IslandButtonStyle(cornerRadius: 100))
                    .keyboardShortcut(.cancelAction).accessibilityLabel(L10n.string("Kapat"))
            }
            HStack(spacing: 9) {
                Button(action: chooseApplication) { Label(L10n.string("Uygulama seç…"), systemImage: "app.badge") }
                Button { showsWebsite.toggle(); error = nil } label: { Label(L10n.string("Web sitesi"), systemImage: "globe") }
            }.buttonStyle(IslandButtonStyle(bordered: true)).adaFont(size: 12)
            if showsWebsite {
                VStack(spacing: 8) {
                    TextField(L10n.string("Adı"), text: $websiteName)
                    HStack(spacing: 8) {
                        TextField("https://…", text: $websiteAddress).onSubmit(addWebsite)
                        Button(L10n.string("Ekle"), action: addWebsite).buttonStyle(IslandButtonStyle(bordered: true))
                    }
                }.textFieldStyle(.roundedBorder)
            }
            if let error { Text(error).adaFont(size: 11).foregroundStyle(.red) }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    choices(applications)
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
                        if kind == .spotify {
                            SpotifyBrandIcon(size: 30)
                        } else {
                            Image(systemName: kind.symbol)
                                .adaFont(size: 19).foregroundStyle(Color.accentColor)
                                .frame(height: 30)
                        }
                        Text(kind.title).adaFont(size: 11, weight: .medium).lineLimit(1)
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
        panel.title = L10n.string("Bir uygulama seç")
        panel.prompt = L10n.string("Ekle")
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let tile = DashboardTile.application(at: url) else {
            error = L10n.string("Geçerli bir uygulama seç.")
            return
        }
        onChoose(tile)
    }

    private func addWebsite() {
        guard let url = DashboardTile.validWebsiteURL(websiteAddress) else {
            error = L10n.string("Geçerli bir HTTPS adresi yaz.")
            return
        }
        error = nil
        onChoose(DashboardTile(kind: .website, customName: websiteName, webURL: url.absoluteString))
    }
}
