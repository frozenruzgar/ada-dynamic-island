import AdaCore
import AppKit

@MainActor
final class HoverController {
    let monitor = IslandPointerMonitor()
    var holdOpenUntil = Date.distantPast
    var keyboardHeld = false
    var suppressUntilExit = false
    private var openingTask: Task<Void, Never>?
    private var collapseTask: DispatchWorkItem?

    func checkPointer(blocked: Bool, inside: Bool, expanded: Bool, hoverEnabled: Bool,
                      canExpand: @escaping () -> Bool, expand: @escaping () -> Void,
                      scheduleCollapse: () -> Void) {
        guard !blocked else { cancelOpening(); cancelCollapse(); return }
        if inside {
            cancelCollapse()
            if expanded && keyboardHeld {
                holdOpenUntil = .distantPast
                keyboardHeld = false
            }
            if !expanded && hoverEnabled && !suppressUntilExit {
                scheduleOpening(canExpand: canExpand, expand: expand)
            } else { cancelOpening() }
        } else {
            cancelOpening()
            suppressUntilExit = false
            scheduleCollapse()
        }
    }

    private func scheduleOpening(canExpand: @escaping () -> Bool, expand: @escaping () -> Void) {
        guard openingTask == nil else { return }
        openingTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(80)) }
            catch { return }
            guard let self else { return }
            self.openingTask = nil
            if !self.suppressUntilExit && canExpand() { expand() }
        }
    }

    func cancelOpening() {
        openingTask?.cancel()
        openingTask = nil
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
    func stop() { cancelOpening(); cancelCollapse(); monitor.stop() }
}
