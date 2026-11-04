import AppKit
import Foundation

@main struct NowPlayingChecks {
    @MainActor static func main() {
        func expect(_ value: Bool, _ label: String) { precondition(value, label) }
        let spotifyPaused = NowPlayingMetadata(source: .spotify, identifier: "spotify:track:a", title: "A", artist: "Artist", album: "Album", isPlaying: false)
        let spotifyPlaying = NowPlayingMetadata(source: .spotify, identifier: "spotify:track:a", title: "A", artist: "Artist", album: "Album", isPlaying: true)
        let musicPlaying = NowPlayingMetadata(source: .appleMusic, identifier: "persistent-b", title: "B", artist: "Singer", album: "Record", isPlaying: true)
        let musicPaused = NowPlayingMetadata(source: .appleMusic, identifier: "persistent-b", title: "B", artist: "Singer", album: "Record", isPlaying: false)
        expect(NowPlayingPolicy.choose([spotifyPaused, musicPlaying], previousSource: .spotify, newlyPlaying: [])?.source == .appleMusic, "Playing player takes precedence over remembered paused player")
        expect(NowPlayingPolicy.choose([spotifyPlaying, musicPlaying], previousSource: .appleMusic, newlyPlaying: [])?.source == .appleMusic, "Simultaneously playing players do not flicker with poll order")
        expect(NowPlayingPolicy.choose([spotifyPlaying, musicPlaying], previousSource: .spotify, newlyPlaying: [.appleMusic])?.source == .appleMusic, "New playback takes over compact island")
        expect(NowPlayingPolicy.choose([spotifyPaused, musicPaused], previousSource: .appleMusic, newlyPlaying: [])?.source == .appleMusic, "Pause retains the last selected album artwork")
        expect(NowPlayingPolicy.choose([], previousSource: .appleMusic, newlyPlaying: []) == nil, "Quit and stopped players clear the compact state")
        let blank = NowPlayingMetadata(source: .appleMusic, identifier: "x", title: " \n", artist: "", album: "", isPlaying: true)
        expect(NowPlayingPolicy.choose([blank, spotifyPaused], previousSource: .appleMusic, newlyPlaying: [.appleMusic])?.source == .spotify, "Blank metadata does not invent a playing track")
        let a = NowPlayingMetadata(source: .spotify, identifier: "", title: "A", artist: "B", album: "C", isPlaying: true)
        let b = NowPlayingMetadata(source: .spotify, identifier: "", title: "A", artist: "B", album: "D", isPlaying: true)
        expect(a.id != b.id, "Tracks without persistent IDs retain distinct artwork keys")
        expect(NowPlayingPolicy.acceptsReply(generation: 2, current: 2, enabled: true), "Current active query applies")
        expect(!NowPlayingPolicy.acceptsReply(generation: 1, current: 2, enabled: true), "Replies from before disabling/re-enabling cannot resurrect stale tracks")
        expect(!NowPlayingPolicy.acceptsReply(generation: 2, current: 2, enabled: false), "Disabled media remains empty after an in-flight reply")
        expect(NowPlayingPolicy.artworkURLAllowed(URL(string: "https://i.scdn.co/image/album")!), "Official Spotify art is accepted")
        expect(NowPlayingPolicy.artworkURLAllowed(URL(string: "https://image-cdn-ak.spotifycdn.com/image/album")!), "Official alternate CDN is accepted")
        for url in ["http://i.scdn.co/image", "file:///tmp/song.jpg", "https://scdn.co.attacker.invalid/image", "https://attacker-scdn.co/image", "https://user:secret@i.scdn.co/image", "https://127.0.0.1/image", "https://i.scdn.co:8080/image"] {
            expect(!NowPlayingPolicy.artworkURLAllowed(URL(string: url)!), "Untrusted artwork URL is rejected: \(url)")
        }
        expect(MediaSource.spotify.bundleIdentifier != MediaSource.appleMusic.bundleIdentifier, "Players have independent routing")
        let store = NowPlayingStore()
        expect(!store.isEnabled && store.track == nil && store.tracks.isEmpty && !store.isPlaying, "Creation does not read apps, request permissions or start music")
        store.refresh()
        store.playPause()
        store.next()
        store.previous()
        expect(!store.isControlling && store.track == nil, "Disabled controls do not launch or send commands to players")
        store.stop()
        expect(!store.isEnabled && store.track == nil, "Disabled lifecycle is idempotent")
        print("PASS: now-playing source arbitration, pause retention, stopped/blank handling, artwork identity and HTTPS allowlist, stale reply rejection, disabled lifecycle; no player launch or playback")
    }
}
