import AdaCore
import AppKit
import SwiftUI

enum Typography {
    static let caption: CGFloat = 10
    static let body: CGFloat = 12
    static let title: CGFloat = 21
}
enum Palette {
    static let primaryText = Color.white
    static let secondaryText = Color.white.opacity(0.68)
    static let tertiaryText = Color.white.opacity(0.6)
    static let cardFill = Color.white.opacity(0.04)
    static let cardStroke = Color.white.opacity(0.12)
}
private struct AdaTextScaleKey: EnvironmentKey { static let defaultValue = 1.0 }
extension EnvironmentValues {
    var adaTextScale: Double {
        get { self[AdaTextScaleKey.self] }
        set { self[AdaTextScaleKey.self] = newValue }
    }
}
private struct AdaFont: ViewModifier {
    private static let medium = "AvenirNext-Medium"
    private static let demiBold = "AvenirNext-DemiBold"
    private static let bold = "AvenirNext-Bold"
    private static let availableFaces = Set([medium, demiBold, bold].filter { NSFont(name: $0, size: 12) != nil })

    let size: CGFloat
    let weight: Font.Weight
    let design: Font.Design
    @Environment(\.adaTextScale) private var scale

    func body(content: Content) -> some View {
        let pointSize = TypographyMetrics.pointSize(base: size, scale: scale)
        if design != .monospaced, let face, Self.availableFaces.contains(face) {
            content.font(.custom(face, fixedSize: pointSize))
        } else {
            content.font(.system(size: pointSize, weight: weight, design: design))
        }
    }

    private var face: String? {
        switch weight {
        case .regular: return Self.medium
        case .medium: return Self.demiBold
        case .semibold, .bold: return Self.bold
        default: return nil
        }
    }
}
struct IslandCardSurface: ViewModifier {
    var cornerRadius: CGFloat = 17
    var fill = AnyShapeStyle(Palette.cardFill)
    var stroke = AnyShapeStyle(Palette.cardStroke)
    var lineWidth: CGFloat = 0.8
    func body(content: Content) -> some View {
        content.background(fill, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(stroke, lineWidth: lineWidth)
                .allowsHitTesting(false))
    }
}
extension View {
    func adaFont(size: CGFloat = Typography.body, weight: Font.Weight = .regular, design: Font.Design = .default) -> some View {
        modifier(AdaFont(size: size, weight: weight, design: design))
    }
    func islandCardSurface(cornerRadius: CGFloat = 17, fill: AnyShapeStyle = AnyShapeStyle(Palette.cardFill),
                           stroke: AnyShapeStyle = AnyShapeStyle(Palette.cardStroke), lineWidth: CGFloat = 0.8) -> some View {
        modifier(IslandCardSurface(cornerRadius: cornerRadius, fill: fill, stroke: stroke, lineWidth: lineWidth))
    }
}
