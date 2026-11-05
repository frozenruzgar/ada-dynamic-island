import AdaCore
import AppKit
import SwiftUI

/// Uses Spotify's own app icon without adapting it to Ada's accent or appearance.
@MainActor
struct SpotifyBrandIcon: View {
    let size: CGFloat
    var circularMark = false

    private static var cachedIcon: (url: URL, image: NSImage)?

    var body: some View {
        Group {
            if let image = Self.installedIcon() {
                let original = Image(nsImage: image)
                    .renderingMode(.original)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                if circularMark {
                    // The green disc occupies 64% of the desktop icon. Trim its outer plate.
                    original.frame(width: size / 0.64, height: size / 0.64)
                        .frame(width: size, height: size)
                        .clipShape(Circle())
                } else {
                    original
                }
            } else {
                Image(systemName: "music.note.list")
                    .adaFont(size: size * 0.55, weight: .semibold)
                    .foregroundStyle(.green)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private static func installedIcon() -> NSImage? {
        let workspace = NSWorkspace.shared
        guard let url = workspace.urlForApplication(withBundleIdentifier: "com.spotify.client") else { return nil }
        if let cachedIcon, cachedIcon.url == url { return cachedIcon.image }

        let bundle = Bundle(url: url)
        let iconName = bundle?.object(forInfoDictionaryKey: "CFBundleIconFile") as? String
        let iconURL = iconName.flatMap {
            bundle?.url(forResource: ($0 as NSString).deletingPathExtension, withExtension: "icns")
        }
        let image = iconURL.flatMap(NSImage.init(contentsOf:)) ?? workspace.icon(forFile: url.path)
        cachedIcon = (url, image)
        return image
    }
}
