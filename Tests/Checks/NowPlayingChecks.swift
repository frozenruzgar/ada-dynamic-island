@testable import Ada
@testable import AdaCore
import AppKit
import Foundation

enum NowPlayingChecks {
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
        let sampledAt = Date(timeIntervalSinceReferenceDate: 10)
        let spotifyTiming = NowPlayingTiming(source: .spotify, rawDuration: 180_000, position: 40, sampledAt: sampledAt)
        let musicTiming = NowPlayingTiming(source: .appleMusic, rawDuration: 180, position: 40, sampledAt: sampledAt)
        expect(spotifyTiming != nil && spotifyTiming == musicTiming, "Both players report a timeline in seconds after normalization")
        expect(spotifyTiming?.elapsed(at: sampledAt.addingTimeInterval(5), isPlaying: true) == 45, "A playing timeline advances from the sampled position")
        expect(spotifyTiming?.elapsed(at: sampledAt.addingTimeInterval(5), isPlaying: false) == 40, "A paused timeline stays at the sampled position")
        expect(spotifyTiming?.elapsed(at: sampledAt.addingTimeInterval(500), isPlaying: true) == 180, "Timeline does not run past the end of the track")
        expect(NowPlayingTiming(source: .appleMusic, rawDuration: 180, position: -1, sampledAt: sampledAt) == nil, "Invalid player timing does not produce a seekable timeline")
        let now = Date()
        var cadence = MediaRefreshCadence()
        expect(cadence.next(at: now, panelOpen: false, playing: true, hasMetadata: true) == .full, "Initial metadata read")
        cadence.lastFullRead = now; cadence.lastPositionRead = now
        expect(cadence.next(at: now.addingTimeInterval(2), panelOpen: false, playing: true, hasMetadata: true) == .full, "No signals retains old fallback")
        cadence.lastSignal = now
        expect(cadence.next(at: now.addingTimeInterval(10), panelOpen: false, playing: true, hasMetadata: true) == .none, "Healthy notifications suppress closed metadata polling")
        expect(cadence.next(at: now.addingTimeInterval(5), panelOpen: true, playing: true, hasMetadata: true) == .position, "Open playback samples only timing")
        expect(cadence.next(at: now.addingTimeInterval(5), panelOpen: true, playing: false, hasMetadata: true) == .none, "Paused playback has no position sampling")
        expect(cadence.next(at: now.addingTimeInterval(30), panelOpen: false, playing: true, hasMetadata: true) == .full, "Periodic metadata safety check")
        expect(cadence.next(at: now.addingTimeInterval(121), panelOpen: false, playing: true, hasMetadata: true) == .full, "Stale notifications restore fallback")
        let store = NowPlayingStore()
        expect(!store.isEnabled && store.track == nil && store.tracks.isEmpty && !store.isPlaying, "Creation does not read apps, request permissions or start music")
        store.refresh()
        store.playPause()
        store.next()
        store.previous()
        expect(!store.isControlling && store.track == nil, "Disabled controls do not launch or send commands to players")
        store.stop()
        expect(!store.isEnabled && store.track == nil, "Disabled lifecycle is idempotent")
        print("PASS: now-playing source arbitration, pause retention, stopped/blank handling, artwork identity and HTTPS allowlist, stale reply rejection, timing normalization and playback progression, disabled lifecycle; no player launch or playback")
    }
}
