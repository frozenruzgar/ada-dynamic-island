import AdaCore
import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private(set) var window: NSWindow?
    func prepare<Content: View>(@ViewBuilder content: () -> Content) {
        guard window == nil else { return }
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: SettingsWindowLayout.contentSize),
            styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = L10n.string("Ada Ayarları")
        window.isReleasedWhenClosed = false
        SettingsWindowLayout.install(on: window, root: content())
        window.center()
        self.window = window
    }
    func show() { NSApp.activate(); window?.makeKeyAndOrderFront(nil) }
}
