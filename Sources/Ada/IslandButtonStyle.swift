import AdaCore
import SwiftUI

/// Expands like the video reference; bordered buttons add adaptive window chrome.
struct IslandButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 10
    var emphasis: Bool = false
    var bordered: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        IslandButtonBody(
            configuration: configuration,
            cornerRadius: cornerRadius,
            emphasis: emphasis,
            bordered: bordered
        )
    }
}

private struct IslandButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let cornerRadius: CGFloat
    let emphasis: Bool
    let bordered: Bool

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    private var isPressed: Bool { isEnabled && configuration.isPressed }
    private var isHighlighted: Bool { isEnabled && (isHovered || isPressed) }
    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    private var scale: CGFloat {
        guard isEnabled, !reduceMotion else { return 1 }
        return isPressed ? 1.07 : (isHovered ? 1.025 : 1)
    }

    private var response: Animation {
        if reduceMotion { return .easeOut(duration: 0.12) }
        return isPressed
            ? .easeOut(duration: 0.1)
            : .spring(duration: 0.32, bounce: 0.22)
    }

    var body: some View {
        configuration.label
            .padding(.horizontal, bordered ? 10 : 0)
            .padding(.vertical, bordered ? 5 : 0)
            .background {
                if bordered {
                    shape.fill(.regularMaterial)
                        .overlay {
                            shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.7)
                        }
                }
            }
            .overlay {
                ZStack {
                    shape.fill(
                        LinearGradient(
                            colors: [
                                .white.opacity(isPressed ? 0.15 : 0.055),
                                .clear,
                                .accentColor.opacity(isPressed ? 0.085 : 0.025)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    shape.strokeBorder(
                        LinearGradient(
                            colors: [
                                .white.opacity(isPressed ? 0.6 : 0.25),
                                .white.opacity(0.035),
                                .accentColor.opacity(isPressed ? 0.35 : 0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: isPressed ? 0.9 : 0.65
                    )
                    .shadow(
                        color: .accentColor.opacity(isPressed ? (emphasis ? 0.2 : 0.12) : 0),
                        radius: emphasis ? 10 : 7
                    )
                }
                .opacity(isHighlighted ? 1 : 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .opacity(isEnabled ? 1 : 0.55)
            .scaleEffect(scale)
            .contentShape(.interaction, Rectangle())
            .animation(response, value: isPressed)
            .animation(.easeOut(duration: 0.18), value: isHovered)
            .onHover { isHovered = isEnabled && $0 }
            .onChange(of: isEnabled) { _, enabled in
                if !enabled { isHovered = false }
            }
    }
}
