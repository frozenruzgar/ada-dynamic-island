import AdaCore
import AppKit
import SwiftUI

struct IslandSurface: View {
    let palette: [Color]
    let tintIntensity: Double
    let shape: UnevenRoundedRectangle
    let backdropRadius: CGFloat

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            if reduceTransparency {
                tint
            } else {
                // Keep cross-window frosting independent of the glass controls.
                IslandBackdrop(cornerRadius: backdropRadius)
                #if compiler(>=6.2) && !ADA_LEGACY_GLASS
                if #available(macOS 26.0, *) {
                    Color.clear.glassEffect(.clear, in: shape)
                }
                #endif
                // Keep the theme a light wash over the system's frosted material.
                tint.opacity(tintIntensity * 0.16)
                LinearGradient(
                    colors: [.white.opacity(0.055), .clear, .black.opacity(0.035)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            }
        }
        .overlay {
            shape.strokeBorder(
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(0.42), location: 0),
                        .init(color: .white.opacity(0.06), location: 0.45),
                        .init(color: .white.opacity(0.23), location: 1)
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ),
                lineWidth: 0.8
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var tint: LinearGradient {
        LinearGradient(colors: palette, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

struct IslandAuroraSurface: View {
    let tintIntensity: Double
    var isAnimated = true
    var framesPerSecond: Double = 10

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let moves = isAnimated && !reduceMotion

        GeometryReader { geometry in
            TimelineView(.animation(minimumInterval: 1.0 / framesPerSecond, paused: !moves)) { context in
                let time = context.date.timeIntervalSinceReferenceDate
                let phase = moves ? time.truncatingRemainder(dividingBy: 22) / 22 * 2 * .pi : 0
                colors(phase: phase, span: max(geometry.size.width, geometry.size.height))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func colors(phase: Double, span: CGFloat) -> some View {
        let intensity = min(max(tintIntensity, 0), 1)
        let pinkCenter = UnitPoint(x: 0.86 + 0.13 * sin(phase), y: 0.12 + 0.15 * cos(phase))
        let violetCenter = UnitPoint(x: 0.20 + 0.14 * cos(phase), y: 0.86 + 0.12 * sin(phase))

        return ZStack {
            // This base fills the whole panel so neither the desktop nor other windows show through.
            LinearGradient(
                colors: [
                    Color(red: 0.11, green: 0.03, blue: 0.22),
                    Color(red: 0.25, green: 0.07, blue: 0.36),
                    Color(red: 0.15, green: 0.04, blue: 0.25)
                ],
                startPoint: .bottomLeading,
                endPoint: .topTrailing
            )
            RadialGradient(
                colors: [Color(red: 0.56, green: 0.22, blue: 1).opacity(0.26 + 0.25 * intensity), .clear],
                center: violetCenter, startRadius: 0, endRadius: span * 0.67
            )
            RadialGradient(
                colors: [Color(red: 1, green: 0.25, blue: 0.64).opacity(0.22 + 0.25 * intensity), .clear],
                center: pinkCenter, startRadius: 0, endRadius: span * 0.54
            )
            LinearGradient(
                colors: [.black.opacity(0.10), .clear, .black.opacity(0.13)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

private struct IslandBackdrop: NSViewRepresentable {
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        // This mode samples windows and desktop content behind the Ada panel.
        view.blendingMode = .behindWindow
        view.material = .popover
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        view.wantsLayer = true
        view.layer?.masksToBounds = true
        view.layer?.cornerCurve = .continuous
        view.layer?.cornerRadius = cornerRadius
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.layer?.cornerRadius = cornerRadius
    }
}

struct IslandGlassButtonSurface: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        #if compiler(>=6.2) && !ADA_LEGACY_GLASS
        if #available(macOS 26.0, *) {
            content.glassEffect(.clear, in: Capsule())
        } else {
            content.background(.white.opacity(0.12), in: Capsule())
        }
        #else
        content.background(.white.opacity(0.12), in: Capsule())
        #endif
    }
}

struct IslandControlSurface: ViewModifier {
    var cornerRadius: CGFloat = 16

    @ViewBuilder
    func body(content: Content) -> some View {
        #if compiler(>=6.2) && !ADA_LEGACY_GLASS
        if #available(macOS 26.0, *) {
            content
                .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: cornerRadius))
                .glassEffect(.clear, in: RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            legacy(content)
        }
        #else
        legacy(content)
        #endif
    }

    private func legacy(_ content: Content) -> some View {
        content.islandCardSurface(cornerRadius: cornerRadius,
            fill: AnyShapeStyle(Color.white.opacity(0.09)), stroke: AnyShapeStyle(Color.white.opacity(0.18)))
    }
}
