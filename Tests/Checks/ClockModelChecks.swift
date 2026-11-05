@testable import Ada
@testable import AdaCore
import Foundation
enum ClockModelChecks {
    @MainActor static func main() {
        let suite = "Ada.ClockChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let date = Date(timeIntervalSince1970: 1_000)
        let model = FocusClockModel(defaults: defaults, now: date)
        model.soundEnabled = false
        var changes = 0, completions = 0
        model.stateChanged = { changes += 1 }; model.completed = { completions += 1 }
        precondition(!model.isTicking)
        model.toggle(pomodoro: true, breakMinutes: 5, defaultMinutes: 25, at: date)
        precondition(model.isTicking && changes == 1)
        model.tick(at: date.addingTimeInterval(10))
        precondition(changes == 1 && model.timeLabel == "24:50")
        model.tick(at: date.addingTimeInterval(1_500))
        model.tick(at: date.addingTimeInterval(1_600))
        precondition(changes == 2 && completions == 1 && !model.isTicking)
        let restored = FocusClockModel(defaults: defaults)
        precondition(restored.clock.completed && !restored.isTicking)
        model.toggle(pomodoro: true, breakMinutes: 5, defaultMinutes: 25)
        precondition(model.isBreak && model.clock.duration == 300 && model.isTicking)
        model.toggle(pomodoro: true, breakMinutes: 5, defaultMinutes: 25)
        precondition(!model.isTicking)
        model.stop(); restored.stop()
        let island = IslandModel(defaults: defaults, startServices: false)
        var structuralChanges = 0
        island.layoutChanged = { structuralChanges += 1 }
        island.soundEnabled = true
        precondition(defaults.bool(forKey: "soundEnabled") && structuralChanges == 1)
        island.soundEnabled = false
        precondition(!defaults.bool(forKey: "soundEnabled") && structuralChanges == 2)
        island.shutdown()
        print("PASS: clock ticks isolated from structural callbacks, idle/pause timers stopped, completion once and persisted break state")
    }
}
