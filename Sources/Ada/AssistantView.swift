import AppKit
import SwiftUI
import WebKit

/// The assistant launcher does not use API credentials or submit prompts.
/// Draft text stays in memory until the user explicitly copies it.
enum AssistantProvider: String, CaseIterable, Identifiable {
    case chatGPT, claude
    var id: String { rawValue }
    var title: String { self == .chatGPT ? "ChatGPT" : "Claude" }
    var symbol: String { self == .chatGPT ? "sparkles" : "asterisk" }
    var url: URL {
        URL(string: self == .chatGPT ? "https://chatgpt.com/" : "https://claude.ai/")!
    }
}

enum AssistantTask: String, CaseIterable, Identifiable {
    case ask, summarize, improve, translate, email
    var id: String { rawValue }
    var title: String {
        switch self {
        case .ask: return "Soru sor"
        case .summarize: return "Özetle"
        case .improve: return "Düzelt"
        case .translate: return "İngilizceye çevir"
        case .email: return "E-posta taslağı"
        }
    }
    var instruction: String {
        switch self {
        case .ask: return ""
        case .summarize: return "Aşağıdaki metni Türkçe, kısa ve anlaşılır biçimde özetle. Ana noktaları koru:"
        case .improve: return "Aşağıdaki metnin anlamını koruyarak yazımını ve anlatımını düzelt. Yalnızca düzeltilmiş metni ver:"
        case .translate: return "Aşağıdaki metni doğal ve anlamı koruyan bir İngilizceyle çevir:"
        case .email: return "Aşağıdaki notlardan konu satırı ve gövdesi olan açık, profesyonel bir Türkçe e-posta taslağı hazırla. Eksik bilgileri uydurma:"
        }
    }
}

@MainActor
final class AssistantStore: NSObject, ObservableObject, NSWindowDelegate {
    @Published var provider: AssistantProvider {
        didSet { UserDefaults.standard.set(provider.rawValue, forKey: "assistantProvider") }
    }
    @Published var task: AssistantTask = .ask
    @Published var draft = ""
    @Published private(set) var status = ""

    private var windows: [AssistantProvider: NSWindow] = [:]
    private var sessions: [AssistantProvider: AssistantWebSession] = [:]

    override init() {
        provider = AssistantProvider(rawValue: UserDefaults.standard.string(forKey: "assistantProvider") ?? "") ?? .chatGPT
        super.init()
    }

    var preparedPrompt: String {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }
        return task.instruction.isEmpty ? text : "\(task.instruction)\n\n\(text)"
    }

    func readClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
            status = "Panoda metin yok."
            return
        }
        draft = text
        status = ""
    }

    func clearDraft() {
        draft = ""
        status = ""
    }

    func copyAndOpen() {
        guard !preparedPrompt.isEmpty else {
            status = "Bir soru veya metin yaz."
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(preparedPrompt, forType: .string)
        status = "Kopyalandı. Sohbete yapıştır."
        showChat()
    }

    /// Opening a chat is the first point at which this feature accesses the network.
    func showChat() {
        let target = provider
        if let window = windows[target] {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let session = AssistantWebSession(provider: target)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 740),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Ada · \(target.title)"
        window.minSize = NSSize(width: 900, height: 650)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: AssistantChatWindow(session: session))
        window.center()
        sessions[target] = session
        windows[target] = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        session.loadHome()
    }

    func openInBrowser() {
        // Use only the provider's official landing URL. Drafts and credentials are
        // never encoded into URLs, and no session data is copied to another app.
        status = NSWorkspace.shared.open(provider.url) ? "" : "Tarayıcı açılamadı."
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let provider = windows.first(where: { $0.value === window })?.key else { return }
        sessions[provider]?.stop()
        window.contentView = nil
        windows.removeValue(forKey: provider)
        sessions.removeValue(forKey: provider)
    }

    func shutdown() {
        for session in sessions.values { session.stop() }
        for window in windows.values { window.delegate = nil; window.close() }
        windows.removeAll()
        sessions.removeAll()
        draft = ""
    }
}

struct AssistantView: View {
    @ObservedObject var store: AssistantStore
    var accent: Color = Color(red: 0.54, green: 0.69, blue: 1)
    var onSelectProvider: () -> Void = {}

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Sohbet hizmeti", selection: Binding(get: { store.provider }, set: { provider in
                    store.provider = provider
                    onSelectProvider()
                })) {
                    ForEach(AssistantProvider.allCases) { provider in
                        Text(provider.title).tag(provider)
                    }
                }.labelsHidden().pickerStyle(.segmented)
                Button(action: store.showChat) {
                    Label("Sohbeti aç", systemImage: "bubble.left.and.bubble.right")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 11))
                }.buttonStyle(IslandButtonStyle()).foregroundStyle(accent)
                Button(action: store.openInBrowser) {
                    Label("Tarayıcıda aç", systemImage: "arrow.up.right.square")
                        .font(.system(size: 10, weight: .medium))
                }.buttonStyle(IslandButtonStyle()).foregroundStyle(.white.opacity(0.65))
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(width: 232)
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .assistantSurface()

            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("Taslak").font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Picker("İstek türü", selection: $store.task) {
                        ForEach(AssistantTask.allCases) { task in Text(task.title).tag(task) }
                    }.labelsHidden().frame(maxWidth: 180)
                }
                ZStack(alignment: .topLeading) {
                    if store.draft.isEmpty {
                        Text("Soru veya metin…")
                            .font(.system(size: 12)).foregroundStyle(.white.opacity(0.52))
                            .padding(.top, 6).padding(.leading, 5).allowsHitTesting(false)
                    }
                    TextEditor(text: $store.draft)
                        .font(.system(size: 12))
                        .scrollContentBackground(.hidden)
                        .accessibilityLabel("Taslak metni")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(5)
                .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                HStack(spacing: 12) {
                    Button("Panodan al", action: store.readClipboard)
                    Button("Temizle", action: store.clearDraft).disabled(store.draft.isEmpty)
                    Spacer(minLength: 0)
                    Button(action: store.copyAndOpen) {
                        Label("Kopyala ve aç", systemImage: "arrow.up.right")
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 13).padding(.vertical, 8)
                            .foregroundStyle(accent).background(accent.opacity(0.13), in: Capsule())
                    }.disabled(store.preparedPrompt.isEmpty)
                }.font(.system(size: 10)).buttonStyle(IslandButtonStyle(cornerRadius: 100))
                Text(store.status.isEmpty ? "Kopyaladıktan sonra sohbete yapıştır." : store.status)
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.60)).lineLimit(2)
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .assistantSurface()
        }
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
    }
}

@MainActor
private final class AssistantWebSession: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    let provider: AssistantProvider
    let webView: WKWebView
    @Published private(set) var loading = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var canGoBack = false
    @Published private(set) var hostname: String
    @Published private(set) var errorMessage: String?
    @Published private(set) var notice: String?
    private var progressObservation: NSKeyValueObservation?
    private var backObservation: NSKeyValueObservation?
    private var urlObservation: NSKeyValueObservation?

    init(provider: AssistantProvider) {
        self.provider = provider
        self.hostname = provider.url.host ?? provider.title
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.applicationNameForUserAgent = "Ada"
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        progressObservation = webView.observe(\.estimatedProgress, options: [.initial, .new]) { [weak self] view, _ in
            MainActor.assumeIsolated { self?.progress = view.estimatedProgress }
        }
        backObservation = webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] view, _ in
            MainActor.assumeIsolated { self?.canGoBack = view.canGoBack }
        }
        urlObservation = webView.observe(\.url, options: [.new]) { [weak self] view, _ in
            MainActor.assumeIsolated { self?.hostname = view.url?.host ?? provider.title }
        }
    }

    func loadHome() {
        errorMessage = nil
        notice = nil
        webView.load(URLRequest(url: provider.url))
    }
    func reload() {
        errorMessage = nil
        if webView.url == nil { loadHome() } else { webView.reload() }
    }
    func goBack() { if webView.canGoBack { webView.goBack() } }
    func openBrowser() { NSWorkspace.shared.open(provider.url) }
    func stop() {
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        progressObservation?.invalidate()
        backObservation?.invalidate()
        urlObservation?.invalidate()
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        loading = true
        errorMessage = nil
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loading = false
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        showNavigationFailure(error)
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        showNavigationFailure(error)
    }
    private func showNavigationFailure(_ error: Error) {
        loading = false
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        errorMessage = "Sayfa açılamadı. Yenile veya tarayıcıda aç."
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        loading = false
        errorMessage = "Sohbet durdu. Sayfayı yenile."
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        let scheme = url.scheme?.lowercased()
        guard scheme == "https" || scheme == "about" else {
            notice = "Bu bağlantı burada açılamıyor."
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard let url = navigationAction.request.url, url.scheme?.lowercased() == "https" else { return nil }
        // Only a link the user clicked can open another app. Script-created popups
        // remain blocked; provider login may then be continued in a regular browser.
        if navigationAction.navigationType == .linkActivated {
            NSWorkspace.shared.open(url)
        } else {
            notice = "Giriş için tarayıcıda devam et."
        }
        return nil
    }
}

private struct AssistantChatWindow: View {
    @ObservedObject var session: AssistantWebSession

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(action: session.goBack) { Image(systemName: "chevron.left") }
                    .disabled(!session.canGoBack).help("Geri").accessibilityLabel("Geri")
                Button(action: session.reload) { Image(systemName: "arrow.clockwise") }
                    .help("Yenile").accessibilityLabel("Yenile")
                Label(session.provider.title, systemImage: "lock.fill")
                    .font(.system(size: 12, weight: .semibold))
                Text(session.hostname).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Button("Tarayıcıda aç", action: session.openBrowser)
            }.padding(.horizontal, 16).padding(.vertical, 11)
            if session.loading {
                ProgressView(value: session.progress).progressViewStyle(.linear).frame(height: 2)
            } else { Divider() }
            if let message = session.errorMessage ?? session.notice {
                HStack(spacing: 10) {
                    Image(systemName: "info.circle")
                    Text(message).font(.system(size: 11))
                    Spacer()
                    Button("Yenile", action: session.reload)
                }.padding(12).background(.orange.opacity(0.12))
            }
            AssistantWebView(webView: session.webView)
        }
        .frame(minWidth: 880, minHeight: 610)
        .buttonStyle(IslandButtonStyle(bordered: true))
    }
}

private struct AssistantWebView: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

private extension View {
    func assistantSurface() -> some View {
        background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.08), lineWidth: 0.8))
    }
}
