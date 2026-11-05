import AppKit
import SwiftUI
import IOKit.ps
import AdaCore

@MainActor
final class IslandModel: ObservableObject {
    @Published var preferences: IslandPreferences {
        didSet {
            if preferences.supportsPersistence, let data = try? JSONEncoder().encode(preferences) {
                defaults.set(data, forKey: "workspacePreferencesV3")
            }
            layoutChanged?()
        }
    }
    @Published var page: IslandPage = .home {
        didSet { if page != oldValue { layoutChanged?() } }
    }
    @Published private(set) var pageBeforeUtility: IslandPage = .home

    func selectPage(_ page: IslandPage) {
        if page.isUtility { openUtility(page); return }
        // Only explicit navigation changes the page remembered across openings.
        let startup = IslandStartPage(rawValue: page.rawValue) ?? .home
        if preferences.startupPage != startup { preferences.startupPage = startup }
        self.page = page
    }

    func openUtility(_ page: IslandPage, returningTo pageOverride: IslandPage? = nil) {
        guard page.isUtility else { return }
        if let pageOverride, !pageOverride.isUtility {
            pageBeforeUtility = pageOverride
        } else if !self.page.isUtility {
            pageBeforeUtility = self.page
        }
        self.page = page
    }

    func closeUtility() {
        if page.isUtility { page = pageBeforeUtility }
    }
    @Published var shortcutStatus = ""
    @Published var recordingShortcut = false { didSet { layoutChanged?() } }
    @Published var interactionHeld = false
    @Published var panelPopoverOpen = false
    @Published var availableScreenWidth: CGFloat = 1400
    @Published var expanded = false
    @Published var pinned = false
    @Published var notchWidth: CGFloat = 0
    @Published var menuBarHeight: CGFloat = 0
    @Published var mediaIsPlaying = false
    @Published var activityOptions = IslandActivityOptions() {
        didSet {
            if let data = try? JSONEncoder().encode(activityOptions) {
                defaults.set(data, forKey: "ada.activityOptions")
            }
            activities.configure(activityOptions)
        }
    }
    let activities = IslandActivityStore()
    var activityVisible: Bool { activities.notice != nil || (!mediaIsPlaying && activities.deadline != nil) }
    @Published var pointerInside = false
    @Published var panelIsKey = false
    @Published var lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
    @Published var batteryPercent: Int?
    @Published var charging = false
    @Published var pluggedIn = false
    let focus: FocusClockModel
    var clock: FocusClock { focus.clock }
    var now: Date { focus.now }
    var isBreak: Bool { focus.isBreak }
    var soundEnabled: Bool {
        get { focus.soundEnabled }
        set { focus.soundEnabled = newValue; focus.save() }
    }
    var layoutChanged: (() -> Void)?
    var completed: (() -> Void)?
    private let batteryEvents = BatteryEventMonitor()
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard, startServices: Bool = true) {
        self.defaults = defaults
        preferences = IslandPreferences.load(defaults: defaults)
        focus = FocusClockModel(defaults: defaults)
        if let data = defaults.data(forKey: "ada.activityOptions"),
           let saved = try? JSONDecoder().decode(IslandActivityOptions.self, from: data) {
            activityOptions = saved
        }
        if startServices { activities.configure(activityOptions) }
        focus.stateChanged = { [weak self] in
            self?.objectWillChange.send()
            self?.layoutChanged?()
        }
        focus.completed = { [weak self] in self?.completed?() }
        if startServices { batteryEvents.start { [weak self] in self?.refreshBattery() } }
    }

    var width: CGFloat {
        guard expanded else { return closedWidth }
        let preferredWidth = page == .player ? 512 : preferences.expandedWidth
        return min(availableScreenWidth - 40, max(preferredWidth, closedWidth))
    }
    var flushToTop: Bool { attached && (expanded || (mediaIsPlaying && !activityVisible)) }
    var menuClearance: CGFloat { flushToTop ? menuBarHeight : 0 }
    var playerHeaderBesideCamera: Bool {
        attached && page == .player && menuClearance >= 26 && (width - notchWidth) / 2 >= 130
    }
    var contentTopInset: CGFloat { playerHeaderBesideCamera ? 0 : menuClearance }
    var height: CGFloat {
        guard expanded else { return closedHeight }
        if page == .player { return contentTopInset + topReserve + (preferences.showCalendarEvents ? 206 : 116) }
        return contentTopInset + topReserve + max(preferences.contentHeight, page.minimumHeight)
    }
    var remaining: TimeInterval { clock.remaining(at: now) }
    var timeLabel: String {
        let seconds = Int(ceil(remaining))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
    var progress: Double { clock.progress(at: now) }
    var selectedMinutes: Int { Int(clock.duration / 60) }
    var batterySymbol: String {
        if charging { return "battery.100percent.bolt" }
        guard let batteryPercent else { return "battery.0percent" }
        switch batteryPercent {
        case 0..<13: return "battery.0percent"
        case 13..<38: return "battery.25percent"
        case 38..<63: return "battery.50percent"
        case 63..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
    var batteryColor: Color {
        if charging { return .mint }
        if let batteryPercent, batteryPercent <= 20 { return .orange }
        return .white.opacity(0.85)
    }
    var batteryDescription: String {
        guard batteryPercent != nil else { return L10n.string("Pil bilgisi yok") }
        if charging { return L10n.string("Şarj oluyor") }
        if pluggedIn { return L10n.string("Güç adaptörüne bağlı") }
        return L10n.string("Pil gücüyle çalışıyor")
    }
    var focusStatus: String {
        if clock.completed { return L10n.string("Güzel iş. Bir mola ver.") }
        if clock.isRunning { return L10n.string("Şimdi tek bir şeye odaklan.") }
        if remaining < clock.duration { return L10n.string("Hazır olduğunda devam et.") }
        return L10n.string("Kendine biraz alan aç.")
    }

    func toggleTimer() {
        focus.toggle(pomodoro: preferences.pomodoro, breakMinutes: preferences.breakMinutes,
                     defaultMinutes: preferences.defaultMinutes)
    }
    func selectMinutes(_ minutes: Int) { focus.selectMinutes(minutes) }
    func reset() { focus.reset() }
    func adjustMinutes(_ minutes: Int) { focus.adjustMinutes(minutes) }
    func save() { focus.save() }
    func shutdown() { focus.stop(); batteryEvents.stop(); activities.stop() }
    func refreshBattery() {
        defer { activities.updateBattery(percent: batteryPercent, pluggedIn: pluggedIn) }
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            batteryPercent = nil
            return
        }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
            batteryPercent = min(100, max(0, Int((Double(current) / Double(maximum) * 100).rounded())))
            charging = description[kIOPSIsChargingKey] as? Bool ?? false
            pluggedIn = description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            return
        }
        batteryPercent = nil
        charging = false
        pluggedIn = false
    }
}
