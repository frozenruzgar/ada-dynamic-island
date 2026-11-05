@testable import Ada
import Foundation

enum InstallationChecks {
    static func main() throws {
        let token = "AdaMigration-\(UUID())"
        let defaults = UserDefaults(suiteName: token)!
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(token)
        defer {
            defaults.removePersistentDomain(forName: token)
            try? FileManager.default.removeItem(at: root)
        }
        let old = root.appendingPathComponent(AdaInstallation.legacyIdentifier)
        let new = root.appendingPathComponent(AdaInstallation.identifier)
        let bytes = Data("fixture".utf8)
        for path in ["Notes/current.md", "Shelf/items.json"] {
            let source = old.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
            try bytes.write(to: source)
        }
        defaults.set("Claude", forKey: "assistantProvider")
        try AdaInstallation.migrate(defaults: defaults, legacyValues: [
            "focusClock": bytes, "assistantProvider": "ChatGPT", "unrelated": "skip"
        ], parent: root)
        for path in ["Notes/current.md", "Shelf/items.json"] {
            let source = try Data(contentsOf: old.appendingPathComponent(path))
            let copy = try Data(contentsOf: new.appendingPathComponent(path))
            precondition(source == bytes && copy == bytes)
        }
        precondition(defaults.data(forKey: "focusClock") == bytes)
        precondition(defaults.string(forKey: "assistantProvider") == "Claude")
        precondition(defaults.object(forKey: "unrelated") == nil)
        try AdaInstallation.migrate(defaults: defaults, legacyValues: ["workspaceNote": "duplicate"], parent: root)
        precondition(defaults.object(forKey: "workspaceNote") == nil)
        print("PASS: bundle migration copies notes, shelf and known settings once, keeping original and destination data")
    }
}
