import AdaCore
import AppKit
import SwiftUI
import QuartzCore

private final class IslandHostingView: NSHostingView<IslandView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var needsPanelToBecomeKey: Bool { true }
}

final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    var usesFullScreenFrame = false
    var onPrimaryClick: ((NSPoint) -> Bool)?
    var onFilePaste: (() -> Bool)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if isKeyWindow, modifiers == .command, event.charactersIgnoringModifiers?.lowercased() == "v",
           onFilePaste?() == true { return true }
        return super.performKeyEquivalent(with: event)
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown {
            if !event.modifierFlags.contains(.control),
               onPrimaryClick?(convertPoint(toScreen: event.locationInWindow)) == true {
                return
            }
            // Key the nonactivating panel before AppKit dispatches to a SwiftUI control.
            if !isKeyWindow { makeKey() }
        }
        super.sendEvent(event)
    }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        // The controller already fits the flush frame to the display. Do not
        // constrain it again to the work area beneath the menu bar.
        usesFullScreenFrame ? frameRect : super.constrainFrameRect(frameRect, to: screen)
    }
}

@MainActor
final class PanelController {
    let panel: IslandPanel
    private(set) var lastTargetFrame: NSRect?
    init() {
        panel = IslandPanel(contentRect: .zero,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isReleasedWhenClosed = false
        // Place the island below system menu titles and status items.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue - 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isMovable = false
        panel.acceptsMouseMovedEvents = true
    }
    func install(root: IslandView) { panel.contentView = IslandHostingView(rootView: root) }
    func position(frame: NSRect, attached: Bool, expanded: Bool, animated: Bool) {
        panel.usesFullScreenFrame = attached
        guard frame != lastTargetFrame else { return }
        lastTargetFrame = frame
        // Open controls at their final coordinates. SwiftUI animates their appearance.
        if animated && !expanded && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.38
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 0.72, 0.28, 1)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            // This also replaces a closing frame animation if Ada reopens mid-transition.
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                panel.animator().setFrame(frame, display: true)
            }
        }
    }
}
