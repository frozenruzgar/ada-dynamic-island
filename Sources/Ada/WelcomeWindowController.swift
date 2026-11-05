import AppKit
import SwiftUI

@MainActor
final class WelcomeWindowController {
    private var window: NSWindow?
    var isVisible: Bool { window?.isVisible == true }

    func show(textScale: Double, shortcut: String?) {
        if window?.isVisible != true {
            let root = WelcomeView(shortcut: shortcut) { [weak self] in self?.window?.close() }
                .environment(\.adaTextScale, textScale)
                .fixedSize(horizontal: true, vertical: true)
            let window = NSWindow(contentViewController: NSHostingController(rootView: root))
            window.styleMask = [.titled, .closable]
            window.title = L10n.string("Ada’ya hoş geldin")
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct WelcomeView: View {
    let shortcut: String?
    var dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(L10n.string("Ada’ya hoş geldin"), systemImage: "capsule.tophalf.filled")
                .adaFont(size: 23, weight: .semibold)
                .accessibilityAddTraits(.isHeader)

            tip("cursorarrow", L10n.string("Fareyi ekranın üst ortasına götür. Çentiksiz ekranda Ada çubuğunu kullan."))
            if let shortcut {
                tip("keyboard", L10n.string("Klavyeyle açıp kapatmak için \(shortcut) tuşlarına bas."))
            } else {
                tip("keyboard", L10n.string("Klavye kısayolunu Ayarlar → Davranış bölümünden açabilirsin."))
            }
            tip("menubar.rectangle", L10n.string("Menü çubuğundaki Ada simgesinden ayarlara ulaşabilirsin."))
            tip("lock.shield", L10n.string("Kamera ve bildirim izinleri yalnız ilgili özelliği açtığında istenir. Müzik denetimi için macOS Otomasyon izni gerekebilir."))

            HStack {
                Spacer()
                Button(L10n.string("Başla"), action: dismiss)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 476, alignment: .leading)
        .adaFont(size: 13)
    }

    private func tip(_ symbol: String, _ title: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(title)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
