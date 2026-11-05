import AdaCore
import AppKit
import Combine
import Foundation
import Carbon
import ImageIO

extension MediaSource {
    var title: String { self == .spotify ? L10n.string("Spotify") : L10n.string("Apple Müzik") }
    var symbol: String { self == .spotify ? "waveform.circle.fill" : "music.note" }
    var applicationURL: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) }
    var isInstalled: Bool { applicationURL != nil }
    fileprivate var eventClass: AEEventClass { mediaCode(self == .spotify ? "spfy" : "hook") }
}

struct NowPlayingTrack: Identifiable {
    let id: String
    let source: MediaSource
    let title: String
    let artist: String
    let album: String
    let isPlaying: Bool
    var artwork: NSImage?
    var timing: NowPlayingTiming? = nil
}

@MainActor
final class NowPlayingStore: ObservableObject {
    @Published private(set) var track: NowPlayingTrack?
    @Published private(set) var tracks: [MediaSource: NowPlayingTrack] = [:]
    @Published private(set) var status: String?
    @Published private(set) var isEnabled = false
    @Published private(set) var isControlling = false

    var isPlaying: Bool { track?.isPlaying == true }
    var permissionDenied: Bool { !deniedSources.isEmpty }
    private let worker = DispatchQueue(label: "dev.ada.island.now-playing", qos: .utility)
    private var timer: Timer?
    private var generation: UInt64 = 0
    private var panelOpen = false
    private var cadence: [MediaSource: MediaRefreshCadence] = [:]
    private var eventObservers: [NSObjectProtocol] = []
    private var eventRefresh: DispatchWorkItem?
    private var refreshQueued = false
    private var polling = false
    private var deniedSources = Set<MediaSource>()
    private var previousMetadata: [MediaSource: NowPlayingMetadata] = [:]
    private var artworkCache: [String: NSImage] = [:]
    private var artworkLoads: [MediaSource: MediaArtworkRequest] = [:]
    private var artworkRetryAfter: [String: Date] = [:]

    init(previewTrack: NowPlayingTrack? = nil) {
        track = previewTrack
        if let previewTrack { tracks[previewTrack.source] = previewTrack }
    }

    #if compiler(>=6.2)
    isolated deinit { cleanup() }
    #else
    // Older toolchains: owners and test fixtures release this UI store on main.
    deinit { MainActor.assumeIsolated { cleanup() } }
    #endif
    private func cleanup() {
        timer?.invalidate(); eventRefresh?.cancel()
        eventObservers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
        artworkLoads.values.forEach { $0.cancel() }
    }

    func setPanelOpen(_ open: Bool) { panelOpen = open }

    private func installPlaybackObservers() {
        let names: [(String, MediaSource)] = [("com.spotify.client.PlaybackStateChanged", .spotify),
            ("com.apple.Music.playerInfo", .appleMusic), ("com.apple.iTunes.playerInfo", .appleMusic)]
        for (name, source) in names {
            let token = DistributedNotificationCenter.default().addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.isEnabled else { return }
                    // Notification payloads are untrusted hints. Read the running
                    // player's PID through public Apple Events, never its payload.
                    self.cadence[source, default: MediaRefreshCadence()].lastSignal = Date()
                    self.eventRefresh?.cancel()
                    let task = DispatchWorkItem { [weak self] in self?.refresh() }
                    self.eventRefresh = task
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: task)
                }
            }
            eventObservers.append(token)
        }
    }

    func track(for source: MediaSource) -> NowPlayingTrack? { tracks[source] }
    func permissionDenied(for source: MediaSource) -> Bool { deniedSources.contains(source) }
    func start() { setEnabled(true) }
    func stop() { setEnabled(false) }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        generation &+= 1
        isEnabled = enabled
        timer?.invalidate()
        timer = nil
        if enabled {
            installPlaybackObservers()
            let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh(forceFull: false) }
            }
            timer.tolerance = 0.3
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
            refresh()
        } else {
            eventRefresh?.cancel(); eventRefresh = nil
            eventObservers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
            eventObservers.removeAll(); cadence.removeAll(); refreshQueued = false
            artworkLoads.values.forEach { $0.cancel() }
            artworkLoads.removeAll()
            previousMetadata.removeAll()
            artworkRetryAfter.removeAll()
            tracks = [:]
            track = nil
            status = nil
        }
    }

    func retryPermissions() {
        deniedSources.removeAll()
        status = nil
        refresh()
    }

    func openAutomationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") else { return }
        NSWorkspace.shared.open(url)
    }

    func refresh(forceFull: Bool = true) {
        guard isEnabled else { return }
        guard !polling, !isControlling else {
            if forceFull { refreshQueued = true }
            return
        }
        let running: [(MediaSource, pid_t)] = MediaSource.allCases.compactMap { source in
            guard !deniedSources.contains(source),
                  let app = NSRunningApplication.runningApplications(withBundleIdentifier: source.bundleIdentifier).first,
                  !app.isTerminated else { return nil }
            return (source, app.processIdentifier)
        }
        let runningSources = Set(running.map(\.0))
        // Remove quit players promptly, including while another player's request is pending.
        for source in tracks.keys where !runningSources.contains(source) {
            tracks[source] = nil
            previousMetadata[source] = nil
            artworkLoads.removeValue(forKey: source)?.cancel()
        }
        if let current = track, !runningSources.contains(current.source) { track = nil }
        guard !running.isEmpty else {
            track = nil
            publishPermissionStatus()
            return
        }
        let date = Date()
        let plans = running.map { source, pid -> (MediaSource, pid_t, MediaRefreshKind, NowPlayingMetadata?) in
            let cached = previousMetadata[source]
            let kind: MediaRefreshKind = forceFull ? .full : cadence[source, default: MediaRefreshCadence()].next(
                at: date, panelOpen: panelOpen, playing: cached?.isPlaying == true, hasMetadata: cached != nil)
            if kind == .full { cadence[source, default: MediaRefreshCadence()].lastFullRead = date }
            if kind != .none { cadence[source, default: MediaRefreshCadence()].lastPositionRead = date }
            return (source, pid, kind, cached)
        }
        guard plans.contains(where: { $0.2 != .none }) else { return }
        polling = true
        let requestGeneration = generation
        let cachedIDs = Set(artworkCache.keys)
        worker.async { [weak self] in
            let results = plans.map { source, pid, kind, cached -> MediaReadResult in
                autoreleasepool {
                    switch kind {
                    case .none: return MediaReadResult(source: source, metadata: cached)
                    case .full: return MediaAppleEvents.read(source: source, pid: pid, cachedArtworkIDs: cachedIDs)
                    case .position: return MediaAppleEvents.readPosition(source: source, pid: pid, cached: cached, cachedArtworkIDs: cachedIDs)
                    }
                }
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.polling = false
                guard NowPlayingPolicy.acceptsReply(generation: requestGeneration, current: self.generation, enabled: self.isEnabled) else { return }
                // A player can quit during a request. Do not briefly resurrect its artwork.
                let liveSources = Set(MediaSource.allCases.filter {
                    !NSRunningApplication.runningApplications(withBundleIdentifier: $0.bundleIdentifier).isEmpty
                })
                var snapshots: [NowPlayingMetadata] = []
                var newlyPlaying = Set<MediaSource>()
                for result in results where liveSources.contains(result.source) {
                    if result.errorCode == -1743 { self.deniedSources.insert(result.source) }
                    if let metadata = result.metadata {
                        if metadata.isPlaying && self.previousMetadata[metadata.source]?.isPlaying != true {
                            newlyPlaying.insert(metadata.source)
                        }
                        snapshots.append(metadata)
                    }
                }
                self.apply(snapshots, newlyPlaying: newlyPlaying)
                self.publishPermissionStatus()
                if self.refreshQueued { self.refreshQueued = false; self.refresh() }
            }
        }
    }

    func openSource(_ source: MediaSource? = nil) {
        let source = source ?? track?.source ?? .appleMusic
        guard let url = source.applicationURL else {
            if let webURL = URL(string: source == .spotify ? "https://open.spotify.com" : "https://music.apple.com") {
                NSWorkspace.shared.open(webURL)
            }
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { [weak self] _, error in
            guard error != nil else { return }
            Task { @MainActor in self?.status = L10n.string("\(source.title) açılamadı.") }
        }
    }

    func playPause(source: MediaSource? = nil) { control(.transport("PlPs"), source: source) }
    func next(source: MediaSource? = nil) { control(.transport("Next"), source: source) }
    func previous(source: MediaSource? = nil) { control(.transport("Prev"), source: source) }

    func seek(to position: TimeInterval, in track: NowPlayingTrack) {
        guard position.isFinite,
              let current = tracks[track.source], current.id == track.id,
              let duration = current.timing?.duration else { return }
        control(.seek(min(max(position, 0), duration)), source: track.source)
    }

    private enum PlaybackCommand: Sendable {
        case transport(String)
        case seek(TimeInterval)
    }

    private func control(_ command: PlaybackCommand, source: MediaSource?) {
        guard isEnabled, !isControlling, let source = source ?? track?.source,
              tracks[source] != nil,
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: source.bundleIdentifier).first,
              !app.isTerminated else { return }
        isControlling = true
        let pid = app.processIdentifier
        let requestGeneration = generation
        worker.async { [weak self] in
            let errorCode: Int? = autoreleasepool {
                do {
                    switch command {
                    case .seek(let position):
                        try MediaAppleEvents.seek(source: source, pid: pid, to: position)
                    case .transport(let command):
                        _ = try MediaAppleEvents.send(source: source, pid: pid, eventClass: source.eventClass,
                                                      eventID: mediaCode(command), object: nil, timeout: 1)
                    }
                    return nil
                } catch { return MediaAppleEvents.errorCode(error) }
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isControlling = false
                guard NowPlayingPolicy.acceptsReply(generation: requestGeneration, current: self.generation, enabled: self.isEnabled) else { return }
                if errorCode == -1743 {
                    self.deniedSources.insert(source)
                    self.publishPermissionStatus()
                } else if errorCode != nil {
                    self.status = L10n.string("\(source.title) yanıt vermedi.")
                }
                self.refreshQueued = false
                self.refresh()
            }
        }
    }

    private func apply(_ snapshots: [NowPlayingMetadata], newlyPlaying: Set<MediaSource>) {
        let selected = NowPlayingPolicy.choose(snapshots, previousSource: track?.source, newlyPlaying: newlyPlaying)
        let activeSources = Set(snapshots.map(\.source))
        for source in artworkLoads.keys where !activeSources.contains(source) {
            artworkLoads.removeValue(forKey: source)?.cancel()
        }
        var nextTracks: [MediaSource: NowPlayingTrack] = [:]
        for metadata in snapshots {
            if let request = artworkLoads[metadata.source], request.identifier != metadata.id {
                artworkLoads.removeValue(forKey: metadata.source)?.cancel()
            }
            if let data = metadata.artworkData, let image = Self.decodeArtwork(data) { artworkCache[metadata.id] = image }
            let value = NowPlayingTrack(id: metadata.id, source: metadata.source, title: metadata.title,
                                        artist: metadata.artist, album: metadata.album, isPlaying: metadata.isPlaying,
                                        artwork: artworkCache[metadata.id], timing: metadata.timing)
            nextTracks[metadata.source] = value
            if artworkCache[metadata.id] == nil, let url = metadata.artworkURL,
               NowPlayingPolicy.artworkURLAllowed(url), artworkLoads[metadata.source]?.identifier != metadata.id,
               (artworkRetryAfter[metadata.id] ?? .distantPast) <= Date() {
                artworkLoads.removeValue(forKey: metadata.source)?.cancel()
                let requestGeneration = generation
                let identifier = metadata.id
                let source = metadata.source
                let request = MediaArtworkRequest(identifier: identifier, url: url) { [weak self] data in
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.generation == requestGeneration, self.isEnabled,
                              self.tracks[source]?.id == identifier else { return }
                        self.artworkLoads[source] = nil
                        guard let data, let image = Self.decodeArtwork(data) else {
                            self.artworkRetryAfter[identifier] = Date().addingTimeInterval(60)
                            return
                        }
                        self.artworkRetryAfter[identifier] = nil
                        self.artworkCache[identifier] = image
                        self.tracks[source]?.artwork = image
                        if self.track?.id == identifier { self.track?.artwork = image }
                        self.trimArtworkCache()
                    }
                }
                artworkLoads[source] = request
                request.start()
            }
        }
        previousMetadata = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.source, $0) })
        tracks = nextTracks
        track = selected.flatMap { nextTracks[$0.source] }
        trimArtworkCache()
    }

    private func publishPermissionStatus() {
        if !deniedSources.isEmpty {
            status = deniedSources.sorted { $0.rawValue < $1.rawValue }.map(\.title).joined(separator: " / ") + L10n.string(" için Otomasyon izni gerekli.")
        } else { status = nil }
    }

    private func trimArtworkCache() {
        if artworkCache.count > 16 {
            let currentIDs = Set(tracks.values.map(\.id))
            artworkCache = artworkCache.filter { currentIDs.contains($0.key) }
        }
        artworkRetryAfter = artworkRetryAfter.filter { $0.value > Date() }
    }

    private static func decodeArtwork(_ data: Data) -> NSImage? {
        guard !data.isEmpty, data.count <= MediaArtworkRequest.maximumBytes,
              let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 512,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }
}
