import AdaCore
import AppKit
import SwiftUI
import WebKit

/// The assistant launcher does not use API credentials or submit prompts.
/// Draft text stays in memory until the user explicitly copies it.
enum AssistantProvider: String, CaseIterable, Identifiable {
    case chatGPT, claude
    var id: String { rawValue }
    var title: String { self == .chatGPT ? L10n.string("ChatGPT") : L10n.string("Claude") }
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
        case .ask: return L10n.string("Soru sor")
        case .summarize: return L10n.string("Özetle")
        case .improve: return L10n.string("Düzelt")
        case .translate: return L10n.string("İngilizceye çevir")
        case .email: return L10n.string("E-posta taslağı")
        }
    }
    var instruction: String {
        switch self {
        case .ask: return ""
        case .summarize: return L10n.string("Aşağıdaki metni Türkçe, kısa ve anlaşılır biçimde özetle. Ana noktaları koru:")
        case .improve: return L10n.string("Aşağıdaki metnin anlamını koruyarak yazımını ve anlatımını düzelt. Yalnızca düzeltilmiş metni ver:")
        case .translate: return L10n.string("Aşağıdaki metni doğal ve anlamı koruyan bir İngilizceyle çevir:")
        case .email: return L10n.string("Aşağıdaki notlardan konu satırı ve gövdesi olan açık, profesyonel bir Türkçe e-posta taslağı hazırla. Eksik bilgileri uydurma:")
        }
    }
}

@MainActor
final class AssistantStore: NSObject, ObservableObject, NSWindowDelegate {
    @Published var provider: AssistantProvider {
        didSet { defaults.set(provider.rawValue, forKey: "assistantProvider") }
    }
    @Published var task: AssistantTask = .ask
    @Published var draft = ""
    @Published private(set) var status = ""
    @Published private(set) var clearingSessions = false
    @Published private(set) var sessionStatus: String?

    private let defaults: UserDefaults
    private var windows: [AssistantProvider: NSWindow] = [:]
    private var sessions: [AssistantProvider: AssistantWebSession] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        provider = AssistantProvider(rawValue: defaults.string(forKey: "assistantProvider") ?? "") ?? .chatGPT
        super.init()
    }

    var preparedPrompt: String {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }
        return task.instruction.isEmpty ? text : "\(task.instruction)\n\n\(text)"
    }

    func readClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
            status = L10n.string("Panoda metin yok.")
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
            status = L10n.string("Bir soru veya metin yaz.")
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(preparedPrompt, forType: .string)
        status = L10n.string("Kopyalandı. Sohbete yapıştır.")
        showChat()
    }

    /// Opening a chat is the first point at which this feature accesses the network.
    func showChat() {
        guard !clearingSessions else { return }
        let target = provider
        if let window = windows[target] {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            return
        }
        let session = AssistantWebSession(provider: target)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 740),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = L10n.string("Ada · \(target.title)")
        window.minSize = NSSize(width: 900, height: 650)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: AssistantChatWindow(session: session))
        window.center()
        sessions[target] = session
        windows[target] = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        session.loadHome()
    }

    func openInBrowser() {
        // Use only the provider's official landing URL. Drafts and credentials are
        // never encoded into URLs, and no session data is copied to another app.
        status = NSWorkspace.shared.open(provider.url) ? "" : L10n.string("Tarayıcı açılamadı.")
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let provider = windows.first(where: { $0.value === window })?.key else { return }
        sessions[provider]?.stop()
        window.contentView = nil
        windows.removeValue(forKey: provider)
        sessions.removeValue(forKey: provider)
    }

    func clearSessions(erase: (@MainActor () async -> Void)? = nil) async {
        guard !clearingSessions else { return }
        clearingSessions = true
        sessionStatus = nil
        closeWindows()
        if let erase { await erase() }
        else {
            await WKWebsiteDataStore.default().removeData(
                ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
        }
        clearingSessions = false
        sessionStatus = L10n.string("Ada’daki sohbet oturumları temizlendi.")
    }

    func shutdown() {
        closeWindows()
        draft = ""
    }

    private func closeWindows() {
        for session in sessions.values { session.stop() }
        for window in windows.values { window.delegate = nil; window.close() }
        windows.removeAll()
        sessions.removeAll()
    }
}

struct AssistantView: View {
    @ObservedObject var store: AssistantStore
    var accent: Color = Color(red: 0.54, green: 0.69, blue: 1)
    var onSelectProvider: () -> Void = {}

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                Picker(L10n.string("Sohbet hizmeti"), selection: Binding(get: { store.provider }, set: { provider in
                    store.provider = provider
                    onSelectProvider()
                })) {
                    ForEach(AssistantProvider.allCases) { provider in
                        Text(provider.title).tag(provider)
                    }
                }.labelsHidden().pickerStyle(.segmented)
                Button(action: store.showChat) {
                    Label(L10n.string("Sohbeti aç"), systemImage: "bubble.left.and.bubble.right")
                        .adaFont(size: 11, weight: .semibold)
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 11))
                }.buttonStyle(IslandButtonStyle()).foregroundStyle(accent)
                Button(action: store.openInBrowser) {
                    Label(L10n.string("Tarayıcıda aç"), systemImage: "arrow.up.right.square")
                        .adaFont(size: 10, weight: .medium)
                }.buttonStyle(IslandButtonStyle()).foregroundStyle(.white.opacity(0.65))
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(width: 232)
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .assistantSurface()

            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text(L10n.string("Taslak")).adaFont(size: 12, weight: .semibold)
                    Spacer()
                    Picker(L10n.string("İstek türü"), selection: $store.task) {
                        ForEach(AssistantTask.allCases) { task in Text(task.title).tag(task) }
                    }.labelsHidden().frame(maxWidth: 180)
                }
                ZStack(alignment: .topLeading) {
                    if store.draft.isEmpty {
                        Text(L10n.string("Soru veya metin…"))
                            .adaFont(size: 12).foregroundStyle(Palette.tertiaryText)
                            .padding(.top, 6).padding(.leading, 5).allowsHitTesting(false)
                    }
                    TextEditor(text: $store.draft)
                        .adaFont(size: 12)
                        .scrollContentBackground(.hidden)
                        .accessibilityLabel(L10n.string("Taslak metni"))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(5)
                .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                HStack(spacing: 12) {
                    Button(L10n.string("Panodan al"), action: store.readClipboard)
                    Button(L10n.string("Temizle"), action: store.clearDraft).disabled(store.draft.isEmpty)
                    Spacer(minLength: 0)
                    Button(action: store.copyAndOpen) {
                        Label(L10n.string("Kopyala ve aç"), systemImage: "arrow.up.right")
                            .adaFont(size: 11, weight: .semibold)
                            .padding(.horizontal, 13).padding(.vertical, 8)
                            .foregroundStyle(accent).background(accent.opacity(0.13), in: Capsule())
                    }.disabled(store.preparedPrompt.isEmpty)
                }.adaFont(size: 10).buttonStyle(IslandButtonStyle(cornerRadius: 100))
                Text(store.status.isEmpty ? L10n.string("Kopyaladıktan sonra sohbete yapıştır.") : store.status)
                    .adaFont(size: 10).foregroundStyle(.white.opacity(0.60)).lineLimit(2)
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
        errorMessage = L10n.string("Sayfa açılamadı. Yenile veya tarayıcıda aç.")
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        loading = false
        errorMessage = L10n.string("Sohbet durdu. Sayfayı yenile.")
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        let scheme = url.scheme?.lowercased()
        guard scheme == "https" || scheme == "about" else {
            notice = L10n.string("Bu bağlantı burada açılamıyor.")
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
            notice = L10n.string("Giriş için tarayıcıda devam et.")
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
                    .disabled(!session.canGoBack).help(L10n.string("Geri")).accessibilityLabel(L10n.string("Geri"))
                Button(action: session.reload) { Image(systemName: "arrow.clockwise") }
                    .help(L10n.string("Yenile")).accessibilityLabel(L10n.string("Yenile"))
                Label(session.provider.title, systemImage: "lock.fill")
                    .adaFont(size: 12, weight: .semibold)
                Text(session.hostname).adaFont(size: 10).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Button(L10n.string("Tarayıcıda aç"), action: session.openBrowser)
            }.padding(.horizontal, 16).padding(.vertical, 11)
            if session.loading {
                ProgressView(value: session.progress).progressViewStyle(.linear).frame(height: 2)
            } else { Divider() }
            if let message = session.errorMessage ?? session.notice {
                HStack(spacing: 10) {
                    Image(systemName: "info.circle")
                    Text(message).adaFont(size: 11)
                    Spacer()
                    Button(L10n.string("Yenile"), action: session.reload)
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
        islandCardSurface(cornerRadius: 18)
    }
}
