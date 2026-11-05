@testable import Ada
@testable import AdaCore
import AppKit
import SwiftUI

enum SettingsLayoutChecks {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let size = SettingsWindowLayout.contentSize
        SettingsWindowLayout.install(on: window,
            root: Text("Settings layout validation").frame(width: size.width, height: size.height))
        window.contentView?.layoutSubtreeIfNeeded()
        precondition(window.contentViewController != nil)
        precondition(window.contentRect(forFrameRect: window.frame).size == size)
        precondition(window.contentView?.frame.size == size)
        precondition(window.contentView?.fittingSize == size)
        precondition(!window.isVisible, "Layout checks must not show or activate a window")
        window.close()
        print("PASS: native settings content frame, hosting intrinsic size and shared layout dimensions; no window shown")
    }
}
