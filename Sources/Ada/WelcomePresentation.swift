import Foundation

enum WelcomePresentation {
    static let presentedKey = "welcomePresentedV1"

    private static let existingInstallKeys = [
        "workspacePreferencesV3", "dashboardTilesV1", "workspaceAppShortcutsV2",
        "workspaceShortcuts", "workspaceNote", "workspaceTasks", "focusClock",
        "shelfRetentionDays", "ada.prompter.v1"
    ]

    // Evaluate before creating stores, which seed defaults on the first launch.
    static func shouldShowOnLaunch(defaults: UserDefaults, storage: URL) -> Bool {
        guard !defaults.bool(forKey: presentedKey),
              !existingInstallKeys.contains(where: { defaults.object(forKey: $0) != nil }) else {
            return false
        }

        return !["Notes/current.md", "Shelf/items.json"].contains {
            FileManager.default.fileExists(atPath: storage.appendingPathComponent($0).path)
        }
    }

    static func recordPresentation(defaults: UserDefaults) {
        defaults.set(true, forKey: presentedKey)
    }
}
