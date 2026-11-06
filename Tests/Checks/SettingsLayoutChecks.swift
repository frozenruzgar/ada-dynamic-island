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

        let island = PanelController()
        let compact = NSRect(x: 340, y: 760, width: 116, height: 31)
        let expanded = NSRect(x: 68, y: 580, width: 660, height: 244)
        island.position(frame: compact, attached: true, expanded: false, animated: false)
        island.position(frame: expanded, attached: true, expanded: true, animated: true)
        precondition(island.panel.frame == expanded, "Buttons have their final coordinates on the opening event")
        island.position(frame: compact, attached: true, expanded: false, animated: true)
        island.position(frame: expanded, attached: true, expanded: true, animated: true)
        precondition(island.panel.frame == expanded, "Reopening takes precedence over the closing resize")
        print("PASS: native settings dimensions and immediate island interaction bounds; no window shown")
    }
}
