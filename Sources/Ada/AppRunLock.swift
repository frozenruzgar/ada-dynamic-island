import Darwin
import Foundation

/// Launch Services can omit a directly launched process. This lock serializes
/// access to Ada's local stores independently of how the process was launched.
final class AppRunLock {
    enum Attempt {
        case acquired(AppRunLock)
        case occupied(pid_t?)
        case unavailable(Int32)
    }

    private let descriptor: Int32
    private init(descriptor: Int32) { self.descriptor = descriptor }

    static func attempt(at path: String) -> Attempt {
        let fd = open(path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { return .unavailable(errno) }

        if flock(fd, LOCK_EX | LOCK_NB) == 0 {
            let pid = Array(String(getpid()).utf8)
            if ftruncate(fd, 0) == 0 {
                _ = pid.withUnsafeBytes { pwrite(fd, $0.baseAddress, $0.count, 0) }
            }
            return .acquired(AppRunLock(descriptor: fd))
        }

        let failure = errno
        defer { close(fd) }
        guard failure == EWOULDBLOCK else { return .unavailable(failure) }
        var bytes = [UInt8](repeating: 0, count: 32)
        let count = bytes.withUnsafeMutableBytes { pread(fd, $0.baseAddress, $0.count, 0) }
        let owner = count > 0 ? pid_t(String(decoding: bytes.prefix(count), as: UTF8.self)) : nil
        return .occupied(owner)
    }

    // Keep the lock file in place so contenders always lock the same inode.
    deinit { close(descriptor) }
}
