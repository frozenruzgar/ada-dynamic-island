@testable import Ada
@testable import AdaCore
import AppKit
import Foundation
enum AssistantChecks {
    @MainActor static func main() async {
        let store = AssistantStore()
        assert(store.preparedPrompt.isEmpty)
        store.draft = "  Bir örnek metin.  "
        assert(store.preparedPrompt == "Bir örnek metin.")
        store.task = .summarize
        assert(store.preparedPrompt.hasPrefix(store.task.instruction + "\n\n"))
        assert(store.preparedPrompt.hasSuffix("\n\nBir örnek metin."))
        store.task = .improve
        assert(store.preparedPrompt.hasPrefix(store.task.instruction + "\n\n"))
        store.task = .translate
        assert(store.preparedPrompt.hasPrefix(store.task.instruction + "\n\n"))
        store.task = .email
        assert(store.preparedPrompt.hasPrefix(store.task.instruction + "\n\n"))
        store.clearDraft()
        assert(store.preparedPrompt.isEmpty)
        for provider in AssistantProvider.allCases {
            assert(provider.url.scheme == "https")
            assert(provider.url.query == nil)
            assert(["chatgpt.com", "claude.ai"].contains(provider.url.host!))
        }
        store.draft = "Local draft"
        var erased = false
        await store.clearSessions {
            precondition(store.clearingSessions && store.sessionStatus == nil)
            erased = true
        }
        precondition(erased && !store.clearingSessions && store.sessionStatus != nil)
        precondition(store.draft == "Local draft")
        print("PASS: assistant local prompt composition, empty-state, templates and official provider URLs; no network or clipboard access")
    }
}
