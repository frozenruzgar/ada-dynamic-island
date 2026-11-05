import AdaCore
import AppKit
import SwiftUI

struct MediaTileView: View {
    @ObservedObject var store: NowPlayingStore
    let source: MediaSource
    let accent: Color

    private var currentTrack: NowPlayingTrack? { store.track(for: source) }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let track = currentTrack {
                Button { store.openSource(source) } label: {
                    HStack(spacing: 8) {
                        MediaArtworkView(image: track.artwork, size: 30)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(track.title).adaFont(size: 11, weight: .semibold).lineLimit(1)
                            Text(track.artist.isEmpty ? source.title : track.artist)
                                .adaFont(size: 9).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.right").adaFont(size: 8)
                            .foregroundStyle(Palette.tertiaryText)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(IslandButtonStyle(cornerRadius: 8))
                .help(L10n.string("\(source.title) uygulamasını aç"))

                HStack(spacing: 5) {
                    Button(action: openPlayer) {
                        HStack(spacing: 5) {
                            if source == .spotify {
                                SpotifyBrandIcon(size: 26)
                            }
                            Text(source.title).adaFont(size: 9, weight: .medium)
                                .foregroundStyle(.white.opacity(0.8)).lineLimit(1)
                        }.contentShape(Rectangle())
                    }
                    .buttonStyle(IslandButtonStyle(cornerRadius: 8))
                    .accessibilityLabel(L10n.string("\(source.title) uygulamasını aç"))
                    Spacer(minLength: 0)
                    transportButton("backward.end.fill", label: L10n.string("Önceki parça")) { store.previous(source: source) }
                    transportButton(track.isPlaying ? "pause.fill" : "play.fill",
                                    label: track.isPlaying ? L10n.string("Duraklat") : L10n.string("Oynat")) { store.playPause(source: source) }
                    transportButton("forward.end.fill", label: L10n.string("Sonraki parça")) { store.next(source: source) }
                }
                .animation(.easeInOut(duration: 0.18), value: track.isPlaying)
            } else {
                Button(action: openPlayer) {
                    HStack(spacing: 8) {
                        playerIcon
                        Text(source.title).adaFont(size: 12, weight: .semibold).lineLimit(1)
                        Spacer(minLength: 0)
                    }.contentShape(Rectangle())
                }
                .buttonStyle(IslandButtonStyle(cornerRadius: 8))
                .accessibilityLabel(L10n.string("\(source.title) uygulamasını aç"))
                HStack(spacing: 6) {
                    Text(source.isInstalled ? (store.permissionDenied(for: source) ? L10n.string("İzin gerekli") : L10n.string("Bir parça seç")) : L10n.string("Mac uygulaması gerekli"))
                        .adaFont(size: 9).foregroundStyle(Palette.tertiaryText).lineLimit(1)

                    Spacer(minLength: 0)
                    if source.isInstalled, store.permissionDenied(for: source) {
                        Button(L10n.string("İzinler"), action: store.openAutomationSettings)
                            .adaFont(size: 9, weight: .semibold)
                            .buttonStyle(IslandButtonStyle(cornerRadius: 100))
                            .foregroundStyle(accent)
                            .help(store.status ?? L10n.string("Müzik erişim izinlerini aç"))
                            .contextMenu { Button(L10n.string("Yeniden dene"), action: store.retryPermissions) }
                    } else {
                        Button(action: openPlayer) {
                            Text(source.isInstalled ? L10n.string("Aç") : L10n.string("Web’de aç"))
                                .adaFont(size: 10, weight: .semibold)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(.white.opacity(0.09), in: Capsule())
                        }
                            .buttonStyle(IslandButtonStyle(cornerRadius: 100))
                            .foregroundStyle(accent)
                    }
                }
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 19))
        .overlay(RoundedRectangle(cornerRadius: 19).strokeBorder(
            LinearGradient(colors: [.white.opacity(0.19), .white.opacity(0.055)],
                           startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.8))
        .foregroundStyle(.white)
    }

    private var playerIcon: some View {
        Group {
            if source == .spotify {
                SpotifyBrandIcon(size: 34)
            } else if let url = source.applicationURL {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable().interpolation(.high).scaledToFit()
            } else {
                Image(systemName: source.symbol)
                    .adaFont(size: 20, weight: .medium)
                    .foregroundStyle(accent)
                    .frame(width: 30, height: 30)
                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .frame(width: 34, height: 34)
        .accessibilityHidden(true)
    }

    private func transportButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .contentTransition(.opacity)
                .adaFont(size: 9, weight: .semibold)
                .frame(width: 22, height: 20)
                .background(.white.opacity(0.07), in: Capsule())
        }
        .buttonStyle(IslandButtonStyle(cornerRadius: 100))
        .disabled(store.isControlling)
        .accessibilityLabel(L10n.string("\(source.title) · \(label)"))
        .help(label)
    }

    private func openPlayer() {
        if source.isInstalled { store.openSource(source) }
        else {
            let address = source == .spotify ? "https://open.spotify.com" : "https://music.apple.com"
            if let url = URL(string: address) { NSWorkspace.shared.open(url) }
        }
    }
}

struct MediaArtworkView: View {
    let image: NSImage?
    let size: CGFloat
    var cornerRadius: CGFloat? = nil

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius ?? max(3, size * 0.2), style: .continuous)
        Group {
            if let image {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFill()
            } else {
                ZStack {
                    Color.white.opacity(0.1)
                    Image(systemName: "music.note")
                        .adaFont(size: size * 0.44, weight: .medium)
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(shape.strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
        .accessibilityHidden(true)
    }
}

struct IslandPlayerView: View {
    @ObservedObject var store: NowPlayingStore
    let accent: Color
    let onFiles: () -> Void
    @Binding var showCalendarEvents: Bool

    var body: some View {
        HStack(spacing: 17) {
            Group {
                if let track = store.track {
                    activePlayer(track)
                } else {
                    idlePlayer
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            weekCard
                .frame(width: 142)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.white)
    }

    private func activePlayer(_ track: NowPlayingTrack) -> some View {
        HStack(spacing: 9) {
            MediaArtworkView(image: track.artwork, size: 96, cornerRadius: 10)
                .overlay(alignment: .bottomTrailing) {
                    sourceBadge(for: track.source)
                        .offset(x: 5, y: 5)
                }
            VStack(alignment: .leading, spacing: 5) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title).adaFont(size: 14, weight: .semibold).lineLimit(1)
                    Text(track.artist.isEmpty ? track.source.title : track.artist)
                        .adaFont(size: 11).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let timing = track.timing {
                    PlayerTimeline(track: track, timing: timing, isControlling: store.isControlling) {
                        store.seek(to: $0, in: track)
                    }
                    .id(track.id)
                } else {
                    Text(L10n.string("Süre bilgisi yok"))
                        .adaFont(size: 9).foregroundStyle(Palette.tertiaryText)
                }
                HStack(spacing: 4) {
                    transport("backward.fill", label: L10n.string("Önceki parça")) { store.previous(source: track.source) }
                    transport(track.isPlaying ? "pause.fill" : "play.fill",
                              label: track.isPlaying ? L10n.string("Duraklat") : L10n.string("Oynat")) {
                        store.playPause(source: track.source)
                    }
                    transport("forward.fill", label: L10n.string("Sonraki parça")) { store.next(source: track.source) }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func sourceBadge(for source: MediaSource) -> some View {
        Button { store.openSource(source) } label: {
            if source == .spotify {
                SpotifyBrandIcon(size: 24, circularMark: true)
            } else {
                Image(systemName: source.symbol)
                    .adaFont(size: 10, weight: .semibold)
                    .frame(width: 24, height: 24)
                    .background(.white.opacity(0.09), in: Circle())
            }
        }
        .buttonStyle(IslandButtonStyle(cornerRadius: 100))
        .accessibilityLabel(L10n.string("\(source.title) uygulamasını aç"))
        .help(L10n.string("\(source.title) uygulamasını aç"))
    }

    private var idlePlayer: some View {
        HStack(spacing: 14) {
            MediaArtworkView(image: nil, size: 72)
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.string("Şu an çalan yok")).adaFont(size: 15, weight: .semibold)
                Text(idleMessage).adaFont(size: 10).foregroundStyle(.white.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    ForEach(MediaSource.allCases) { source in
                        if store.permissionDenied(for: source) {
                            action(L10n.string("İzinler"), symbol: "lock", perform: store.openAutomationSettings)
                                .accessibilityLabel(L10n.string("\(source.title) izinleri"))
                        } else {
                            action(source.title, symbol: source.symbol, isSpotify: source == .spotify) {
                                store.openSource(source)
                            }
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var idleMessage: String {
        if let status = store.status { return status }
        return store.isEnabled
            ? L10n.string("Spotify veya Apple Müzik’te bir parça başlat.")
            : L10n.string("Ayarlar’dan müzik göstergesini aç.")
    }

    private var weekCard: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.string("Bu hafta"))
                    .adaFont(size: 10, weight: .semibold)
                    .foregroundStyle(.white.opacity(0.7))
                HStack(spacing: 0) {
                    ForEach(week(containing: context.date), id: \.self) { day in
                        dayCell(day, today: context.date)
                    }
                }
                if showCalendarEvents {
                    UpcomingEventsView(enabled: $showCalendarEvents, showControls: false)
                }
                HStack(spacing: 5) {
                    action(L10n.string("Takvim"), symbol: "calendar", minimumHeight: 30) {
                        if let calendar = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
                            NSWorkspace.shared.openApplication(at: calendar, configuration: .init())
                        }
                    }
                    action(L10n.string("Dosyalar"), symbol: "tray", minimumHeight: 30, perform: onFiles)
                }
            }
        }
    }

    private func week(containing date: Date) -> [Date] {
        CalendarPresentation.week(containing: date)
    }

    private func dayCell(_ day: Date, today: Date) -> some View {
        let locale = Locale.autoupdatingCurrent
        let current = Calendar.autoupdatingCurrent.isDate(day, inSameDayAs: today)
        return VStack(spacing: 4) {
            Text(day.formatted(.dateTime.weekday(.abbreviated).locale(locale)))
                .adaFont(size: 8, weight: .medium)
                .foregroundStyle(current ? accent : Palette.tertiaryText)
                .lineLimit(1)

            Text(day.formatted(.dateTime.day().locale(locale)))
                .adaFont(size: 10, weight: current ? .bold : .medium).monospacedDigit()
                .frame(width: 18, height: 18)
                .background(current ? accent.opacity(0.82) : .clear, in: Circle())
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(locale)))
        .accessibilityAddTraits(current ? .isSelected : [])
    }

    private func transport(_ symbol: String, label: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Image(systemName: symbol)
                .adaFont(size: 12, weight: .semibold)
                .contentTransition(.opacity)
                .frame(width: 34, height: 27)
                .foregroundStyle(.white)
                .contentShape(Rectangle())
        }
        .buttonStyle(IslandButtonStyle(cornerRadius: 100))
        .disabled(store.isControlling)
        .accessibilityLabel(label)
        .help(label)
    }

    private func action(_ title: String, symbol: String, isSpotify: Bool = false, minimumHeight: CGFloat = 24,
                        perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            HStack(spacing: 3) {
                if isSpotify {
                    SpotifyBrandIcon(size: 22, circularMark: true)
                } else {
                    Image(systemName: symbol)
                }
                Text(title)
            }
            .adaFont(size: 10, weight: .medium).lineLimit(1)
            .padding(.horizontal, 5)
            .frame(minHeight: minimumHeight)
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(IslandButtonStyle(cornerRadius: 7))
    }
}

private struct PlayerTimeline: View {
    let track: NowPlayingTrack
    let timing: NowPlayingTiming
    let isControlling: Bool
    let onSeek: (TimeInterval) -> Void
    @State private var scrubPosition: TimeInterval?
    @State private var isScrubbing = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.5, paused: !track.isPlaying)) { context in
            let position = min(timing.duration, scrubPosition ?? timing.elapsed(at: context.date, isPlaying: track.isPlaying))
            VStack(spacing: 1) {
                Slider(value: Binding(get: { position }, set: { updated in
                    if isScrubbing { scrubPosition = updated }
                    else { onSeek(updated) }
                }), in: 0...timing.duration, onEditingChanged: scrub)
                .controlSize(.mini)
                .tint(.white.opacity(0.86))
                .disabled(isControlling)
                .accessibilityLabel(L10n.string("Parça konumu"))
                .accessibilityValue(L10n.string("\(timestamp(position)) / \(timestamp(timing.duration))"))
                HStack {
                    Text(timestamp(position))
                    Spacer()
                    Text(timestamp(timing.duration))
                }
                .adaFont(size: 9).monospacedDigit()
                .foregroundStyle(Palette.tertiaryText)
                .accessibilityHidden(true)
            }
        }
    }

    private func scrub(_ editing: Bool) {
        isScrubbing = editing
        if !editing, let position = scrubPosition {
            scrubPosition = nil
            onSeek(position)
        }
    }

    private func timestamp(_ duration: TimeInterval) -> String {
        let seconds = Int(max(0, duration))
        if seconds >= 3_600 {
            return String(format: "%d:%02d:%02d", seconds / 3_600, seconds / 60 % 60, seconds % 60)
        }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

struct CompactNowPlayingView: View {
    let track: NowPlayingTrack
    let notchWidth: CGFloat
    let totalWidth: CGFloat
    let attached: Bool
    let accent: Color

    var body: some View {
        Group {
            if attached {
                HStack(spacing: 0) {
                    MediaArtworkView(image: track.artwork, size: 26)
                        .frame(width: wingWidth)
                    Color.clear.frame(width: notchWidth)
                    NowPlayingEqualizer(isPlaying: track.isPlaying, color: waveformColor)
                        .frame(width: wingWidth)
                }
            } else {
                HStack(spacing: 8) {
                    MediaArtworkView(image: track.artwork, size: 24)
                    Text(track.title)
                        .adaFont(size: 10, weight: .semibold)
                        .foregroundStyle(.white).lineLimit(1)
                    Spacer(minLength: 0)
                    NowPlayingEqualizer(isPlaying: track.isPlaying, color: waveformColor)
                }
                .padding(.horizontal, 11)
            }
        }
        .frame(width: totalWidth, height: 38)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.string("\(track.title)\(track.artist.isEmpty ? "" : L10n.string(", \(track.artist)")) · \(track.isPlaying ? L10n.string("Çalıyor") : L10n.string("Duraklatıldı"))"))
    }

    private var wingWidth: CGFloat { max(0, (totalWidth - notchWidth) / 2) }
    private var waveformColor: Color { track.source == .spotify ? Color(red: 0.12, green: 0.84, blue: 0.38) : accent }
}

private struct NowPlayingEqualizer: View {
    let isPlaying: Bool
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.125, paused: !isPlaying || reduceMotion)) { context in
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<5) { index in
                    Capsule()
                        .fill(color)
                        .frame(width: 2.5, height: height(for: index, at: context.date))
                }
            }
            .frame(width: 24, height: 20)
        }
        .accessibilityHidden(true)
    }

    private func height(for index: Int, at date: Date) -> CGFloat {
        guard isPlaying, !reduceMotion else { return [7, 12, 17, 10, 6][index] }
        let phase = date.timeIntervalSinceReferenceDate * 5.2 + Double(index) * 1.7
        return 5 + CGFloat((sin(phase) + 1) / 2) * 13
    }
}
