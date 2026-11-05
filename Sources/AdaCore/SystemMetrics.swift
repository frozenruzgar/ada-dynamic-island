import Foundation

/// Successive aggregate kernel CPU tick counters, not the system load average.
public struct CPUTickSample: Equatable, Sendable {
    public let user: UInt32
    public let system: UInt32
    public let idle: UInt32
    public let nice: UInt32

    public init(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32) {
        self.user = user; self.system = system; self.idle = idle; self.nice = nice
    }

    /// UInt32 subtraction deliberately wraps when a kernel tick counter wraps.
    public static func utilization(previous: Self, current: Self) -> Double? {
        let user = UInt64(current.user &- previous.user)
        let system = UInt64(current.system &- previous.system)
        let idle = UInt64(current.idle &- previous.idle)
        let nice = UInt64(current.nice &- previous.nice)
        let total = user + system + idle + nice
        guard total > 0 else { return nil }
        return min(1, max(0, Double(user + system + nice) / Double(total)))
    }
}

public struct MemorySnapshot: Equatable, Sendable {
    public let total: UInt64
    public let used: UInt64
    public let compressed: UInt64
    public let wired: UInt64
    public var fraction: Double { total > 0 ? min(1, Double(used) / Double(total)) : 0 }

    /// Anonymous resident pages minus purgeable pages, plus wired and physically
    /// occupied compressor pages. Uncompressed logical pages in the compressor
    /// are not added; compressed memory is already a subset of `used`.
    public static func calculate(total: UInt64, pageSize: UInt64, anonymousPages: UInt64,
                          purgeablePages: UInt64, wiredPages: UInt64, compressorPages: UInt64) -> Self {
        let anonymous = anonymousPages > purgeablePages ? anonymousPages - purgeablePages : 0
        let compressed = compressorPages * pageSize
        let wired = wiredPages * pageSize
        let used = min(total, anonymous * pageSize + wired + compressed)
        return Self(total: total, used: used, compressed: min(total, compressed), wired: min(total, wired))
    }
}
