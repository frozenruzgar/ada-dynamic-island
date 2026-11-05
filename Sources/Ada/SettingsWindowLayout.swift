import AdaCore
import AppKit
import SwiftUI

@MainActor
enum SettingsWindowLayout {
    static let contentSize = CGSize(width: 620, height: 660)

    static func install<Content: View>(on window: NSWindow, root: Content) {
        window.contentViewController = NSHostingController(rootView: root.fixedSize())
        window.setContentSize(contentSize)
    }
}
