import Foundation

public enum MediaSource: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case spotify, appleMusic
    public var id: String { rawValue }
    public var bundleIdentifier: String { self == .spotify ? "com.spotify.client" : "com.apple.Music" }
}


public struct NowPlayingTiming: Equatable, Sendable {
    public let duration: TimeInterval
    public let position: TimeInterval
    public let sampledAt: Date

    public init?(source: MediaSource, rawDuration: Double, position: TimeInterval, sampledAt: Date) {
        // Spotify's desktop scripting bridge returns track duration in milliseconds.
        let duration = source == .spotify ? rawDuration / 1_000 : rawDuration
        guard duration.isFinite, duration > 0, duration <= Double(Int32.max),
              position.isFinite, position >= 0, position <= duration + 3 else { return nil }
        self.duration = duration
        self.position = min(position, duration)
        self.sampledAt = sampledAt
    }

    public func elapsed(at date: Date, isPlaying: Bool) -> TimeInterval {
        let advance = isPlaying ? max(0, date.timeIntervalSince(sampledAt)) : 0
        return min(duration, position + advance)
    }
}

// Metadata stays independent of AppKit images so selection and stale replies are testable.
public struct NowPlayingMetadata: Equatable, Sendable {
    public let source: MediaSource
    public let identifier: String
    public let title: String
    public let artist: String
    public let album: String
    public let isPlaying: Bool
    public var artworkURL: URL? = nil
    public var artworkData: Data? = nil
    public var timing: NowPlayingTiming? = nil
    public init(source: MediaSource, identifier: String, title: String, artist: String, album: String,
                isPlaying: Bool, artworkURL: URL? = nil, artworkData: Data? = nil, timing: NowPlayingTiming? = nil) {
        self.source = source; self.identifier = identifier; self.title = title; self.artist = artist
        self.album = album; self.isPlaying = isPlaying; self.artworkURL = artworkURL
        self.artworkData = artworkData; self.timing = timing
    }
    public var id: String { "\(source.rawValue):\(identifier.isEmpty ? title + "\u{1f}" + artist + "\u{1f}" + album : identifier)" }
}

public enum NowPlayingPolicy {
    public static func choose(_ candidates: [NowPlayingMetadata], previousSource: MediaSource?, newlyPlaying: Set<MediaSource>) -> NowPlayingMetadata? {
        let valid = candidates.filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let playing = valid.filter(\.isPlaying)
        if let fresh = playing.first(where: { newlyPlaying.contains($0.source) && $0.source != previousSource }) { return fresh }
        if let previous = playing.first(where: { $0.source == previousSource }) { return previous }
        if let playing = playing.first { return playing }
        return valid.first(where: { $0.source == previousSource }) ?? valid.first
    }

    public static func acceptsReply(generation: UInt64, current: UInt64, enabled: Bool) -> Bool {
        enabled && generation == current
    }

    public static func artworkURLAllowed(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", url.user == nil, url.password == nil,
              let host = url.host?.lowercased(), url.port == nil || url.port == 443 else { return false }
        return host == "scdn.co" || host.hasSuffix(".scdn.co") || host == "spotifycdn.com" || host.hasSuffix(".spotifycdn.com")
    }
}

public enum MediaRefreshKind: Equatable, Sendable { case none, full, position }
public struct MediaRefreshCadence: Sendable {
    public init() {}
    public var lastSignal: Date?
    public var lastFullRead: Date?
    public var lastPositionRead: Date?
    public func next(at now: Date, panelOpen: Bool, playing: Bool, hasMetadata: Bool) -> MediaRefreshKind {
        let receivesSignals = lastSignal.map { now.timeIntervalSince($0) < 120 } ?? false
        let interval: TimeInterval = receivesSignals ? 30 : 2
        if lastFullRead.map({ now.timeIntervalSince($0) >= interval }) ?? true { return .full }
        if panelOpen && playing && hasMetadata &&
            (lastPositionRead.map { now.timeIntervalSince($0) >= 5 } ?? true) { return .position }
        return .none
    }
}
