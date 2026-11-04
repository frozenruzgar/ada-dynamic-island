import SwiftUI

enum IslandStyle: String, CaseIterable, Identifiable {
    case notch, floating
    var id: String { rawValue }
    var title: String { self == .notch ? "Çentikle birleşen" : "Yüzen panel" }
}

struct IslandPreferences: Codable, Equatable {
    var style = "notch"
    var expandedWidth: Double = 660
    var contentHeight: Double = 212
    var floatingGap: Double = 8
    var hoverToOpen = true
    private var hoverSettingsVersion: Int? = 1
    var closeDelay: Double = 0.2
    var showCompactBattery = false
    var showOnCompletion = true
    var defaultMinutes = 25
    var accent = "blue"
    var palette = "aurora"
    var cardOpacity: Double = 0.13
    var cardRadius: Double = 19
    var textScale: Double = 1
    var showNotes = true
    var showTasks = true
    var showBattery = true
    var showQuickActions = true
    var showMusic = true
    var showNowPlaying = true
    var pomodoro = true
    var breakMinutes = 5
    var displayChoice = "builtin"
    var shelfRetentionDays = 1
    var panelOpacity: Double = 0.66
    var startupPage = "chatGPT"
    var homeMiddleCard = "chatGPT"
    var monitoringEnabled = true
    var globalShortcutEnabled = true

    init() {}

    private struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(_ value: String) { stringValue = value }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: AnyKey.self)
        func read<T: Decodable>(_ key: String, _ fallback: T) -> T {
            (try? values.decodeIfPresent(T.self, forKey: AnyKey(key))) ?? fallback
        }
        style = read("style", style)
        if values.contains(AnyKey("panelOpacity")) {
            expandedWidth = read("expandedWidth", expandedWidth)
        }
        contentHeight = read("contentHeight", contentHeight)
        floatingGap = read("floatingGap", floatingGap)
        if values.contains(AnyKey("panelOpacity")) {
            hoverToOpen = read("hoverToOpen", hoverToOpen)
            closeDelay = read("closeDelay", closeDelay)
        }
        hoverSettingsVersion = try? values.decodeIfPresent(Int.self, forKey: AnyKey("hoverSettingsVersion"))
        showCompactBattery = read("showCompactBattery", showCompactBattery)
        showOnCompletion = read("showOnCompletion", showOnCompletion)
        defaultMinutes = read("defaultMinutes", defaultMinutes)
        accent = read("accent", accent)
        palette = read("palette", palette)
        cardOpacity = read("cardOpacity", cardOpacity)
        cardRadius = read("cardRadius", cardRadius)
        textScale = read("textScale", textScale)
        showNotes = read("showNotes", showNotes)
        showTasks = read("showTasks", showTasks)
        showBattery = read("showBattery", showBattery)
        showQuickActions = read("showQuickActions", showQuickActions)
        showMusic = read("showMusic", showMusic)
        showNowPlaying = read("showNowPlaying", showNowPlaying)
        pomodoro = read("pomodoro", pomodoro)
        breakMinutes = read("breakMinutes", breakMinutes)
        displayChoice = read("displayChoice", displayChoice)
        shelfRetentionDays = read("shelfRetentionDays", shelfRetentionDays)
        panelOpacity = read("panelOpacity", panelOpacity)
        startupPage = read("startupPage", startupPage)
        homeMiddleCard = read("homeMiddleCard", homeMiddleCard)
        monitoringEnabled = read("monitoringEnabled", monitoringEnabled)
        globalShortcutEnabled = read("globalShortcutEnabled", globalShortcutEnabled)
    }


    static func load() -> Self {
        // A new preference key preserves the older version's settings while adopting
        // the wider reference layout. Subsequent launches preserve customization.
        guard let data = UserDefaults.standard.data(forKey: "workspacePreferencesV3"),
              var value = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        value.expandedWidth = min(880, max(620, value.expandedWidth))
        value.contentHeight = min(340, max(210, value.contentHeight))
        value.panelOpacity = min(0.95, max(0.30, value.panelOpacity))
        value.closeDelay = min(1.5, max(0.12, value.closeDelay))
        value.cardOpacity = min(0.3, max(0.05, value.cardOpacity))
        value.cardRadius = min(28, max(10, value.cardRadius))
        value.textScale = min(1.15, max(0.9, value.textScale))
        value.defaultMinutes = min(180, max(1, value.defaultMinutes))
        // Adopt hover activation once on upgrade. Later changes to the toggle persist.
        if value.hoverSettingsVersion == nil {
            value.hoverToOpen = true
            value.hoverSettingsVersion = 1
            if let updated = try? JSONEncoder().encode(value) {
                UserDefaults.standard.set(updated, forKey: "workspacePreferencesV3")
            }
        }
        return value
    }
}

extension IslandModel {
    var accentColor: Color {
        switch preferences.accent {
        case "mint": return Color(red: 0.61, green: 0.96, blue: 0.78)
        case "purple": return Color(red: 0.73, green: 0.61, blue: 1)
        case "orange": return Color(red: 1, green: 0.70, blue: 0.39)
        default: return Color(red: 0.43, green: 0.65, blue: 1)
        }
    }
    var panelGradient: [Color] {
        switch preferences.palette {
        case "graphite": return [.black, Color(white: 0.08)]
        case "forest": return [.black, Color(red: 0.04, green: 0.16, blue: 0.13)]
        case "purple": return [.black, Color(red: 0.17, green: 0.10, blue: 0.29)]
        default: return [.black, Color(red: 0.05, green: 0.10, blue: 0.23), Color(red: 0.14, green: 0.09, blue: 0.25)]
        }
    }
    var attached: Bool { preferences.style == "notch" && notchWidth > 0 }
    var compactHasContent: Bool {
        mediaIsPlaying || clock.isRunning || clock.completed || remaining < clock.duration || preferences.showCompactBattery
    }
    var topReserve: CGFloat { 40 }
    var compactVisible: Bool { !attached || compactHasContent || !preferences.hoverToOpen }
    var closedWidth: CGFloat {
        if mediaIsPlaying { return attached ? max(150, notchWidth) + 88 : 230 }
        return compactHasContent ? 166 : 116
    }
    var closedHeight: CGFloat { mediaIsPlaying ? (attached ? max(38, menuBarHeight) : 38) : 31 }
    var primaryTitle: String {
        if clock.isRunning { return "Duraklat" }
        if clock.completed { return preferences.pomodoro && !isBreak ? "Molaya başla" : "Odağa başla" }
        if remaining < clock.duration { return "Devam et" }
        return "Başlat"
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
            .background {
                RoundedRectangle(cornerRadius: model.preferences.cardRadius)
                    .fill(LinearGradient(colors: [
                        highlighted ? model.accentColor.opacity(0.24) : .white.opacity(model.preferences.cardOpacity * 0.75),
                        .white.opacity(model.preferences.cardOpacity * 0.25)
                    ], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            .overlay {
                RoundedRectangle(cornerRadius: model.preferences.cardRadius)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.19), .white.opacity(0.055)], startPoint: .top, endPoint: .bottom), lineWidth: 0.8)
            }
    }
}

extension View {
    func glassCard(_ model: IslandModel, highlighted: Bool = false) -> some View {
        modifier(GlassCard(model: model, highlighted: highlighted))
    }
}
