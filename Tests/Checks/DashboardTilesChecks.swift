@testable import Ada
@testable import AdaCore
import AppKit
import Foundation

enum DashboardTilesChecks {
    @MainActor static func main() throws {
        let domain = "AdaDashboardTilesChecks-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }

        let battery = DashboardTile(kind: .battery)
        let focus = DashboardTile(kind: .focus)
        let store = DashboardLayoutStore(defaults: defaults, initialTiles: [battery, focus])
        precondition(store.tiles.map(\.kind) == [.battery, .focus])
        precondition(store.add(DashboardTile(kind: .spotify)))
        let firstSpotifyID = store.tiles.last!.id
        for _ in 0..<4 { precondition(store.add(DashboardTile(kind: .spotify))) }
        precondition(store.tiles.count == 3 && store.tiles.filter { $0.kind == .spotify }.count == 1)
        precondition(store.focusedTileID == firstSpotifyID)
        precondition(store.add(battery))
        precondition(Set(store.tiles.map(\.id)).count == 4)
        let spotifyID = store.tiles[2].id
        store.move(id: spotifyID, by: -2)
        precondition(store.tiles.first?.kind == .spotify)
        precondition(store.replace(id: spotifyID, with: DashboardTile(kind: .appleMusic)))
        precondition(store.tiles.first?.id == spotifyID && store.tiles.first?.kind == .appleMusic)

        let restored = DashboardLayoutStore(defaults: defaults, initialTiles: [DashboardTile(kind: .notes)])
        precondition(restored.tiles == store.tiles)
        restored.remove(id: spotifyID)
        precondition(restored.tiles.count == 3)
        restored.reset(to: [])
        precondition(DashboardLayoutStore(defaults: defaults).tiles.isEmpty)

        precondition(DashboardTile.validWebsiteURL("example.com/path?q=music")?.scheme == "https")
        precondition(DashboardTile.validWebsiteURL("http://example.com") == nil)
        precondition(DashboardTile.validWebsiteURL("javascript:alert(1)") == nil)
        precondition(DashboardTile.validWebsiteURL("file:///Applications/Music.app") == nil)
        precondition(DashboardTile.validWebsiteURL("https://name:secret@example.com") == nil)
        precondition(DashboardTile.validWebsiteURL("https://example.com/a b") == nil)
        precondition(!restored.add(DashboardTile(kind: .website, webURL: "http://example.com")))

        for _ in 0..<DashboardLayoutStore.maxTiles { precondition(restored.add(DashboardTile(kind: .chatGPT))) }
        precondition(!restored.add(DashboardTile(kind: .claude)))
        precondition(restored.tiles.count == DashboardLayoutStore.maxTiles)

        let validRecord = try JSONSerialization.jsonObject(with: JSONEncoder().encode(battery))
        let brokenRecord: [String: Any] = ["id": "broken", "kind": "notes"]
        let futureRecord: [String: Any] = ["id": UUID().uuidString, "kind": "aFutureWidget"]
        defaults.set(try JSONSerialization.data(withJSONObject: [validRecord, brokenRecord, futureRecord, validRecord]),
                     forKey: DashboardLayoutStore.storageKey)
        let partial = DashboardLayoutStore(defaults: defaults)
        precondition(partial.tiles.count == 2 && partial.tiles.allSatisfy { $0.kind == .battery })
        precondition(Set(partial.tiles.map(\.id)).count == 2)

        let spotifyDomain = domain + "-spotify"
        let spotifyDefaults = UserDefaults(suiteName: spotifyDomain)!
        defer { spotifyDefaults.removePersistentDomain(forName: spotifyDomain) }
        let firstSpotify = DashboardTile(kind: .spotify)
        let notes = DashboardTile(kind: .notes)
        let spotifyApp = DashboardTile(kind: .app, appBundleID: "com.spotify.client")
        let legacy = [battery, firstSpotify, notes, DashboardTile(kind: .spotify), spotifyApp, focus]
        spotifyDefaults.set(try JSONEncoder().encode(legacy), forKey: DashboardLayoutStore.storageKey)
        let singleSpotify = DashboardLayoutStore(defaults: spotifyDefaults)
        precondition(singleSpotify.tiles == [battery, firstSpotify, notes, focus])
        precondition(DashboardLayoutStore(defaults: spotifyDefaults).tiles == singleSpotify.tiles)
        precondition(singleSpotify.add(spotifyApp))
        precondition(singleSpotify.tiles.count == 4 && singleSpotify.focusedTileID == firstSpotify.id)
        precondition(singleSpotify.replace(id: battery.id, with: spotifyApp))
        precondition(singleSpotify.tiles.map(\.kind) == [.spotify, .notes, .focus])
        precondition(singleSpotify.tiles.first?.id == battery.id && singleSpotify.focusedTileID == battery.id)
        singleSpotify.reset(to: [firstSpotify])
        while singleSpotify.tiles.count < DashboardLayoutStore.maxTiles {
            precondition(singleSpotify.add(DashboardTile(kind: .notes)))
        }
        precondition(singleSpotify.add(DashboardTile(kind: .spotify)))
        precondition(singleSpotify.tiles.count == DashboardLayoutStore.maxTiles)
        precondition(singleSpotify.tiles.filter { $0.kind == .spotify }.count == 1)
        precondition(singleSpotify.focusedTileID == firstSpotify.id && singleSpotify.errorMessage == nil)

        let missingApp = DashboardTile(kind: .app, customName: "Missing", appBundleID: "dev.ada.missing")
        precondition(missingApp.isWellFormed && missingApp.appURL == nil)
        precondition(!DashboardTile.validApplication(at: URL(fileURLWithPath: "/tmp")))
        let music = URL(fileURLWithPath: "/System/Applications/Music.app")
        if FileManager.default.fileExists(atPath: music.path) {
            let application = DashboardTile.application(at: music)
            precondition(application?.appBundleID == "com.apple.Music")
            precondition(application?.appURL == music)
        }
        print("PASS: dashboard seeding, add/change/reorder/remove, persistence, empty layout, unique identities, limits, partial recovery, Spotify repeat selection, legacy duplicate cleanup, app aliases and replacement uniqueness, HTTPS validation and application validation")
    }
}
