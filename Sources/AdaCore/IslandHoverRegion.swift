import CoreGraphics

/// The physical camera and the visible island form one continuous hover area.
public struct IslandHoverRegion {
    private let panel: CGRect?
    private let camera: CGRect?

    public init(panel: CGRect?, camera: CGRect? = nil) {
        self.panel = panel?.insetBy(dx: -4, dy: -4)
        self.camera = camera
    }

    public func contains(_ pointer: CGPoint) -> Bool {
        if let camera, contains(pointer, in: camera) { return true }
        return panel.map { contains(pointer, in: $0) } ?? false
    }

    private func contains(_ pointer: CGPoint, in frame: CGRect) -> Bool {
        // The top edge is a valid pointer position, so include maxY.
        pointer.x >= frame.minX && pointer.x <= frame.maxX &&
        pointer.y >= frame.minY && pointer.y <= frame.maxY
    }
}
