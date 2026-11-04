import AppKit
import Combine
import Foundation
import Carbon
import ImageIO

enum MediaSource: String, CaseIterable, Identifiable, Codable, Hashable {
    case spotify, appleMusic
    var id: String { rawValue }
    var title: String { self == .spotify ? "Spotify" : "Apple Müzik" }
    var symbol: String { self == .spotify ? "waveform.circle.fill" : "music.note" }
    var bundleIdentifier: String { self == .spotify ? "com.spotify.client" : "com.apple.Music" }
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
}

// Metadata stays independent of AppKit images so selection and stale replies are testable.
struct NowPlayingMetadata: Equatable {
    let source: MediaSource
    let identifier: String
    let title: String
    let artist: String
    let album: String
    let isPlaying: Bool
    var artworkURL: URL? = nil
    var artworkData: Data? = nil
    var id: String { "\(source.rawValue):\(identifier.isEmpty ? title + "\u{1f}" + artist + "\u{1f}" + album : identifier)" }
}

enum NowPlayingPolicy {
    static func choose(_ candidates: [NowPlayingMetadata], previousSource: MediaSource?, newlyPlaying: Set<MediaSource>) -> NowPlayingMetadata? {
        let valid = candidates.filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let playing = valid.filter(\.isPlaying)
        if let fresh = playing.first(where: { newlyPlaying.contains($0.source) && $0.source != previousSource }) { return fresh }
        if let previous = playing.first(where: { $0.source == previousSource }) { return previous }
        if let playing = playing.first { return playing }
        return valid.first(where: { $0.source == previousSource }) ?? valid.first
    }

    static func acceptsReply(generation: UInt64, current: UInt64, enabled: Bool) -> Bool {
        enabled && generation == current
    }

    static func artworkURLAllowed(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", url.user == nil, url.password == nil,
              let host = url.host?.lowercased(), url.port == nil || url.port == 443 else { return false }
        return host == "scdn.co" || host.hasSuffix(".scdn.co") || host == "spotifycdn.com" || host.hasSuffix(".spotifycdn.com")
    }
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
    private var polling = false
    private var deniedSources = Set<MediaSource>()
    private var previousMetadata: [MediaSource: NowPlayingMetadata] = [:]
    private var artworkCache: [String: NSImage] = [:]
    private var artworkLoads: [MediaSource: MediaArtworkRequest] = [:]
    private var artworkRetryAfter: [String: Date] = [:]

    deinit { timer?.invalidate(); artworkLoads.values.forEach { $0.cancel() } }

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
            let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            timer.tolerance = 0.3
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
            refresh()
        } else {
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

    func refresh() {
        guard isEnabled, !polling else { return }
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
        polling = true
        let requestGeneration = generation
        let cachedIDs = Set(artworkCache.keys)
        worker.async { [weak self] in
            let results = running.map { source, pid -> MediaReadResult in
                autoreleasepool { MediaAppleEvents.read(source: source, pid: pid, cachedArtworkIDs: cachedIDs) }
            }
            DispatchQueue.main.async {
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
            Task { @MainActor in self?.status = "\(source.title) açılamadı." }
        }
    }

    func playPause(source: MediaSource? = nil) { control("PlPs", source: source) }
    func next(source: MediaSource? = nil) { control("Next", source: source) }
    func previous(source: MediaSource? = nil) { control("Prev", source: source) }

    private func control(_ command: String, source: MediaSource?) {
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
                    _ = try MediaAppleEvents.send(source: source, pid: pid, eventClass: source.eventClass,
                                                  eventID: mediaCode(command), object: nil, timeout: 1)
                    return nil
                } catch { return MediaAppleEvents.errorCode(error) }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.isControlling = false
                guard NowPlayingPolicy.acceptsReply(generation: requestGeneration, current: self.generation, enabled: self.isEnabled) else { return }
                if errorCode == -1743 {
                    self.deniedSources.insert(source)
                    self.publishPermissionStatus()
                } else if errorCode != nil {
                    self.status = "\(source.title) yanıt vermedi."
                }
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
                                        artwork: artworkCache[metadata.id])
            nextTracks[metadata.source] = value
            if artworkCache[metadata.id] == nil, let url = metadata.artworkURL,
               NowPlayingPolicy.artworkURLAllowed(url), artworkLoads[metadata.source]?.identifier != metadata.id,
               (artworkRetryAfter[metadata.id] ?? .distantPast) <= Date() {
                artworkLoads.removeValue(forKey: metadata.source)?.cancel()
                let requestGeneration = generation
                let identifier = metadata.id
                let source = metadata.source
                let request = MediaArtworkRequest(identifier: identifier, url: url) { [weak self] data in
                    DispatchQueue.main.async {
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
            status = deniedSources.sorted { $0.rawValue < $1.rawValue }.map(\.title).joined(separator: " / ") + " için Otomasyon izni gerekli."
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

private struct MediaReadResult {
    let source: MediaSource
    let metadata: NowPlayingMetadata?
    var errorCode: Int? = nil
}

// Raw public Apple events use each player's scripting dictionary. Targeting its PID,
// rather than its bundle URL, means background checks cannot launch a stopped app.
private enum MediaAppleEvents {
    static func read(source: MediaSource, pid: pid_t, cachedArtworkIDs: Set<String>) -> MediaReadResult {
        let deadline = Date().addingTimeInterval(3)
        func get(_ property: String, container: NSAppleEventDescriptor = .null()) throws -> NSAppleEventDescriptor {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { throw NSError(domain: NSOSStatusErrorDomain, code: -1712) }
            return try send(source: source, pid: pid, eventClass: mediaCode("core"), eventID: mediaCode("getd"),
                            object: propertyObject(property, container: container), timeout: min(0.7, remaining))
        }
        do {
            let state = try get("pPlS")
            let isPlaying = ["kPSP", "kPSF", "kPSR"].contains { state.enumCodeValue == mediaCode($0) }
            let isPaused = state.enumCodeValue == mediaCode("kPSp")
            guard isPlaying || isPaused else { return MediaReadResult(source: source, metadata: nil) }
            let currentTrack = propertyObject("pTrk")
            let title = try get("pnam", container: currentTrack).stringValue ?? ""
            guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return MediaReadResult(source: source, metadata: nil) }
            let artist = (try? get("pArt", container: currentTrack).stringValue) ?? ""
            let album = (try? get("pAlb", container: currentTrack).stringValue) ?? ""
            let identifier = (try? get(source == .spotify ? "ID  " : "pPIS", container: currentTrack).stringValue) ?? ""
            var metadata = NowPlayingMetadata(source: source, identifier: identifier, title: title,
                                              artist: artist, album: album, isPlaying: isPlaying)
            if !cachedArtworkIDs.contains(metadata.id) {
                if source == .spotify {
                    if let text = try? get("aUrl", container: currentTrack).stringValue, let url = URL(string: text), NowPlayingPolicy.artworkURLAllowed(url) {
                        metadata.artworkURL = url
                    }
                } else {
                    let artwork = elementObject("cArt", index: 1, container: currentTrack)
                    if let data = try? get("pRaw", container: artwork).data, data.count <= MediaArtworkRequest.maximumBytes {
                        metadata.artworkData = data
                    }
                }
            }
            return MediaReadResult(source: source, metadata: metadata)
        } catch {
            return MediaReadResult(source: source, metadata: nil, errorCode: errorCode(error))
        }
    }

    static func errorCode(_ error: Error) -> Int {
        let error = error as NSError
        return (error.userInfo[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? error.code
    }

    static func send(source: MediaSource, pid: pid_t, eventClass: AEEventClass, eventID: AEEventID,
                     object: NSAppleEventDescriptor?, timeout: TimeInterval) throws -> NSAppleEventDescriptor {
        let event = NSAppleEventDescriptor(eventClass: eventClass, eventID: eventID,
                                          targetDescriptor: NSAppleEventDescriptor(processIdentifier: pid),
                                          returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        if let object { event.setParam(object, forKeyword: keyDirectObject) }
        let reply = try event.sendEvent(options: [.waitForReply, .neverInteract, .dontRecord], timeout: timeout)
        if let number = reply.paramDescriptor(forKeyword: keyErrorNumber)?.int32Value, number != 0 {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(number))
        }
        return reply.paramDescriptor(forKeyword: keyDirectObject) ?? .null()
    }

    static func propertyObject(_ property: String, container: NSAppleEventDescriptor = .null()) -> NSAppleEventDescriptor {
        object(want: mediaCode("prop"), form: mediaCode("prop"), key: NSAppleEventDescriptor(typeCode: mediaCode(property)), container: container)
    }
    static func elementObject(_ element: String, index: Int32, container: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
        object(want: mediaCode(element), form: mediaCode("indx"), key: NSAppleEventDescriptor(int32: index), container: container)
    }
    private static func object(want: OSType, form: OSType, key: NSAppleEventDescriptor, container: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
        let record = NSAppleEventDescriptor.record()
        record.setDescriptor(NSAppleEventDescriptor(typeCode: want), forKeyword: mediaCode("want"))
        record.setDescriptor(NSAppleEventDescriptor(enumCode: form), forKeyword: mediaCode("form"))
        record.setDescriptor(key, forKeyword: mediaCode("seld"))
        record.setDescriptor(container, forKeyword: mediaCode("from"))
        return record.coerce(toDescriptorType: mediaCode("obj "))!
    }
}

private func mediaCode(_ text: String) -> OSType {
    text.utf8.reduce(0) { ($0 << 8) | OSType($1) }
}

private final class MediaArtworkRequest: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    static let maximumBytes = 3 * 1024 * 1024
    let identifier: String
    private let url: URL
    private let completion: (Data?) -> Void
    private var bytes = Data()
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private let taskLock = NSLock()
    private var completed = false
    private var rejected = false

    init(identifier: String, url: URL, completion: @escaping (Data?) -> Void) {
        self.identifier = identifier
        self.url = url
        self.completion = completion
    }
    func start() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 10
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
        let task = session.dataTask(with: url)
        taskLock.lock()
        self.session = session
        self.task = task
        taskLock.unlock()
        task.resume()
    }
    func cancel() {
        taskLock.lock()
        let task = self.task
        taskLock.unlock()
        task?.cancel()
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url.map(NowPlayingPolicy.artworkURLAllowed) == true ? request : nil)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let validStatus = (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
        let isImage = response.mimeType?.lowercased().hasPrefix("image/") == true
        rejected = !validStatus || !isImage || response.expectedContentLength > Int64(Self.maximumBytes)
        completionHandler(rejected ? .cancel : .allow)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard bytes.count + data.count <= Self.maximumBytes else { rejected = true; dataTask.cancel(); return }
        bytes.append(data)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard !completed else { return }
        completed = true
        completion(error == nil && !rejected ? bytes : nil)
        session.finishTasksAndInvalidate()
        taskLock.lock()
        self.session = nil
        self.task = nil
        taskLock.unlock()
    }
}
