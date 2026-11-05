@testable import Ada
import Foundation

enum WelcomeChecks {
    static func main() throws {
        let suite = "Ada.WelcomeChecks.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let storage = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: storage) }

        defaults.set("tr", forKey: "UnrelatedTestSetting")
        precondition(WelcomePresentation.shouldShowOnLaunch(defaults: defaults, storage: storage))
        WelcomePresentation.recordPresentation(defaults: defaults)
        precondition(!WelcomePresentation.shouldShowOnLaunch(defaults: defaults, storage: storage))
        defaults.removeObject(forKey: WelcomePresentation.presentedKey)

        defaults.set(Data("legacy".utf8), forKey: "workspacePreferencesV3")
        precondition(!WelcomePresentation.shouldShowOnLaunch(defaults: defaults, storage: storage))
        defaults.removeObject(forKey: "workspacePreferencesV3")
        defaults.set(0, forKey: "shelfRetentionDays")
        precondition(!WelcomePresentation.shouldShowOnLaunch(defaults: defaults, storage: storage))
        defaults.removeObject(forKey: "shelfRetentionDays")

        let notes = storage.appendingPathComponent("Notes")
        try FileManager.default.createDirectory(at: notes, withIntermediateDirectories: true)
        try Data().write(to: notes.appendingPathComponent("current.md"))
        precondition(!WelcomePresentation.shouldShowOnLaunch(defaults: defaults, storage: storage))
        let released = Data(#"[{"tag_name":"v0.12.3"}]"#.utf8)
        let available = try AdaReleaseCheck.availableVersion(current: "0.12.0", response: released)
        let upToDate = try AdaReleaseCheck.availableVersion(current: "0.12.3", response: released)
        let invalid = try AdaReleaseCheck.latestVersion(from: Data(#"[{"tag_name":"v0.12.invalid"}]"#.utf8))
        precondition(available == "0.12.3" && upToDate == nil && invalid == nil)
        print("PASS: welcome appears once for fresh installs and skips existing preferences and notes")
    }
}
