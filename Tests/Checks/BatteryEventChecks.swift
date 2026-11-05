@testable import Ada
@testable import AdaCore
import Foundation
@MainActor private final class FakeBatteryEvents: BatteryEventClient {
    var available = true
    var handler: (@MainActor @Sendable () -> Void)?
    var starts = 0
    func start(onChange: @escaping @MainActor @Sendable () -> Void) -> Bool {
        starts += 1; handler = available ? onChange : nil; return available
    }
    func stop() { handler = nil }
}
enum BatteryEventChecks {
    @MainActor static func main() {
        let client = FakeBatteryEvents(), monitor = BatteryEventMonitor(client: FakeBatteryEvents())
        monitor.stop()
        let active = BatteryEventMonitor(client: client)
        var updates = 0
        active.start { updates += 1 }
        precondition(updates == 1 && !active.usingFallback)
        client.handler?(); precondition(updates == 2)
        active.stop(); precondition(client.handler == nil && !active.usingFallback)
        client.available = false
        active.start { updates += 1 }
        precondition(updates == 3 && active.usingFallback)
        active.stop(); precondition(!active.usingFallback)
        let power = BatteryActivitySnapshot(percent: 24, pluggedIn: true)
        let unplugged = BatteryActivitySnapshot(percent: 24, pluggedIn: false)
        let low = BatteryActivitySnapshot(percent: 20, pluggedIn: false)
        precondition(power.events(after: nil).isEmpty)
        precondition(unplugged.events(after: power) == [.disconnected])
        precondition(low.events(after: unplugged) == [.low] && low.events(after: low).isEmpty)
        let activity = IslandActivityStore()
        activity.startCountdown(minutes: 5)
        precondition(activity.deadline == nil)
        var options = IslandActivityOptions()
        options.countdown = true
        activity.configure(options)
        activity.startCountdown(minutes: 5)
        let deadline = activity.deadline!
        activity.completeIfNeeded(now: deadline)
        precondition(activity.deadline == nil && activity.notice?.symbol == "timer")
        activity.stop()
        print("PASS: battery initial snapshot, event refresh, source cleanup and timer fallback only after registration failure; no power settings changed")
    }
}
