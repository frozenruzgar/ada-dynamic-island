import Foundation

public enum TypographyMetrics {
    public static func pointSize(base: Double, scale: Double) -> Double {
        let base = base.isFinite ? max(10, base) : 12
        let scale = scale.isFinite ? min(1.15, max(0.9, scale)) : 1
        return max(10, base * scale)
    }
}
