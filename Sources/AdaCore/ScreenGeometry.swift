import Foundation
import CoreGraphics

/// AppKit global screen coordinates, in points. Never multiply by backing scale;
/// displays may have negative origins or sit above/below the primary display.
public struct ScreenGeometry: Sendable {
    public let frame: CGRect
    public let visibleFrame: CGRect
    public let safeTop: CGFloat
    public let statusBarHeight: CGFloat
    public let auxiliaryLeft: CGRect?
    public let auxiliaryRight: CGRect?
    public init(frame: CGRect, visibleFrame: CGRect, safeTop: CGFloat, statusBarHeight: CGFloat,
                auxiliaryLeft: CGRect? = nil, auxiliaryRight: CGRect? = nil) {
        self.frame = frame; self.visibleFrame = visibleFrame
        self.safeTop = max(0, safeTop); self.statusBarHeight = max(0, statusBarHeight)
        self.auxiliaryLeft = auxiliaryLeft; self.auxiliaryRight = auxiliaryRight
    }
    public var notchWidth: CGFloat {
        guard safeTop > 0, let left = auxiliaryLeft, let right = auxiliaryRight,
              !left.isEmpty, !right.isEmpty else { return 0 }
        return max(0, right.minX - left.maxX)
    }
    public var menuBottom: CGFloat { min(visibleFrame.maxY, frame.maxY - max(safeTop, statusBarHeight)) }
    public var menuBarHeight: CGFloat { frame.maxY - menuBottom }
    public func cameraCenterX(attached: Bool) -> CGFloat {
        guard attached, notchWidth > 0, let left = auxiliaryLeft, let right = auxiliaryRight else { return frame.midX }
        return (left.maxX + right.minX) / 2
    }
    public func panelFrame(size: CGSize, attached: Bool, flushToTop: Bool, floatingGap: CGFloat,
                           attachedGap: CGFloat = 2) -> CGRect {
        let top = flushToTop ? frame.maxY : menuBottom - (attached ? attachedGap : floatingGap)
        return CGRect(x: cameraCenterX(attached: attached) - size.width / 2,
                      y: top - size.height, width: size.width, height: size.height)
    }
    public func cameraInputFrame(attached: Bool, horizontalPadding: CGFloat = 0, below: CGFloat = 0) -> CGRect? {
        guard attached, notchWidth > 0 else { return nil }
        let width = notchWidth + 2 * horizontalPadding, height = safeTop + below
        return CGRect(x: cameraCenterX(attached: true) - width / 2, y: frame.maxY - height,
                      width: width, height: height + 0.5)
    }
}
