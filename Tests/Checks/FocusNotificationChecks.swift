@testable import Ada
@testable import AdaCore
import AppKit
import Foundation

@MainActor private final class FakeFocusNotificationClient: FocusNotificationClient {
    var allowed = false
    var requests = 0
    var sent: [(String, String)] = []
    var fail = false
    func requestAuthorization() async throws -> Bool { requests += 1; return allowed }
    func post(title: String, body: String) async throws {
        if fail { throw CocoaError(.fileWriteUnknown) }
        sent.append((title, body))
    }
}

enum FocusNotificationChecks {
    @MainActor static func main() async {
        let client = FakeFocusNotificationClient()
        let store = FocusNotificationStore(client: client)
        await store.sendCompletion(enabled: false, isBreak: false)
        precondition(client.requests == 0 && client.sent.isEmpty)
        let denied = await store.requestEnable()
        precondition(!denied && client.requests == 1 && store.statusMessage != nil)
        client.allowed = true
        let allowed = await store.requestEnable()
        precondition(allowed && client.requests == 2 && store.statusMessage == nil)
        await store.sendCompletion(enabled: true, isBreak: false)
        await store.sendCompletion(enabled: true, isBreak: true)
        precondition(client.sent.count == 2 && client.requests == 2)
        precondition(client.sent[0].0 == L10n.string("Odak tamamlandı"))
        precondition(client.sent[1].0 == L10n.string("Mola tamamlandı"))
        client.fail = true
        await store.sendCompletion(enabled: true, isBreak: false)
        precondition(store.statusMessage != nil && client.sent.count == 2)
        print("PASS: notification opt-in, no work while disabled, permission denial/approval, focus/break context and delivery errors; no OS permission or notification requested")
    }
}
