import AppKit
import Foundation
@main struct AssistantChecks {
    @MainActor static func main() {
        let store = AssistantStore()
        assert(store.preparedPrompt.isEmpty)
        store.draft = "  Bir örnek metin.  "
        assert(store.preparedPrompt == "Bir örnek metin.")
        store.task = .summarize
        assert(store.preparedPrompt.contains("özetle"))
        assert(store.preparedPrompt.hasSuffix("\n\nBir örnek metin."))
        store.task = .improve
        assert(store.preparedPrompt.contains("anlamını koruyarak"))
        store.task = .translate
        assert(store.preparedPrompt.contains("İngilizceyle"))
        store.task = .email
        assert(store.preparedPrompt.contains("e-posta taslağı"))
        store.clearDraft()
        assert(store.preparedPrompt.isEmpty)
        for provider in AssistantProvider.allCases {
            assert(provider.url.scheme == "https")
            assert(provider.url.query == nil)
            assert(["chatgpt.com", "claude.ai"].contains(provider.url.host!))
        }
        print("PASS: assistant local prompt composition, empty-state, templates and official provider URLs; no network or clipboard access")
    }
}
