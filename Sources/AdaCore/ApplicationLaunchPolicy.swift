import Foundation

public struct ApplicationVersion: Equatable, Comparable, Sendable {
    private let release: [Int]
    private let build: [Int]

    public init(_ release: String, build: String) {
        self.release = Self.components(release)
        self.build = Self.components(build)
    }
    private static func components(_ text: String) -> [Int] {
        let pieces = text.split(separator: ".", omittingEmptySubsequences: false)
        let numbers = pieces.compactMap { Int($0) }
        guard numbers.count == pieces.count, !numbers.isEmpty, numbers.allSatisfy({ $0 >= 0 }) else { return [0] }
        var result = numbers
        while result.count > 1 && result.last == 0 { result.removeLast() }
        return result
    }
    private static func compare(_ lhs: [Int], _ rhs: [Int]) -> Int {
        for index in 0..<max(lhs.count, rhs.count) {
            let left = index < lhs.count ? lhs[index] : 0
            let right = index < rhs.count ? rhs[index] : 0
            if left < right { return -1 }
            if left > right { return 1 }
        }
        return 0
    }
    public static func < (lhs: Self, rhs: Self) -> Bool {
        let release = compare(lhs.release, rhs.release)
        return release == 0 ? compare(lhs.build, rhs.build) < 0 : release < 0
    }
}

public struct ApplicationInstance: Equatable, Sendable {
    public let pid: Int32
    public let version: ApplicationVersion
    public let launchedAt: TimeInterval
    public init(pid: Int32, version: ApplicationVersion, launchedAt: TimeInterval) {
        self.pid = pid; self.version = version; self.launchedAt = launchedAt
    }
}

public enum ApplicationLaunchPolicy {
    /// Newer versions win. Equal versions keep the earlier launch; PID is only
    /// a deterministic tie-breaker, so concurrent starts cannot both withdraw.
    public static func winner(current: ApplicationInstance, others: [ApplicationInstance]) -> ApplicationInstance {
        ([current] + others).sorted { lhs, rhs in
            if lhs.version != rhs.version { return lhs.version > rhs.version }
            if lhs.launchedAt != rhs.launchedAt { return lhs.launchedAt < rhs.launchedAt }
            return lhs.pid < rhs.pid
        }[0]
    }
}
