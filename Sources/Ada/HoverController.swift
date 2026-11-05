import AdaCore
import AppKit

@MainActor
final class HoverController {
    let monitor = IslandPointerMonitor()
    var holdOpenUntil = Date.distantPast
    var keyboardHeld = false
    var suppressUntilExit = false
    private var collapseTask: DispatchWorkItem?
    func checkPointer(blocked: Bool, inside: Bool, expanded: Bool, hoverEnabled: Bool,
                      expand: () -> Void, scheduleCollapse: () -> Void) {
        guard !blocked else { cancelCollapse(); return }
        if inside {
            cancelCollapse()
            if expanded {
                holdOpenUntil = .distantPast
                keyboardHeld = false
            }
            if !expanded && hoverEnabled && !suppressUntilExit { expand() }
        } else { suppressUntilExit = false; scheduleCollapse() }
    }
    func cancelCollapse() { collapseTask?.cancel(); collapseTask = nil }
    func scheduleCollapse(delay: TimeInterval, canCollapse: @escaping () -> Bool, collapse: @escaping () -> Void) {
        guard collapseTask == nil, canCollapse() else { return }
        let task = DispatchWorkItem { [weak self] in
            self?.collapseTask = nil
            if canCollapse() { collapse() }
        }
        collapseTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: task)
    }
    func stop() { cancelCollapse(); monitor.stop() }
}
