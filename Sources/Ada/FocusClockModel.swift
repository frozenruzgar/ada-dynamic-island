import AppKit
import Combine
import AdaCore

/// Tick publications belong only to the two clock views. Structural changes
/// notify the island once; stopped clocks own no repeating timer.
@MainActor
final class FocusClockModel: ObservableObject {
    @Published private(set) var clock: FocusClock
    @Published private(set) var now: Date
    @Published private(set) var isBreak: Bool
    @Published var soundEnabled: Bool
    var stateChanged: (() -> Void)?
    var completed: (() -> Void)?
    private let defaults: UserDefaults
    private var ticker: Timer?
    var isTicking: Bool { ticker != nil }

    init(defaults: UserDefaults = .standard, now: Date = Date()) {
        self.defaults = defaults
        self.now = now
        isBreak = defaults.bool(forKey: "isBreak")
        soundEnabled = defaults.object(forKey: "soundEnabled") as? Bool ?? true
        if let data = defaults.data(forKey: "focusClock"),
           let saved = try? JSONDecoder().decode(FocusClock.self, from: data) { clock = saved }
        else { clock = FocusClock() }
        if clock.finishIfNeeded(at: now) { persist() }
        configureTicker()
    }
    var remaining: TimeInterval { clock.remaining(at: now) }
    var timeLabel: String {
        let seconds = Int(ceil(remaining))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
    var progress: Double { clock.progress(at: now) }
    func toggle(pomodoro: Bool, breakMinutes: Int, defaultMinutes: Int, at date: Date = Date()) {
        if clock.completed {
            if pomodoro && !isBreak { isBreak = true; clock.reset(minutes: breakMinutes) }
            else { isBreak = false; clock.reset(minutes: defaultMinutes) }
        }
        now = date
        if clock.isRunning { clock.pause(at: date) } else { clock.start(at: date) }
        save()
    }
    func selectMinutes(_ minutes: Int) {
        now = Date(); isBreak = false; clock.reset(minutes: minutes); save()
    }
    func reset() { clock.reset(); now = Date(); save() }
    func adjustMinutes(_ minutes: Int) {
        now = Date(); clock.adjust(by: Double(minutes) * 60, at: now); save()
    }
    func save() { persist(); configureTicker(); stateChanged?() }
    func stop() { ticker?.invalidate(); ticker = nil }
    func tick(at date: Date = Date()) {
        guard clock.isRunning else { return }
        now = date
        if clock.finishIfNeeded(at: date) {
            save()
            if soundEnabled { NSSound(named: "Glass")?.play() }
            completed?()
        }
    }
    private func persist() {
        if let data = try? JSONEncoder().encode(clock) { defaults.set(data, forKey: "focusClock") }
        defaults.set(soundEnabled, forKey: "soundEnabled")
        defaults.set(isBreak, forKey: "isBreak")
    }
    private func configureTicker() {
        guard clock.isRunning else { stop(); return }
        guard ticker == nil else { return }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.1
        ticker = timer
        RunLoop.main.add(timer, forMode: .common)
    }
}
