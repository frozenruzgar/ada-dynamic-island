import Foundation

public protocol IslandPreferenceOption: RawRepresentable, Codable, CaseIterable, Identifiable, Hashable, Sendable where RawValue == String {
    static var defaultValue: Self { get }
}

extension IslandPreferenceOption {
    public var id: String { rawValue }
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = (try? container.decode(String.self)) ?? ""
        self = Self(rawValue: raw) ?? Self.defaultValue
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum IslandStyle: String, IslandPreferenceOption {
    case notch, floating
    public static let defaultValue = Self.notch
}
public enum IslandAccent: String, IslandPreferenceOption {
    case blue, purple, mint, orange
    public static let defaultValue = Self.blue
}
public enum IslandPalette: String, IslandPreferenceOption {
    case nebula, aurora, purple, graphite, forest
    public static let defaultValue = Self.nebula
}
public enum IslandBackgroundMotion: String, IslandPreferenceOption {
    case off, gentle, normal
    public static let defaultValue = Self.gentle
    public var framesPerSecond: Double { self == .normal ? 20 : 10 }
}
public enum IslandDisplayChoice: String, IslandPreferenceOption {
    case builtin, main
    public static let defaultValue = Self.builtin
}
public enum IslandStartPage: String, IslandPreferenceOption {
    case chatGPT, claude, home, menu, assistant, files, system, cloud, tools, prompter
    public static let defaultValue = Self.chatGPT
}

public struct IslandPreferences: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1
    private(set) var schemaVersion = Self.currentSchemaVersion
    public static let nebulaPalette = IslandPalette.nebula
    public static let closeDelayRange: ClosedRange<Double> = 0.12...1.5

    public var style = IslandStyle.notch
    public var expandedWidth: Double = 660
    public var contentHeight: Double = 212
    public var floatingGap: Double = 8
    public var hoverToOpen = true
    public var openShelfOnDrag = true
    public var closeDelay: Double = 0.2
    public var showCompactBattery = false
    public var showCalendarEvents = false
    public var showOnCompletion = true
    public var notifyOnCompletion = false
    public var defaultMinutes = 25
    public var accent = IslandAccent.blue
    public var palette = Self.nebulaPalette
    public var backgroundMotion = IslandBackgroundMotion.gentle
    public var cardOpacity: Double = 0.13
    public var cardRadius: Double = 19
    public var textScale: Double = 1
    public var showNotes = true
    public var showTasks = true
    public var showBattery = true
    public var showQuickActions = true
    public var showMusic = true
    public var showNowPlaying = true
    public var keepCompactMusicBelowMenu = false
    public var pomodoro = true
    public var breakMinutes = 5
    public var displayChoice = IslandDisplayChoice.builtin
    public var panelOpacity: Double = 0.66
    public var startupPage = IslandStartPage.chatGPT
    public var homeMiddleCard = "chatGPT"
    public var monitoringEnabled = true
    public var globalShortcutEnabled = true
    public var panelShortcut = ShortcutBinding.standard
    public var filesShortcut: ShortcutBinding?

    public init() {}

    public var supportsPersistence: Bool { schemaVersion <= Self.currentSchemaVersion }

    public var usesNebulaPalette: Bool { palette == Self.nebulaPalette }

    public mutating func resetAppearance() {
        let defaults = Self()
        startupPage = defaults.startupPage
        style = defaults.style
        expandedWidth = defaults.expandedWidth
        contentHeight = defaults.contentHeight
        floatingGap = defaults.floatingGap
        accent = defaults.accent
        palette = defaults.palette
        backgroundMotion = defaults.backgroundMotion
        panelOpacity = defaults.panelOpacity
        cardOpacity = defaults.cardOpacity
        cardRadius = defaults.cardRadius
        textScale = defaults.textScale
    }

    private struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(_ value: String) { stringValue = value }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    public init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: AnyKey.self)
        func read<T: Decodable>(_ key: String, _ fallback: T) -> T {
            (try? values.decodeIfPresent(T.self, forKey: AnyKey(key))) ?? fallback
        }
        style = read("style", style)
        expandedWidth = read("expandedWidth", expandedWidth)
        contentHeight = read("contentHeight", contentHeight)
        floatingGap = read("floatingGap", floatingGap)
        hoverToOpen = read("hoverToOpen", hoverToOpen)
        openShelfOnDrag = read("openShelfOnDrag", openShelfOnDrag)
        closeDelay = read("closeDelay", closeDelay)
        showCompactBattery = read("showCompactBattery", showCompactBattery)
        showCalendarEvents = read("showCalendarEvents", showCalendarEvents)
        showOnCompletion = read("showOnCompletion", showOnCompletion)
        notifyOnCompletion = read("notifyOnCompletion", notifyOnCompletion)
        defaultMinutes = read("defaultMinutes", defaultMinutes)
        accent = read("accent", accent)
        palette = read("palette", palette)
        backgroundMotion = read("backgroundMotion", backgroundMotion)
        cardOpacity = read("cardOpacity", cardOpacity)
        cardRadius = read("cardRadius", cardRadius)
        textScale = read("textScale", textScale)
        showNotes = read("showNotes", showNotes)
        showTasks = read("showTasks", showTasks)
        showBattery = read("showBattery", showBattery)
        showQuickActions = read("showQuickActions", showQuickActions)
        showMusic = read("showMusic", showMusic)
        showNowPlaying = read("showNowPlaying", showNowPlaying)
        keepCompactMusicBelowMenu = read("keepCompactMusicBelowMenu", keepCompactMusicBelowMenu)
        pomodoro = read("pomodoro", pomodoro)
        breakMinutes = read("breakMinutes", breakMinutes)
        displayChoice = read("displayChoice", displayChoice)
        panelOpacity = read("panelOpacity", panelOpacity)
        startupPage = read("startupPage", startupPage)
        homeMiddleCard = read("homeMiddleCard", homeMiddleCard)
        monitoringEnabled = read("monitoringEnabled", monitoringEnabled)
        globalShortcutEnabled = read("globalShortcutEnabled", globalShortcutEnabled)
        panelShortcut = read("panelShortcut", panelShortcut)
        filesShortcut = read("filesShortcut", filesShortcut)
        if panelShortcut.conflicts(with: filesShortcut) { filesShortcut = nil }
        schemaVersion = max(0, read("schemaVersion", 0))
        // The obsolete marker is consulted only while converting unversioned data.
        let legacyHoverConfigured = read("hoverSettingsVersion", 0) >= 1
        migrate(legacyHoverConfigured: legacyHoverConfigured)
        normalizeNumericValues()
    }


    private mutating func migrate(legacyHoverConfigured: Bool) {
        while schemaVersion < Self.currentSchemaVersion {
            switch schemaVersion {
            case 0:
                migrateVersion0To1(legacyHoverConfigured: legacyHoverConfigured)
            default:
                return
            }
        }
    }

    private mutating func migrateVersion0To1(legacyHoverConfigured: Bool) {
        if !legacyHoverConfigured { hoverToOpen = true }
        schemaVersion = 1
    }

    private mutating func normalizeNumericValues() {
        let defaults = Self()
        func bounded(_ value: Double, _ range: ClosedRange<Double>, fallback: Double) -> Double {
            value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback
        }
        expandedWidth = bounded(expandedWidth, 620...880, fallback: defaults.expandedWidth)
        contentHeight = bounded(contentHeight, 210...340, fallback: defaults.contentHeight)
        floatingGap = bounded(floatingGap, 0...40, fallback: defaults.floatingGap)
        panelOpacity = bounded(panelOpacity, 0.30...0.95, fallback: defaults.panelOpacity)
        closeDelay = bounded(closeDelay, Self.closeDelayRange, fallback: defaults.closeDelay)
        cardOpacity = bounded(cardOpacity, 0.05...0.3, fallback: defaults.cardOpacity)
        cardRadius = bounded(cardRadius, 10...28, fallback: defaults.cardRadius)
        textScale = bounded(textScale, 0.9...1.15, fallback: defaults.textScale)
        defaultMinutes = min(180, max(1, defaultMinutes))
        breakMinutes = min(30, max(1, breakMinutes))
    }

    public static func load(defaults: UserDefaults = .standard) -> Self {
        let key = "workspacePreferencesV3"
        guard let data = defaults.data(forKey: key),
              let value = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        let fields = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let sourceVersion = max(0, fields?["schemaVersion"] as? Int ?? 0)
        if sourceVersion < Self.currentSchemaVersion, let updated = try? JSONEncoder().encode(value) {
            defaults.set(updated, forKey: key)
        }
        return value
    }
}
