import AppKit
import SwiftUI

struct CloudFavoriteFolder: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var bookmark: Data?
    var fallbackPath: String
}

struct CloudWebService: Identifiable {
    var id: String
    var name: String
    var symbol: String
    var url: URL

    static let all: [CloudWebService] = [
        .init(id: "icloud", name: "iCloud", symbol: "icloud", url: URL(string: "https://www.icloud.com/")!),
        .init(id: "drive", name: "Google Drive", symbol: "externaldrive", url: URL(string: "https://drive.google.com/")!),
        .init(id: "dropbox", name: "Dropbox", symbol: "shippingbox", url: URL(string: "https://www.dropbox.com/")!),
        .init(id: "onedrive", name: "OneDrive", symbol: "cloud", url: URL(string: "https://onedrive.live.com/")!)
    ]
}

/// Keeps only user-chosen folder locations. No directory listing, file-content reading,
/// background upload or account connection is performed by this store.
@MainActor
final class CloudWorkspaceStore: ObservableObject {
    @Published private(set) var favorites: [CloudFavoriteFolder] = []
    @Published private(set) var iCloudDriveAvailable = false
    @Published private(set) var choosingFolder = false
    @Published var errorMessage: String?

    private let defaults: UserDefaults
    private let key = "ada.cloud.favoriteFolders.v1"
    private var folderPicker: NSOpenPanel?
    let iCloudDriveURL: URL
    let downloadsURL: URL

    init(defaults: UserDefaults = .standard, homeDirectory: URL? = nil) {
        self.defaults = defaults
        let home = homeDirectory ?? FileManager.default.homeDirectoryForCurrentUser
        iCloudDriveURL = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        downloadsURL = home.appendingPathComponent("Downloads", isDirectory: true)
        if let data = defaults.data(forKey: key),
           let saved = try? JSONDecoder().decode([CloudFavoriteFolder].self, from: data) {
            favorites = saved
        }
        refreshAvailability()
    }

    func refreshAvailability() {
        var directory: ObjCBool = false
        iCloudDriveAvailable = FileManager.default.fileExists(atPath: iCloudDriveURL.path, isDirectory: &directory) && directory.boolValue
    }

    func clearError() { errorMessage = nil }

    func chooseFolders() {
        errorMessage = nil
        if let folderPicker { folderPicker.makeKeyAndOrderFront(nil); return }
        let picker = NSOpenPanel()
        picker.title = "Klasör seç"
        picker.prompt = "Kısayol ekle"
        picker.canChooseDirectories = true
        picker.canChooseFiles = false
        picker.canCreateDirectories = false
        picker.allowsMultipleSelection = true
        folderPicker = picker
        choosingFolder = true
        NSApp.activate(ignoringOtherApps: true)
        picker.begin { [weak self] response in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.folderPicker = nil
                self.choosingFolder = false
                guard response == .OK else { return }
                self.addFolders(picker.urls)
            }
        }
    }

    /// Called only for folders explicitly selected by the user (also useful for isolated checks).
    func addFolders(_ urls: [URL]) {
        var rejected = false
        errorMessage = nil
        for originalURL in urls {
            let url = originalURL.standardizedFileURL
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            var isDirectory: ObjCBool = false
            guard url.isFileURL,
                  FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                rejected = true
                continue
            }
            guard !favorites.contains(where: { $0.fallbackPath == url.path }) else { continue }
            let bookmark = (try? url.bookmarkData(options: .withSecurityScope,
                includingResourceValuesForKeys: nil, relativeTo: nil)) ??
                (try? url.bookmarkData(options: .minimalBookmark,
                    includingResourceValuesForKeys: nil, relativeTo: nil))
            let name = url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
            favorites.append(CloudFavoriteFolder(name: name, bookmark: bookmark, fallbackPath: url.path))
        }
        persist()
        if rejected { errorMessage = "Bazı klasörler eklenemedi." }
    }

    func removeFavorite(_ id: UUID) {
        // This removes only a shortcut, never the folder or its contents.
        favorites.removeAll { $0.id == id }
        persist()
    }

    func openFavorite(_ favorite: CloudFavoriteFolder) {
        guard let url = resolve(favorite) else { return }
        openFolder(url)
    }

    func revealFavorite(_ favorite: CloudFavoriteFolder) {
        guard let url = resolve(favorite) else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard folderExists(url) else {
            errorMessage = "“\(favorite.name)” bulunamadı. Kısayolu yeniden ekle."
            return
        }
        errorMessage = nil
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openICloudDrive() {
        refreshAvailability()
        guard iCloudDriveAvailable else {
            errorMessage = "iCloud Drive klasörü bulunamadı."
            return
        }
        openFolder(iCloudDriveURL)
    }

    func openDownloads() { openFolder(downloadsURL) }

    func openWeb(_ service: CloudWebService) {
        guard service.url.scheme == "https", CloudWebService.all.contains(where: { $0.url == service.url }) else { return }
        errorMessage = nil
        if !NSWorkspace.shared.open(service.url) { errorMessage = "Tarayıcı açılamadı." }
    }

    private func resolve(_ favorite: CloudFavoriteFolder) -> URL? {
        errorMessage = nil
        if let bookmark = favorite.bookmark {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: bookmark,
                options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale) {
                if stale { refreshBookmark(for: favorite.id, url: url) }
                return url
            }
            // Basic bookmarks may not be security-scoped on an unsandboxed personal build.
            if let url = try? URL(resolvingBookmarkData: bookmark,
                options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale) {
                if stale { refreshBookmark(for: favorite.id, url: url) }
                return url
            }
        }
        let fallback = URL(fileURLWithPath: favorite.fallbackPath, isDirectory: true)
        guard folderExists(fallback) else {
            errorMessage = "“\(favorite.name)” açılamadı. Kısayolu yeniden ekle."
            return nil
        }
        return fallback
    }

    private func refreshBookmark(for id: UUID, url: URL) {
        guard let index = favorites.firstIndex(where: { $0.id == id }) else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        if let data = (try? url.bookmarkData(options: .withSecurityScope,
            includingResourceValuesForKeys: nil, relativeTo: nil)) ??
            (try? url.bookmarkData(options: .minimalBookmark,
                includingResourceValuesForKeys: nil, relativeTo: nil)) {
            favorites[index].bookmark = data
            favorites[index].fallbackPath = url.path
            favorites[index].name = url.lastPathComponent
            persist()
        }
    }

    private func openFolder(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard folderExists(url) else { errorMessage = "Klasör bulunamadı veya erişilemiyor."; return }
        errorMessage = nil
        if !NSWorkspace.shared.open(url) { errorMessage = "Klasör Finder’da açılamadı." }
    }

    private func folderExists(_ url: URL) -> Bool {
        var directory: ObjCBool = false
        return url.isFileURL && FileManager.default.fileExists(atPath: url.path, isDirectory: &directory) && directory.boolValue
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(favorites) { defaults.set(data, forKey: key) }
    }
}

struct CloudWorkspaceView: View {
    @ObservedObject var store: CloudWorkspaceStore
    var accent: Color = .blue

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                localPlaces.frame(width: 178)
                favoriteFolders.frame(maxWidth: .infinity)
                webServices.frame(width: 220)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            if let error = store.errorMessage {
                HStack(spacing: 7) {
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                    Text(error).font(.system(size: 10)).lineLimit(2)
                    Spacer(minLength: 0)
                    Button("Kapat", action: store.clearError).buttonStyle(IslandButtonStyle()).foregroundStyle(accent)
                }
            }
        }
        .foregroundStyle(.white)
        .onAppear { store.refreshAvailability() }
    }

    private var localPlaces: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Bu Mac").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
            locationButton("iCloud Drive", subtitle: store.iCloudDriveAvailable ? nil : "Bu Mac’te yok",
                           symbol: "icloud", action: store.openICloudDrive)
            locationButton("İndirilenler", symbol: "arrow.down.circle", action: store.openDownloads)
        }.cloudCard()
    }

    private var favoriteFolders: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label("Sabit klasörler", systemImage: "pin").font(.system(size: 11, weight: .semibold))
                Spacer()
                Button(action: store.chooseFolders) {
                    Label("Ekle", systemImage: "plus").font(.system(size: 10, weight: .medium))
                }.buttonStyle(IslandButtonStyle()).foregroundStyle(accent)
            }
            if store.favorites.isEmpty {
                VStack(spacing: 7) {
                    Image(systemName: "folder.badge.plus").font(.system(size: 24, weight: .light)).foregroundStyle(accent.opacity(0.7))
                    Text("Henüz klasör yok")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.62))
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 5) {
                        ForEach(store.favorites) { folder in
                            HStack(spacing: 7) {
                                Button { store.openFavorite(folder) } label: {
                                    HStack(spacing: 7) {
                                        Image(systemName: "folder.fill").foregroundStyle(accent)
                                        Text(folder.name).lineLimit(1)
                                        Spacer(minLength: 0)
                                        Image(systemName: "arrow.up.right").font(.system(size: 8)).foregroundStyle(.white.opacity(0.35))
                                    }.contentShape(Rectangle())
                                }.buttonStyle(IslandButtonStyle())
                                Button { store.removeFavorite(folder.id) } label: {
                                    Image(systemName: "xmark").font(.system(size: 8)).foregroundStyle(.white.opacity(0.35))
                                }.buttonStyle(IslandButtonStyle()).help("Kısayolu kaldır").accessibilityLabel("\(folder.name) kısayolunu kaldır")
                            }
                            .font(.system(size: 11, weight: .medium)).padding(7)
                            .background(.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 9))
                            .contextMenu {
                                Button("Finder’da aç") { store.openFavorite(folder) }
                                Button("Finder’da göster") { store.revealFavorite(folder) }
                                Divider()
                                Button("Kısayolu kaldır") { store.removeFavorite(folder.id) }
                            }
                        }
                    }
                }.scrollIndicators(.hidden)
            }
        }.cloudCard()
    }

    private var webServices: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Web kısayolları").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
            ForEach(CloudWebService.all) { service in
                Button { store.openWeb(service) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: service.symbol).frame(width: 16).foregroundStyle(accent)
                        Text(service.name).font(.system(size: 11, weight: .medium))
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.system(size: 8)).foregroundStyle(.white.opacity(0.55))
                    }.padding(.vertical, 3).contentShape(Rectangle())
                }.buttonStyle(IslandButtonStyle()).help("\(service.name) web sitesini aç")
            }
        }.cloudCard()
    }

    private func locationButton(_ title: String, subtitle: String? = nil, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: symbol).font(.system(size: 18)).foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 11, weight: .semibold))
                    if let subtitle {
                        Text(subtitle).font(.system(size: 10)).foregroundStyle(.white.opacity(0.60))
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(9).background(.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 11))
        }.buttonStyle(IslandButtonStyle()).help("\(title) klasörünü Finder’da aç")
    }
}

private struct CloudCard: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 17))
            .overlay(RoundedRectangle(cornerRadius: 17).strokeBorder(.white.opacity(0.08), lineWidth: 0.8))
    }
}

private extension View {
    func cloudCard() -> some View { modifier(CloudCard()) }
}
