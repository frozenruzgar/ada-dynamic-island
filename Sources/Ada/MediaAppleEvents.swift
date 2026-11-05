import AdaCore
import AppKit
import Carbon

struct MediaReadResult: Sendable {
    let source: MediaSource
    let metadata: NowPlayingMetadata?
    var errorCode: Int? = nil
}

// Raw public Apple events use each player's scripting dictionary. Targeting its PID,
// rather than its bundle URL, means background checks cannot launch a stopped app.
enum MediaAppleEvents {
    static func readPosition(source: MediaSource, pid: pid_t, cached: NowPlayingMetadata?, cachedArtworkIDs: Set<String>) -> MediaReadResult {
        guard var metadata = cached, !metadata.identifier.isEmpty, let timing = metadata.timing else {
            return read(source: source, pid: pid, cachedArtworkIDs: cachedArtworkIDs)
        }
        func get(_ property: String, container: NSAppleEventDescriptor = .null()) throws -> NSAppleEventDescriptor {
            try send(source: source, pid: pid, eventClass: mediaCode("core"), eventID: mediaCode("getd"),
                     object: propertyObject(property, container: container), timeout: 0.7)
        }
        do {
            let identifier = try get(source == .spotify ? "ID  " : "pPIS", container: propertyObject("pTrk")).stringValue
            let state = try get("pPlS").enumCodeValue
            let playing = ["kPSP", "kPSF", "kPSR"].contains { state == mediaCode($0) }
            guard identifier == metadata.identifier, playing == metadata.isPlaying else {
                return read(source: source, pid: pid, cachedArtworkIDs: cachedArtworkIDs)
            }
            let position = try get("pPos").coerce(toDescriptorType: typeIEEE64BitFloatingPoint)?.doubleValue ?? -1
            metadata.timing = NowPlayingTiming(source: source,
                rawDuration: source == .spotify ? timing.duration * 1_000 : timing.duration,
                position: position, sampledAt: Date()) ?? timing
            metadata.artworkData = nil
            return MediaReadResult(source: source, metadata: metadata)
        } catch { return MediaReadResult(source: source, metadata: cached, errorCode: errorCode(error)) }
    }

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
            if let duration = try? get("pDur", container: currentTrack).coerce(toDescriptorType: typeIEEE64BitFloatingPoint)?.doubleValue,
               let position = try? get("pPos").coerce(toDescriptorType: typeIEEE64BitFloatingPoint)?.doubleValue {
                metadata.timing = NowPlayingTiming(source: source, rawDuration: duration, position: position, sampledAt: Date())
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

    static func seek(source: MediaSource, pid: pid_t, to position: TimeInterval) throws {
        _ = try send(source: source, pid: pid, eventClass: kAECoreSuite, eventID: kAESetData,
                     object: propertyObject("pPos"), timeout: 1, value: NSAppleEventDescriptor(double: position))
    }

    static func send(source: MediaSource, pid: pid_t, eventClass: AEEventClass, eventID: AEEventID,
                     object: NSAppleEventDescriptor?, timeout: TimeInterval,
                     value: NSAppleEventDescriptor? = nil) throws -> NSAppleEventDescriptor {
        let event = NSAppleEventDescriptor(eventClass: eventClass, eventID: eventID,
                                          targetDescriptor: NSAppleEventDescriptor(processIdentifier: pid),
                                          returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        if let object { event.setParam(object, forKeyword: keyDirectObject) }
        if let value { event.setParam(value, forKeyword: keyAEData) }
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

func mediaCode(_ text: String) -> OSType {
    text.utf8.reduce(0) { ($0 << 8) | OSType($1) }
}
