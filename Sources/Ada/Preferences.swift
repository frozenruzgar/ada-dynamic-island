import AdaCore
import SwiftUI

extension IslandStyle {
    var title: String { self == .notch ? L10n.string("Çentikle birleşen") : L10n.string("Yüzen panel") }
}

extension IslandStartPage {
    var title: String {
        switch self {
        case .chatGPT: return L10n.string("ChatGPT")
        case .claude: return L10n.string("Claude")
        default: return IslandPage(rawValue: rawValue)?.title ?? L10n.string("Ana ekran")
        }
    }
}

extension IslandAccent {
    var title: String {
        switch self {
        case .blue: return L10n.string("Mavi")
        case .purple: return L10n.string("Mor")
        case .mint: return L10n.string("Nane")
        case .orange: return L10n.string("Turuncu")
        }
    }
}

extension IslandPalette {
    var title: String {
        switch self {
        case .nebula: return L10n.string("Nebula · Mor / pembe")
        case .aurora: return L10n.string("Aurora · Mavi / mor")
        case .purple: return L10n.string("Mor")
        case .graphite: return L10n.string("Grafit")
        case .forest: return L10n.string("Orman")
        }
    }
}

extension IslandDisplayChoice {
    var title: String { self == .builtin ? L10n.string("MacBook’un dahili ekranı") : L10n.string("Ana ekran") }
}

extension IslandModel {
    var accentColor: Color {
        switch preferences.accent {
        case .mint: return Color(red: 0.61, green: 0.96, blue: 0.78)
        case .purple: return Color(red: 0.73, green: 0.61, blue: 1)
        case .orange: return Color(red: 1, green: 0.70, blue: 0.39)
        default: return Color(red: 0.43, green: 0.65, blue: 1)
        }
    }
    var panelGradient: [Color] {
        switch preferences.palette {
        case .graphite: return [.black, Color(white: 0.08)]
        case .forest: return [.black, Color(red: 0.04, green: 0.16, blue: 0.13)]
        case .purple: return [.black, Color(red: 0.17, green: 0.10, blue: 0.29)]
        default: return [.black, Color(red: 0.05, green: 0.10, blue: 0.23), Color(red: 0.14, green: 0.09, blue: 0.25)]
        }
    }
    var attached: Bool { preferences.style == .notch && notchWidth > 0 }
    var compactHasContent: Bool {
        activityVisible || mediaIsPlaying || clock.isRunning || clock.completed || remaining < clock.duration || preferences.showCompactBattery
    }
    var topReserve: CGFloat { playerHeaderBesideCamera ? max(30, menuClearance) : (page == .player ? 30 : 32) }
    var compactVisible: Bool { !attached || compactHasContent || !preferences.hoverToOpen }
    var closedWidth: CGFloat {
        if activityVisible { return 220 }
        if mediaIsPlaying { return attached && !compactMusicBelowMenu ? max(150, notchWidth) + 88 : 230 }
        return compactHasContent ? 166 : 116
    }
    var closedHeight: CGFloat { mediaIsPlaying ? (attached && !compactMusicBelowMenu ? max(38, menuBarHeight) : 38) : 31 }
    var primaryTitle: String {
        if clock.isRunning { return L10n.string("Duraklat") }
        if clock.completed { return preferences.pomodoro && !isBreak ? L10n.string("Molaya başla") : L10n.string("Odağa başla") }
        if remaining < clock.duration { return L10n.string("Devam et") }
        return L10n.string("Başlat")
    }
}

extension IslandPreferences {
    var initialDashboardTiles: [DashboardTile] {
        var result: [DashboardTile] = []
        if showQuickActions { result.append(DashboardTile(kind: .quickActions)) }
        if showBattery { result.append(DashboardTile(kind: .battery)) }
        if showMusic {
            let kind: DashboardTileKind = MediaSource.spotify.isInstalled ? .spotify : .appleMusic
            result.append(DashboardTile(kind: kind))
        }
        if showNotes {
            let kind: DashboardTileKind = homeMiddleCard == "chatGPT" ? .chatGPT : homeMiddleCard == "claude" ? .claude : .notes
            result.append(DashboardTile(kind: kind))
        }
        result.append(DashboardTile(kind: .focus))
        if showTasks { result.append(DashboardTile(kind: .tasks)) }
        return result
    }
}

struct GlassCard: ViewModifier {
    let model: IslandModel
    var highlighted = false
    func body(content: Content) -> some View {
        content
            .padding(13)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .islandCardSurface(cornerRadius: model.preferences.cardRadius,
                fill: AnyShapeStyle(LinearGradient(colors: [
                    highlighted ? model.accentColor.opacity(0.24) : .white.opacity(model.preferences.cardOpacity * 0.75),
                    .white.opacity(model.preferences.cardOpacity * 0.25)
                ], startPoint: .topLeading, endPoint: .bottomTrailing)),
                stroke: AnyShapeStyle(LinearGradient(colors: [.white.opacity(0.19), .white.opacity(0.055)], startPoint: .top, endPoint: .bottom)))
    }
}

extension View {
    func glassCard(_ model: IslandModel, highlighted: Bool = false) -> some View {
        modifier(GlassCard(model: model, highlighted: highlighted))
    }
}

extension IslandBackgroundMotion {
    var title: String {
        switch self {
        case .off: return L10n.string("Kapalı")
        case .gentle: return L10n.string("Hafif")
        case .normal: return L10n.string("Normal")
        }
    }
}
