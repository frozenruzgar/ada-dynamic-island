import AppKit
import AdaCore

/// Mouse-only monitors do not request keyboard/Accessibility access. A timer is
/// needed only while open, or as a slower fallback if global monitoring fails.
@MainActor
final class IslandPointerMonitor {
    var onPointerUpdate: (() -> Void)?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var timer: Timer?
    private var mode: PointerTrackingMode = .disabled

    func configure(mode: PointerTrackingMode) {
        guard self.mode != mode else { return }
        self.mode = mode
        guard mode != .disabled else { stop(); return }
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        if globalMonitor == nil {
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] _ in
                MainActor.assumeIsolated { self?.onPointerUpdate?() }
            }
        }
        if localMonitor == nil {
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
                MainActor.assumeIsolated { self?.onPointerUpdate?() }
                return event
            }
        }
        timer?.invalidate()
        timer = nil
        if let interval = PointerTrackingPolicy.timerInterval(mode: mode, globalMonitorAvailable: globalMonitor != nil) {
            let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.onPointerUpdate?() }
            }
            timer.tolerance = interval * 0.2
            self.timer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
    }
    func stop() {
        timer?.invalidate(); timer = nil
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil; localMonitor = nil
        mode = .disabled
    }
}
