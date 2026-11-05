import Foundation

public enum PointerTrackingMode: Equatable, Sendable {
    case disabled, eventsOnly, active
}
public enum PointerTrackingPolicy {
    public static func mode(visible: Bool, hoverEnabled: Bool, expanded: Bool) -> PointerTrackingMode {
        guard visible && hoverEnabled else { return .disabled }
        return expanded ? .active : .eventsOnly
    }
    public static func timerInterval(mode: PointerTrackingMode, globalMonitorAvailable: Bool) -> TimeInterval? {
        switch mode {
        case .disabled: return nil
        case .eventsOnly: return globalMonitorAvailable ? nil : 0.2
        case .active: return 0.06
        }
    }
}
