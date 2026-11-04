import AppKit
import SwiftUI

/// Local teleprompter state. No camera, microphone or network access is required.
@MainActor
final class PrompterStore: NSObject, ObservableObject, NSWindowDelegate {
    private struct SavedState: Codable {
        var script: String
        var speed: Double
        var fontSize: Double
        var mirrored: Bool
        var centered: Bool
    }

    @Published private(set) var script = ""
    @Published var speed: Double = 35 { didSet { savePreferences() } }
    @Published var fontSize: Double = 20 { didSet { savePreferences() } }
    @Published var mirrored = false { didSet { savePreferences() } }
    @Published var centered = true { didSet { savePreferences() } }
    @Published private(set) var isPlaying = false
    @Published private(set) var offset: CGFloat = 0
    @Published private(set) var travel: CGFloat = 0
    @Published private(set) var editorVisible = false
    var onEditorVisibility: ((Bool) -> Void)?

    private var ticker: Timer?
    private var lastUptime: TimeInterval = 0
    private var editorWindow: NSWindow?
    private var scrubStart: CGFloat?
    private let defaultsKey = "ada.prompter.v1"

    override init() {
        super.init()
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let saved = try? JSONDecoder().decode(SavedState.self, from: data) {
            script = saved.script
            speed = min(100, max(10, saved.speed))
            fontSize = min(32, max(14, saved.fontSize))
            mirrored = saved.mirrored
            centered = saved.centered
        }
    }

    var hasScript: Bool { !script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var progress: Double { travel > 0 ? min(1, max(0, Double(offset / travel))) : 0 }
    var finished: Bool { hasScript && travel > 0 && offset >= travel }
    var playbackTitle: String { isPlaying ? "Duraklat" : finished ? "Yeniden başlat" : "Başlat" }

    func togglePlayback() {
        guard hasScript else { showEditor(); return }
        if isPlaying { pause() } else { play() }
    }

    func play() {
        guard hasScript, !isPlaying else { return }
        if finished { offset = 0 }
        isPlaying = true
        lastUptime = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.advance() }
        }
        ticker = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func pause() {
        if isPlaying { advance() }
        isPlaying = false
        ticker?.invalidate()
        ticker = nil
    }

    func reset() {
        pause()
        offset = 0
    }

    func replaceScript(_ text: String) {
        reset()
        script = text
        savePreferences()
    }

    func setTravel(_ measured: CGFloat) {
        let value = max(0, measured)
        guard abs(value - travel) > 0.5 else { return }
        let fraction = travel > 0 ? offset / travel : 0
        travel = value
        offset = min(value, max(0, fraction * value))
    }

    func scrub(translation: CGFloat) {
        if scrubStart == nil {
            pause()
            scrubStart = offset
        }
        offset = min(travel, max(0, (scrubStart ?? 0) - translation))
    }

    func endScrub() { scrubStart = nil }

    private func advance() {
        guard isPlaying else { return }
        let uptime = ProcessInfo.processInfo.systemUptime
        // Ignore a long suspension; waking the Mac must not silently skip a speech.
        let elapsed = min(0.25, max(0, uptime - lastUptime))
        lastUptime = uptime
        guard travel > 0 else { return }
        offset = min(travel, offset + CGFloat(elapsed * speed))
        if offset >= travel {
            isPlaying = false
            ticker?.invalidate()
            ticker = nil
        }
    }

    private func savePreferences() {
        let state = SavedState(script: script, speed: speed, fontSize: fontSize,
                               mirrored: mirrored, centered: centered)
        if let data = try? JSONEncoder().encode(state) { UserDefaults.standard.set(data, forKey: defaultsKey) }
    }

    func showEditor() {
        pause()
        if editorWindow?.isVisible == true {
            NSApp.activate(ignoringOtherApps: true)
            editorWindow?.makeKeyAndOrderFront(nil)
            return
        }
        let window: NSWindow
        if let existing = editorWindow { window = existing }
        else {
            window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 480),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable],
                              backing: .buffered, defer: false)
            window.title = "Teleprompter metni"
            window.minSize = NSSize(width: 500, height: 360)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.appearance = NSAppearance(named: .darkAqua)
            window.center()
            editorWindow = window
        }
        window.contentView = NSHostingView(rootView: PrompterEditor(
            initialText: script,
            onCancel: { [weak window] in window?.close() },
            onSave: { [weak self, weak window] text in
                self?.replaceScript(text)
                window?.close()
            }))
        editorVisible = true
        onEditorVisibility?(true)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        editorVisible = false
        onEditorVisibility?(false)
    }
}

private struct PrompterEditor: View {
    @State private var draft: String
    @FocusState private var focused: Bool
    let onCancel: () -> Void
    let onSave: (String) -> Void

    init(initialText: String, onCancel: @escaping () -> Void, onSave: @escaping (String) -> Void) {
        _draft = State(initialValue: initialText)
        self.onCancel = onCancel
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Konuşma metnini ekle").font(.system(size: 20, weight: .semibold))
            Text("Metin bu Mac’te saklanır. Kaydettiğinde prompter başa döner.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            TextEditor(text: $draft)
                .font(.system(size: 17))
                .scrollContentBackground(.hidden)
                .padding(12)
                .background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.10)))
                .focused($focused)
                .accessibilityLabel("Konuşma metni")
            HStack {
                Text("\(draft.count) karakter").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Vazgeç", action: onCancel).keyboardShortcut(.cancelAction)
                Button("Metni kaydet") { onSave(draft) }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(IslandButtonStyle(emphasis: true, bordered: true))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(24)
        .frame(minWidth: 450, minHeight: 300)
        .buttonStyle(IslandButtonStyle(bordered: true))
        .onAppear { focused = true }
    }
}

private struct PrompterTextHeight: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// Embed as a tab. Keep the store above the tab so its position survives navigation.
struct TeleprompterView: View {
    @ObservedObject var store: PrompterStore
    var accent: Color = Color(red: 0.70, green: 0.61, blue: 1)
    var onEditorVisibility: (Bool) -> Void = { _ in }
    @State private var textHeight: CGFloat = 0
    @State private var keyMonitor: Any?

    var body: some View {
        HStack(spacing: 16) {
            playbackControls.frame(width: 158)
            viewport.frame(maxWidth: .infinity, maxHeight: .infinity)
            readingControls.frame(width: 158)
        }
        .padding(16)
        .background(
            LinearGradient(colors: [.white.opacity(0.065), Color(red: 0.28, green: 0.26, blue: 0.50).opacity(0.30)],
                           startPoint: .top, endPoint: .bottom),
            in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.14), lineWidth: 1))
        .onAppear {
            store.onEditorVisibility = onEditorVisibility
            installKeyMonitor()
        }
        .onDisappear {
            store.pause()
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
            keyMonitor = nil
        }
        .onChange(of: store.editorVisible) { _, value in onEditorVisibility(value) }
    }

    private var playbackControls: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("Teleprompter", systemImage: "text.viewfinder")
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.62))
            Spacer(minLength: 2)
            Button(action: store.togglePlayback) {
                Label(store.hasScript ? store.playbackTitle : "Metin ekle",
                      systemImage: store.isPlaying ? "pause.fill" : store.hasScript ? "play.fill" : "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity).frame(height: 34)
                    .background(accent.opacity(0.85), in: Capsule())
                    .foregroundStyle(.black)
            }.buttonStyle(IslandButtonStyle(cornerRadius: 100))
            Button(action: store.showEditor) {
                Label("Metni düzenle", systemImage: "square.and.pencil")
                    .font(.system(size: 11, weight: .medium))
                    .frame(maxWidth: .infinity).frame(height: 27)
                    .background(.white.opacity(0.075), in: Capsule())
            }.buttonStyle(IslandButtonStyle(cornerRadius: 100))
            Button("Başa dön", action: store.reset)
                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.55))
                .buttonStyle(IslandButtonStyle()).frame(maxWidth: .infinity)
                .disabled(!store.hasScript)
            Spacer(minLength: 2)
            Text(store.isPlaying ? "Boşluk: duraklat" : "Boşluk: devam et")
                .font(.system(size: 9)).foregroundStyle(.white.opacity(0.35))
                .frame(maxWidth: .infinity)
        }
    }

    private var viewport: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                if store.hasScript {
                    Text(store.script)
                        .font(.system(size: store.fontSize, weight: .medium))
                        .lineSpacing(8)
                        .multilineTextAlignment(store.centered ? .center : .leading)
                        .frame(width: max(40, proxy.size.width - 20), alignment: store.centered ? .center : .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .background(GeometryReader { textGeometry in
                            Color.clear.preference(key: PrompterTextHeight.self, value: textGeometry.size.height)
                        })
                        .offset(y: proxy.size.height * 0.32 - store.offset)
                        .scaleEffect(x: store.mirrored ? -1 : 1, y: 1)
                        .frame(maxWidth: .infinity)
                        .onPreferenceChange(PrompterTextHeight.self) { value in
                            textHeight = value
                            store.setTravel(max(0, value - CGFloat(store.fontSize) * 1.3))
                        }
                        .gesture(DragGesture(minimumDistance: 3)
                            .onChanged { value in store.scrub(translation: value.translation.height) }
                            .onEnded { _ in store.endScrub() })
                    Rectangle().fill(accent.opacity(0.45)).frame(height: 1)
                        .offset(y: proxy.size.height * 0.32 + CGFloat(store.fontSize) * 1.4)
                        .allowsHitTesting(false)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "text.aligncenter").font(.system(size: 25, weight: .light)).foregroundStyle(accent)
                        Text("Metnini kameranın altından oku")
                            .font(.system(size: 14, weight: .medium))
                        Text("Metin ekle ile başla; hızını ve yazı boyutunu sağdan ayarla.")
                            .font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
                            .multilineTextAlignment(.center)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.12),
                                         .init(color: .black, location: 0.84), .init(color: .clear, location: 1)],
                                 startPoint: .top, endPoint: .bottom))
            .clipped()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(store.hasScript ? "Konuşma metni. \(store.isPlaying ? "Okunuyor" : "Duraklatıldı"). Yüzde \(Int(store.progress * 100)) tamamlandı." : "Henüz konuşma metni eklenmedi")
    }

    private var readingControls: some View {
        VStack(spacing: 8) {
            controlRow("Hız", value: "\(Int(store.speed))", minusLabel: "Okuma hızını azalt", plusLabel: "Okuma hızını artır",
                       minus: { store.speed = max(10, store.speed - 5) },
                       plus: { store.speed = min(100, store.speed + 5) })
            controlRow("Yazı", value: "\(Int(store.fontSize))", minusLabel: "Yazıyı küçült", plusLabel: "Yazıyı büyüt",
                       minus: { store.fontSize = max(14, store.fontSize - 1) },
                       plus: { store.fontSize = min(32, store.fontSize + 1) })
            HStack(spacing: 5) {
                optionButton(store.centered ? "Ortala" : "Sola", selected: store.centered) { store.centered.toggle() }
                optionButton("Ayna", selected: store.mirrored) { store.mirrored.toggle() }
            }
            Text(store.finished ? "Metin tamamlandı" : "Sürükleyerek konumu değiştir")
                .font(.system(size: 9)).foregroundStyle(.white.opacity(0.35))
                .lineLimit(1).minimumScaleFactor(0.8)
        }
    }

    private func controlRow(_ title: String, value: String, minusLabel: String, plusLabel: String,
                            minus: @escaping () -> Void, plus: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Text(title).font(.system(size: 10)).foregroundStyle(.white.opacity(0.5)).frame(width: 29, alignment: .leading)
            Button(action: minus) { Image(systemName: "minus").frame(width: 21, height: 27) }
                .buttonStyle(IslandButtonStyle()).accessibilityLabel(minusLabel)
            Text(value).font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit()
                .foregroundStyle(accent).frame(minWidth: 20)
            Button(action: plus) { Image(systemName: "plus").frame(width: 21, height: 27) }
                .buttonStyle(IslandButtonStyle()).accessibilityLabel(plusLabel)
        }
        .frame(maxWidth: .infinity)
        .background(.white.opacity(0.065), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.09)))
    }

    private func optionButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 10, weight: .medium))
                .frame(maxWidth: .infinity).frame(height: 26)
                .foregroundStyle(selected ? accent : .white.opacity(0.55))
                .background(selected ? accent.opacity(0.19) : .white.opacity(0.06), in: Capsule())
                .overlay(Capsule().stroke(selected ? accent.opacity(0.25) : .white.opacity(0.08)))
        }.buttonStyle(IslandButtonStyle(cornerRadius: 100))
        .animation(.easeInOut(duration: 0.18), value: selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak store] event in
            guard event.keyCode == 49,
                  event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
                  let window = event.window, window.isKeyWindow,
                  window.styleMask.contains(.nonactivatingPanel),
                  !(window.firstResponder is NSTextView) else { return event }
            MainActor.assumeIsolated {
                guard let store, !store.editorVisible else { return }
                store.togglePlayback()
            }
            return nil
        }
    }
}
