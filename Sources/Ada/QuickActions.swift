import AdaCore
import AppKit
import AVFoundation
import Combine
import SwiftUI

/// User-initiated system actions. Creating this store never requests camera access or starts audio.
@MainActor
final class QuickActionStore: NSObject, ObservableObject, NSWindowDelegate {
    @Published var errorMessage: String?
    @Published private(set) var audioTitle = L10n.string("Yerel müzik seç")
    @Published private(set) var hasAudio = false
    @Published private(set) var audioPlaying = false
    @Published private(set) var cameraOpening = false

    private var player: AVPlayer?
    private var playerObservation: NSKeyValueObservation?
    private var audioEndObserver: NSObjectProtocol?
    private var audioFailureObserver: NSObjectProtocol?
    private var audioURL: URL?
    private var audioScopeHeld = false
    private var mirrorWindow: NSWindow?
    private var cameraDriver: CameraSessionDriver?
    private var cameraErrorObserver: NSObjectProtocol?
    private var airDropService: NSSharingService?
    private var audioPanel: NSOpenPanel?
    private var sharePanel: NSOpenPanel?

    func clearError() { errorMessage = nil }

    func performAirDrop() {
        errorMessage = nil
        if let sharePanel { sharePanel.makeKeyAndOrderFront(nil); return }
        let picker = NSOpenPanel()
        picker.title = L10n.string("AirDrop ile gönderilecek dosyaları seç")
        picker.message = L10n.string("Alıcıyı macOS AirDrop penceresinde seçeceksin.")
        picker.prompt = L10n.string("AirDrop ile paylaş")
        picker.canChooseFiles = true
        picker.canChooseDirectories = false
        picker.allowsMultipleSelection = true
        sharePanel = picker
        NSApp.activate()
        picker.begin { [weak self] response in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.sharePanel = nil
                guard response == .OK, !picker.urls.isEmpty else { return }
                guard let service = NSSharingService(named: .sendViaAirDrop),
                      service.canPerform(withItems: picker.urls) else {
                    self.errorMessage = L10n.string("AirDrop bu dosyalar için kullanılamıyor. Finder’dan AirDrop’u kontrol et.")
                    return
                }
                self.airDropService = service
                service.perform(withItems: picker.urls)
            }
        }
    }

    func chooseAudio() {
        errorMessage = nil
        if let audioPanel { audioPanel.makeKeyAndOrderFront(nil); return }
        let picker = NSOpenPanel()
        picker.title = L10n.string("Müzik veya ses dosyası seç")
        picker.message = L10n.string("Dosya seçildikten sonra oynatmak için Başlat’a bas.")
        picker.prompt = L10n.string("Seç")
        picker.canChooseFiles = true
        picker.canChooseDirectories = false
        picker.allowsMultipleSelection = false
        picker.allowedContentTypes = [.mp3, .mpeg4Audio, .wav, .aiff]
        audioPanel = picker
        NSApp.activate()
        picker.begin { [weak self] response in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.audioPanel = nil
                guard response == .OK, let url = picker.url else { return }
                self.loadAudio(url)
            }
        }
    }

    private func loadAudio(_ url: URL) {
        stopAudio()
        releaseAudioScope()
        audioURL = url
        audioScopeHeld = url.startAccessingSecurityScopedResource()
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            errorMessage = L10n.string("Bu ses dosyası okunamıyor. Başka bir dosya seç.")
            releaseAudioScope()
            return
        }
        if let audioEndObserver { NotificationCenter.default.removeObserver(audioEndObserver) }
        if let audioFailureObserver { NotificationCenter.default.removeObserver(audioFailureObserver) }
        let item = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: item)
        player = newPlayer
        audioTitle = url.deletingPathExtension().lastPathComponent
        hasAudio = true
        audioPlaying = false
        playerObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            let description = item.error?.localizedDescription
            Task { @MainActor [weak self] in
                self?.audioPlaying = false
                self?.errorMessage = L10n.string("Ses dosyası açılamadı. \(description ?? L10n.string("Desteklenen başka bir dosya seç."))")
            }
        }
        audioEndObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
            object: item, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.audioPlaying = false; self?.player?.seek(to: .zero) }
            }
        audioFailureObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.audioPlaying = false
                    self?.errorMessage = L10n.string("Ses dosyası oynatılırken bir sorun oluştu. Başka bir dosya seç.")
                }
            }
    }

    func toggleAudio() {
        guard let player else { chooseAudio(); return }
        errorMessage = nil
        if audioPlaying { player.pause(); audioPlaying = false }
        else { player.play(); audioPlaying = true }
    }

    /// Pauses and rewinds the selected track. It does not clear the selection.
    func stopAudio() {
        player?.pause()
        player?.seek(to: .zero)
        audioPlaying = false
    }

    func showMirror() {
        errorMessage = nil
        if let mirrorWindow { mirrorWindow.makeKeyAndOrderFront(nil); NSApp.activate(); return }
        guard !cameraOpening else { return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: openMirror()
        case .notDetermined:
            cameraOpening = true
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.cameraOpening = false
                    if granted { self.openMirror() }
                    else { self.errorMessage = L10n.string("Kamera izni verilmedi. Sistem Ayarları → Gizlilik ve Güvenlik → Kamera bölümünden Ada’ya izin verebilirsin.") }
                }
            }
        case .denied, .restricted:
            errorMessage = L10n.string("Kamera erişimi kapalı. Sistem Ayarları → Gizlilik ve Güvenlik → Kamera bölümünü kontrol et.")
        @unknown default: errorMessage = L10n.string("Kamera erişim durumu okunamadı.")
        }
    }

    private func openMirror() {
        guard let device = AVCaptureDevice.default(for: .video) else {
            errorMessage = L10n.string("Kullanılabilir kamera bulunamadı.")
            return
        }
        do {
            let session = AVCaptureSession()
            session.beginConfiguration()
            session.sessionPreset = .high
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else {
                session.commitConfiguration()
                errorMessage = L10n.string("Kamera başlatılamadı. Başka bir uygulamanın kamerayı kullanıp kullanmadığını kontrol et.")
                return
            }
            session.addInput(input)
            session.commitConfiguration()
            let driver = CameraSessionDriver(session: session)
            cameraDriver = driver
            cameraErrorObserver = NotificationCenter.default.addObserver(forName: .AVCaptureSessionRuntimeError,
                object: session, queue: .main) { [weak self] notification in
                    let failure = (notification.userInfo?[AVCaptureSessionErrorKey] as? Error)?.localizedDescription
                    MainActor.assumeIsolated {
                        self?.errorMessage = L10n.string("Kamera önizlemesi başlatılamadı. \(failure ?? L10n.string("Kamerayı kullanan diğer uygulamaları kontrol et."))")
                        self?.mirrorWindow?.close()
                    }
                }
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 370),
                styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = L10n.string("Ada · Kamera aynası")
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 360, height: 270)
            window.delegate = self
            window.contentView = NSHostingView(rootView: MirrorContentView(session: session))
            window.center()
            mirrorWindow = window
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            driver.start()
        } catch {
            errorMessage = L10n.string("Kamera açılamadı: \(error.localizedDescription)")
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === mirrorWindow else { return }
        cameraDriver?.stop()
        cameraDriver = nil
        if let cameraErrorObserver { NotificationCenter.default.removeObserver(cameraErrorObserver) }
        cameraErrorObserver = nil
        mirrorWindow = nil
    }

    /// Call from applicationWillTerminate to release camera/audio resources.
    func shutdown() {
        stopAudio()
        cameraDriver?.stop()
        mirrorWindow?.close()
        mirrorWindow = nil
        releaseAudioScope()
        playerObservation = nil
        if let audioEndObserver { NotificationCenter.default.removeObserver(audioEndObserver) }
        if let audioFailureObserver { NotificationCenter.default.removeObserver(audioFailureObserver) }
    }

    private func releaseAudioScope() {
        if audioScopeHeld { audioURL?.stopAccessingSecurityScopedResource() }
        audioScopeHeld = false
        audioURL = nil
    }
}

/// Safety: capture configuration is complete before start. All lifecycle and
/// isRunning operations are serialized on queue; the main-actor preview only
/// displays the session, without changing capture configuration while running.
private final class CameraSessionDriver: @unchecked Sendable {
    let session: AVCaptureSession
    private let queue = DispatchQueue(label: "dev.ada.island.camera")
    init(session: AVCaptureSession) { self.session = session }
    func start() { queue.async { [self] in if !session.isRunning { session.startRunning() } } }
    func stop() { queue.async { [self] in if session.isRunning { session.stopRunning() } } }
}

private struct MirrorContentView: View {
    let session: AVCaptureSession
    var body: some View {
        VStack(spacing: 0) {
            MirrorPreview(session: session).background(.black)
            HStack(spacing: 7) {
                Image(systemName: "camera.fill")
                Text(L10n.string("Canlı ayna · Bu pencereyi kapatınca kamera durur."))
                    .adaFont(size: 11)
            }.foregroundStyle(.secondary).padding(12)
        }.frame(minWidth: 360, minHeight: 240)
    }
}

private struct MirrorPreview: NSViewRepresentable {
    let session: AVCaptureSession
    func makeNSView(context: Context) -> PreviewSurface {
        let view = PreviewSurface()
        view.preview.session = session
        view.preview.videoGravity = .resizeAspectFill
        if let connection = view.preview.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
        return view
    }
    func updateNSView(_ nsView: PreviewSurface, context: Context) {}
}

private final class PreviewSurface: NSView {
    let preview = AVCaptureVideoPreviewLayer()
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(preview)
    }
    required init?(coder: NSCoder) { nil }
    override func layout() { super.layout(); preview.frame = bounds }
}
