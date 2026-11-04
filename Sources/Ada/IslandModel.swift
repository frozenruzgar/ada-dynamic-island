import AppKit
import SwiftUI
import IOKit.ps
import AdaCore

@MainActor
final class IslandModel: ObservableObject {
    @Published var preferences = IslandPreferences.load() {
        didSet {
            if let data = try? JSONEncoder().encode(preferences) {
                UserDefaults.standard.set(data, forKey: "workspacePreferencesV3")
            }
            layoutChanged?()
        }
    }
    @Published var page: IslandPage = .home {
        didSet { if page != oldValue { layoutChanged?() } }
    }

    func selectPage(_ page: IslandPage) {
        // Only explicit navigation changes the page remembered across openings.
        if preferences.startupPage != page.rawValue { preferences.startupPage = page.rawValue }
        self.page = page
    }
    @Published var shortcutStatus = ""
    @Published var interactionHeld = false
    @Published var isBreak = UserDefaults.standard.bool(forKey: "isBreak")
    @Published var availableScreenWidth: CGFloat = 1400
    @Published var expanded = false
    @Published var pinned = false
    @Published var notchWidth: CGFloat = 0
    @Published var menuBarHeight: CGFloat = 0
    @Published var mediaIsPlaying = false
    @Published var batteryPercent: Int?
    @Published var charging = false
    @Published var pluggedIn = false
    @Published var clock: FocusClock
    @Published var now = Date()
    @Published var soundEnabled = UserDefaults.standard.object(forKey: "soundEnabled") as? Bool ?? true
    var layoutChanged: (() -> Void)?
    var completed: (() -> Void)?
    private var ticker: Timer?
    private var batteryTicker: Timer?

    init() {
        if let data = UserDefaults.standard.data(forKey: "focusClock"),
           let saved = try? JSONDecoder().decode(FocusClock.self, from: data) {
            clock = saved
        } else { clock = FocusClock() }
        _ = clock.finishIfNeeded()
        refreshBattery()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        batteryTicker = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshBattery() }
        }
        if let ticker { RunLoop.main.add(ticker, forMode: .common) }
        if let batteryTicker { RunLoop.main.add(batteryTicker, forMode: .common) }
    }

    var width: CGFloat { expanded ? min(availableScreenWidth - 40, max(preferences.expandedWidth, closedWidth)) : closedWidth }
    var flushToTop: Bool { attached && (expanded || mediaIsPlaying) }
    var menuClearance: CGFloat { flushToTop ? menuBarHeight : 0 }
    var height: CGFloat {
        guard expanded else { return closedHeight }
        return menuClearance + topReserve + max(preferences.contentHeight, page.minimumHeight)
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
        guard batteryPercent != nil else { return "Pil bilgisi yok" }
        if charging { return "Şarj oluyor" }
        if pluggedIn { return "Güç adaptörüne bağlı" }
        return "Pil gücüyle çalışıyor"
    }
    var focusStatus: String {
        if clock.completed { return "Güzel iş. Bir mola ver." }
        if clock.isRunning { return "Şimdi tek bir şeye odaklan." }
        if remaining < clock.duration { return "Hazır olduğunda devam et." }
        return "Kendine biraz alan aç."
    }

    func toggleTimer() {
        if clock.completed {
            if preferences.pomodoro && !isBreak {
                isBreak = true
                clock.reset(minutes: preferences.breakMinutes)
            } else {
                isBreak = false
                clock.reset(minutes: preferences.defaultMinutes)
            }
        }
        now = Date()
        if clock.isRunning { clock.pause(at: now) } else { clock.start(at: now) }
        save()
    }
    func selectMinutes(_ minutes: Int) {
        now = Date()
        isBreak = false
        clock.reset(minutes: minutes)
        save()
    }
    func reset() { clock.reset(); now = Date(); save() }
    func adjustMinutes(_ minutes: Int) {
        clock.adjust(by: TimeInterval(minutes * 60), at: Date())
        now = Date()
        save()
    }
    func save() {
        if let data = try? JSONEncoder().encode(clock) {
            UserDefaults.standard.set(data, forKey: "focusClock")
        }
        UserDefaults.standard.set(soundEnabled, forKey: "soundEnabled")
        UserDefaults.standard.set(isBreak, forKey: "isBreak")
        layoutChanged?()
    }
    private func tick() {
        guard clock.isRunning else { return }
        now = Date()
        if clock.finishIfNeeded(at: now) {
            save()
            if soundEnabled { NSSound(named: "Glass")?.play() }
            completed?()
        }
    }
    func refreshBattery() {
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
