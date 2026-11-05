import Foundation

/// Uses a deadline rather than decrementing ticks, so sleep and delayed callbacks do not lose time.
public struct FocusClock: Codable, Equatable, Sendable {
    public private(set) var duration: TimeInterval
    public private(set) var pausedRemaining: TimeInterval
    public private(set) var deadline: Date?
    public private(set) var completed = false

    public init(minutes: Int = 25) {
        duration = TimeInterval(max(1, minutes) * 60)
        pausedRemaining = duration
    }

    public var isRunning: Bool { deadline != nil }
    public func remaining(at date: Date = Date()) -> TimeInterval {
        max(0, deadline.map { $0.timeIntervalSince(date) } ?? pausedRemaining)
    }
    public func progress(at date: Date = Date()) -> Double {
        min(1, max(0, 1 - remaining(at: date) / duration))
    }
    public mutating func start(at date: Date = Date()) {
        guard deadline == nil else { return }
        if completed || pausedRemaining <= 0 { pausedRemaining = duration }
        completed = false
        deadline = date.addingTimeInterval(pausedRemaining)
    }
    public mutating func pause(at date: Date = Date()) {
        guard isRunning else { return }
        if finishIfNeeded(at: date) { return }
        pausedRemaining = remaining(at: date)
        deadline = nil
    }
    public mutating func reset(minutes: Int? = nil) {
        if let minutes { duration = TimeInterval(max(1, minutes) * 60) }
        pausedRemaining = duration
        deadline = nil
        completed = false
    }
    public mutating func adjust(by seconds: TimeInterval, at date: Date = Date()) {
        let oldRemaining = remaining(at: date)
        let newRemaining = max(1, oldRemaining + seconds)
        duration = max(newRemaining, duration + (newRemaining - oldRemaining))
        if isRunning { deadline = date.addingTimeInterval(newRemaining) }
        else { pausedRemaining = newRemaining }
        completed = false
    }
    @discardableResult
    public mutating func finishIfNeeded(at date: Date = Date()) -> Bool {
        guard let deadline, date >= deadline else { return false }
        self.deadline = nil
        pausedRemaining = 0
        completed = true
        return true
    }
}
