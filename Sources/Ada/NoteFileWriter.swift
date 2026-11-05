import AdaCore
import Foundation

/// Serializes atomic note writes and rejects late saves from older revisions.
actor NoteFileWriter {
    let url: URL
    private var newestRevision: UInt64 = 0
    private var recoveryBackupRequired: Bool

    init(url: URL, recoveryBackupRequired: Bool = false) {
        self.url = url
        self.recoveryBackupRequired = recoveryBackupRequired
    }

    func write(_ text: String, revision: UInt64) throws {
        guard revision >= newestRevision else { return }
        newestRevision = revision
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        if recoveryBackupRequired && FileManager.default.fileExists(atPath: url.path) {
            let backup = parent.appendingPathComponent("note-recovery-" + UUID().uuidString + ".md")
            try FileManager.default.copyItem(at: url, to: backup)
            recoveryBackupRequired = false
        }
        try Data(text.utf8).write(to: url, options: .atomic)
    }

    static func export(_ text: String, to url: URL) throws {
        try Data(text.utf8).write(to: url, options: .atomic)
    }
}
