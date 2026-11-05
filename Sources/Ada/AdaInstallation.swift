import Foundation

enum AdaInstallation {
    static let identifier = "io.github.frozenruzgar.ada"
    static let legacyIdentifier = "dev.ada.island"
    static let migrationKey = "ada.installationMigration.v1"

    static var supportParent: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    static var storage: URL {
        supportParent.appendingPathComponent(identifier, isDirectory: true)
    }

    private static let transferredKeys: Set<String> = [
        "workspacePreferencesV3", "dashboardTilesV1", "workspaceAppShortcutsV2",
        "workspaceShortcuts", "workspaceNote", "workspaceTasks", "focusClock", "soundEnabled",
        "isBreak", "shelfMaximumBytes", "shelfRetentionDays", "ada.prompter.v1",
        "ada.cloud.favoriteFolders.v1", "assistantProvider", "welcomePresentedV1"
    ]

    /// The caller owns the shared legacy instance lock while copying. The old
    /// installation remains a rollback source. An interrupted copy is retryable.
    static func migrate(defaults: UserDefaults, legacyValues: [String: Any], parent: URL) throws {
        guard !defaults.bool(forKey: migrationKey) else { return }
        let manager = FileManager.default
        let source = parent.appendingPathComponent(legacyIdentifier, isDirectory: true)
        let target = parent.appendingPathComponent(identifier, isDirectory: true)
        try manager.createDirectory(at: target, withIntermediateDirectories: true)

        for folder in ["Notes", "Shelf"] {
            let old = source.appendingPathComponent(folder, isDirectory: true)
            let new = target.appendingPathComponent(folder, isDirectory: true)
            guard manager.fileExists(atPath: old.path), !manager.fileExists(atPath: new.path) else { continue }
            let staging = target.appendingPathComponent(".migration-\(folder)", isDirectory: true)
            if manager.fileExists(atPath: staging.path) { try manager.removeItem(at: staging) }
            do {
                try manager.copyItem(at: old, to: staging)
                try manager.moveItem(at: staging, to: new)
            } catch {
                try? manager.removeItem(at: staging)
                throw error
            }
        }

        for (key, value) in legacyValues where transferredKeys.contains(key) && defaults.object(forKey: key) == nil {
            defaults.set(value, forKey: key)
        }
        defaults.set(true, forKey: migrationKey)
    }
}
