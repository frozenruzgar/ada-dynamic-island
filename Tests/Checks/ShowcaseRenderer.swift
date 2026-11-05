@testable import Ada
import AdaCore
import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

extension AdaCheckSuite {
    /// Offscreen renders of the real views using only isolated fixture data.
    public static func renderShowcase(to output: URL) async throws {
        _ = NSApplication.shared
        let suite = "Ada.Showcase.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: temporary)
        }
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        let model = IslandModel(defaults: defaults, startServices: false)
        model.notchWidth = 190
        model.menuBarHeight = 34
        model.batteryPercent = 86
        model.preferences.contentHeight = 226
        let workspace = WorkspaceStore(defaults: defaults, noteURL: temporary.appendingPathComponent("Note.md"))
        workspace.note = "Örnek proje · Taslağı gözden geçir"
        workspace.addTask("Tasarımı gözden geçir")
        workspace.addTask("Yayın notlarını yaz")
        let dashboard = DashboardLayoutStore(defaults: defaults, initialTiles: [
            DashboardTile(kind: .quickActions), DashboardTile(kind: .battery), DashboardTile(kind: .focus),
            DashboardTile(kind: .chatGPT), DashboardTile(kind: .notes), DashboardTile(kind: .tasks),
        ])

        let shelf = ShelfStore(storageURL: temporary.appendingPathComponent("Shelf"), retentionDays: 0, defaults: defaults)
        let urls = ["Proje notları.txt", "Sunum taslağı.txt", "Kontrol listesi.txt"].map {
            temporary.appendingPathComponent($0)
        }
        for url in urls { try Data("Ada demo fixture".utf8).write(to: url) }
        shelf.addFiles(urls)
        for _ in 0..<300 where shelf.isImporting { try await Task.sleep(nanoseconds: 10_000_000) }
        guard shelf.items.count == 3 else { throw CocoaError(.fileReadUnknown) }

        let artwork = ImageRenderer(content: ZStack {
            LinearGradient(colors: [.purple, .pink], startPoint: .bottomLeading, endPoint: .topTrailing)
            Image(systemName: "waveform").font(.system(size: 48, weight: .light)).foregroundStyle(.white)
        }.frame(width: 160, height: 160)).nsImage

        let track = NowPlayingTrack(id: "demo", source: .appleMusic, title: "Gece Yürüyüşü",
                                    artist: "Örnek Sanatçı", album: "Ada Demo", isPlaying: false,
                                    artwork: artwork, timing: NowPlayingTiming(source: .appleMusic, rawDuration: 208,
                                        position: 72, sampledAt: .now))
        let media = NowPlayingStore(previewTrack: track)
        let actions = QuickActionStore()
        let assistant = AssistantStore(defaults: defaults)
        let prompter = PrompterStore(defaults: defaults)
        let monitor = SystemMonitor(startImmediately: false)
        let cloud = CloudWorkspaceStore(defaults: defaults, homeDirectory: temporary)
        let awake = AwakeStore()

        var frames: [CGImage] = []
        for (name, page) in [("dashboard", IslandPage.home), ("player", .player), ("shelf", .files)] {
            model.expanded = true
            model.page = page
            let root = IslandView(model: model, workspace: workspace, actions: actions, shelf: shelf,
                prompter: prompter, assistant: assistant, monitor: monitor, cloud: cloud, awake: awake,
                dashboard: dashboard, media: media, onExpand: { _ in }, onOpenCompact: {},
                onSettings: {}, onAddTile: {}, onChangeTile: { _ in })
                .frame(width: model.width, height: model.height)
            let size = NSSize(width: model.width, height: model.height)
            let rect = NSRect(origin: .zero, size: size)
            let window = NSWindow(contentRect: rect, styleMask: .borderless, backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: .darkAqua)
            window.backgroundColor = .clear
            let host = NSHostingView(rootView: root.environment(\.colorScheme, .dark))
            window.contentView = host
            host.frame = rect
            host.layoutSubtreeIfNeeded()
            await Task.yield()
            host.layoutSubtreeIfNeeded()
            let panel: CGImage? = withExtendedLifetime(window) {
                guard let bitmap = host.bitmapImageRepForCachingDisplay(in: rect) else { return nil }
                host.cacheDisplay(in: rect, to: bitmap)
                return bitmap.cgImage
            }
            guard let panel else { throw CocoaError(.fileWriteUnknown) }
            try write([panel], to: output.appendingPathComponent(name + ".png"), type: .png)

            let frame = ImageRenderer(content: ZStack(alignment: .top) {
                Color(red: 0.055, green: 0.05, blue: 0.09)
                Image(decorative: panel, scale: CGFloat(panel.width) / size.width)
                    .padding(.top, 14)
            }.frame(width: 704, height: 320))
            frame.scale = 1
            guard let image = frame.cgImage else { throw CocoaError(.fileWriteUnknown) }
            frames.append(image)
        }
        try write(frames, to: output.appendingPathComponent("demo.gif"), type: .gif)
        _ = await workspace.flushNote()
        model.shutdown()
        print("Rendered 3 fixture screenshots and demo GIF at \(output.path)")
    }

    private static func write(_ frames: [CGImage], to url: URL, type: UTType) throws {
        guard let writer = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, frames.count, nil)
        else { throw CocoaError(.fileWriteUnknown) }
        if type == .gif {
            CGImageDestinationSetProperties(writer, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        }
        for frame in frames {
            let properties: CFDictionary? = type == .gif
                ? [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.8]] as CFDictionary : nil
            CGImageDestinationAddImage(writer, frame, properties)
        }
        guard CGImageDestinationFinalize(writer) else { throw CocoaError(.fileWriteUnknown) }
    }
}
