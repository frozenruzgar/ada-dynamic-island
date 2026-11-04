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
                            Text(track.title).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                            Text(track.artist.isEmpty ? source.title : track.artist)
                                .font(.system(size: 9)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.right").font(.system(size: 8))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(IslandButtonStyle(cornerRadius: 8))
                .help("\(source.title) uygulamasını aç")

                HStack(spacing: 5) {
                    Text(source.title).font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                    Spacer(minLength: 0)
                    transportButton("backward.end.fill", label: "Önceki parça") { store.previous(source: source) }
                    transportButton(track.isPlaying ? "pause.fill" : "play.fill",
                                    label: track.isPlaying ? "Duraklat" : "Oynat") { store.playPause(source: source) }
                    transportButton("forward.end.fill", label: "Sonraki parça") { store.next(source: source) }
                }
                .animation(.easeInOut(duration: 0.18), value: track.isPlaying)
            } else {
                HStack(spacing: 8) {
                    playerIcon
                    Text(source.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    Spacer(minLength: 0)
                }
                HStack(spacing: 6) {
                    Text(source.isInstalled ? (store.permissionDenied(for: source) ? "İzin gerekli" : "Bir parça seç") : "Mac uygulaması gerekli")
                        .font(.system(size: 9)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    if source.isInstalled, store.permissionDenied(for: source) {
                        Button("İzinler", action: store.openAutomationSettings)
                            .font(.system(size: 9, weight: .semibold))
                            .buttonStyle(IslandButtonStyle(cornerRadius: 100))
                            .foregroundStyle(accent)
                            .help(store.status ?? "Müzik erişim izinlerini aç")
                            .contextMenu { Button("Yeniden dene", action: store.retryPermissions) }
                    } else {
                        Button(action: openPlayer) {
                            Text(source.isInstalled ? "Aç" : "Web’de aç")
                                .font(.system(size: 10, weight: .semibold))
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
            if let url = source.applicationURL {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable().interpolation(.high).scaledToFit()
            } else {
                Image(systemName: source.symbol)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(source == .spotify ? Color.green : accent)
                    .frame(width: 30, height: 30)
                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .frame(width: 30, height: 30)
        .accessibilityHidden(true)
    }

    private func transportButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .contentTransition(.opacity)
                .font(.system(size: 9, weight: .semibold))
                .frame(width: 22, height: 20)
                .background(.white.opacity(0.07), in: Capsule())
        }
        .buttonStyle(IslandButtonStyle(cornerRadius: 100))
        .disabled(store.isControlling)
        .accessibilityLabel("\(source.title) · \(label)")
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

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFill()
            } else {
                ZStack {
                    Color.white.opacity(0.1)
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.44, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: max(3, size * 0.2), style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: max(3, size * 0.2), style: .continuous)
            .strokeBorder(.white.opacity(0.15), lineWidth: 0.5))
        .accessibilityHidden(true)
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
                    NowPlayingEqualizer(isPlaying: track.isPlaying, color: accent)
                        .frame(width: wingWidth)
                }
            } else {
                HStack(spacing: 8) {
                    MediaArtworkView(image: track.artwork, size: 24)
                    Text(track.title)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white).lineLimit(1)
                    Spacer(minLength: 0)
                    NowPlayingEqualizer(isPlaying: track.isPlaying, color: accent)
                }
                .padding(.horizontal, 11)
            }
        }
        .frame(width: totalWidth, height: 38)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(track.title)\(track.artist.isEmpty ? "" : ", \(track.artist)") · \(track.isPlaying ? "Çalıyor" : "Duraklatıldı")")
    }

    private var wingWidth: CGFloat { max(0, (totalWidth - notchWidth) / 2) }
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
