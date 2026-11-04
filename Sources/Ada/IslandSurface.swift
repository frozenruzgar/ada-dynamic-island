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
                if #available(macOS 26.0, *) {
                    Color.clear.glassEffect(.clear, in: shape)
                }
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
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.clear, in: Capsule())
        } else {
            content.background(.white.opacity(0.12), in: Capsule())
        }
    }
}

struct IslandControlSurface: ViewModifier {
    var cornerRadius: CGFloat = 16

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: cornerRadius))
                .glassEffect(.clear, in: RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            content
                .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 0.8))
        }
    }
}
