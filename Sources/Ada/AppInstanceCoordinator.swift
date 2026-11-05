import AppKit
import AdaCore

@MainActor
enum AppInstanceCoordinator {
    static var activationName: Notification.Name {
        Notification.Name((Bundle.main.bundleIdentifier ?? AdaInstallation.identifier) + ".activate")
    }

    static func prepare() -> AppRunLock? {
        let identifier = Bundle.main.bundleIdentifier ?? AdaInstallation.identifier
        guard reconcileRunningApps(identifier: identifier) else { return nil }

        let support = AdaInstallation.supportParent.appendingPathComponent(AdaInstallation.legacyIdentifier, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        } catch {
            NSLog("Ada instance lock directory: %@", error.localizedDescription)
            return nil
        }

        switch AppRunLock.attempt(at: support.appendingPathComponent("instance.lock").path) {
        case .acquired(let lock):
            return lock
        case .occupied(let pid):
            if let pid, pid > 0 {
                let running = NSRunningApplication(processIdentifier: pid)
                let peer = running?.bundleIdentifier
                if peer == identifier || peer == AdaInstallation.legacyIdentifier {
                    notify(pid: pid, identifier: peer ?? identifier)
                    _ = running?.activate(options: [])
                } else {
                    notify(pid: pid, identifier: identifier)
                    notify(pid: pid, identifier: AdaInstallation.legacyIdentifier)
                }
            }
            return nil
        case .unavailable(let error):
            NSLog("Ada instance lock could not be acquired (errno %d)", error)
            return nil
        }
    }

    private static func reconcileRunningApps(identifier: String) -> Bool {
        let currentApp = NSRunningApplication.current
        let current = instance(currentApp, bundle: Bundle.main)
        let identities = Set([identifier, AdaInstallation.legacyIdentifier])
        let others = identities.flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0) }
            .filter { $0.processIdentifier != current.pid && !$0.isTerminated }
        let peers = others.map { instance($0, bundle: $0.bundleURL.flatMap(Bundle.init(url:))) }
        let winner = ApplicationLaunchPolicy.winner(current: current, others: peers)
        if winner.pid != current.pid, let app = others.first(where: { $0.processIdentifier == winner.pid }) {
            activate(app, identifier: identifier)
            return false
        }
        let older = zip(others, peers).filter { $0.1.version < current.version }.map(\.0)
        for app in older { _ = app.terminate() }
        // Startup-only bounded wait. Pump AppKit's run loop so isTerminated can
        // update; never force-quit an instance whose user cancelled termination.
        let deadline = Date().addingTimeInterval(3)
        while older.contains(where: { !$0.isTerminated }) && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        if let remaining = older.first(where: { !$0.isTerminated }) {
            activate(remaining, identifier: identifier)
            return false
        }
        return true
    }

    private static func instance(_ app: NSRunningApplication, bundle: Bundle?) -> ApplicationInstance {
        let release = bundle?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let build = bundle?.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return ApplicationInstance(pid: app.processIdentifier, version: ApplicationVersion(release, build: build),
            launchedAt: app.launchDate?.timeIntervalSinceReferenceDate ?? 0)
    }
    private static func activate(_ app: NSRunningApplication, identifier: String) {
        notify(pid: app.processIdentifier, identifier: app.bundleIdentifier ?? identifier)
        _ = app.activate(options: [])
    }

    private static func notify(pid: pid_t, identifier: String) {
        let action = CommandLine.arguments.contains("--settings") ? "settings" : "activate"
        DistributedNotificationCenter.default().postNotificationName(Notification.Name(identifier + ".activate"), object: identifier,
            userInfo: ["targetPID": Int(pid), "action": action], deliverImmediately: true)
    }
}
