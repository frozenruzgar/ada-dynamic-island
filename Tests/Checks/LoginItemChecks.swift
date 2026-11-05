@testable import Ada
@testable import AdaCore
import Foundation
import ServiceManagement

@MainActor
private final class FakeLoginItemService: LoginItemService {
    var status: SMAppService.Status = .notRegistered
    var registerCount = 0
    var unregisterCount = 0
    var settingsCount = 0
    var registeredStatus: SMAppService.Status = .enabled
    var registrationFails = false
    var unregistrationFails = false
    var externalRegistrationRace = false
    var externalUnregistrationRace = false

    func register() throws {
        registerCount += 1
        if externalRegistrationRace {
            status = .enabled
            throw NSError(domain: "Test", code: 1)
        }
        if registrationFails { throw NSError(domain: "Test", code: 2) }
        status = registeredStatus
    }

    func unregister() throws {
        unregisterCount += 1
        if externalUnregistrationRace {
            status = .notRegistered
            throw NSError(domain: "Test", code: 3)
        }
        if unregistrationFails { throw NSError(domain: "Test", code: 4) }
        status = .notRegistered
    }

    func openSettings() { settingsCount += 1 }
}

enum LoginItemChecks {
    @MainActor static func main() {
        func expect(_ condition: Bool, _ description: String) { precondition(condition, description) }
        let fake = FakeLoginItemService()
        let store = LoginItemStore(service: fake)
        expect(!store.enabled && !store.requiresApproval && !store.isBusy, "Initial system state is shown")
        store.refresh()
        expect(fake.registerCount == 0 && fake.unregisterCount == 0, "Initialization and refresh never register automatically")
        store.setEnabled(false)
        expect(fake.unregisterCount == 0, "Disabling an unregistered item is a no-op")

        store.setEnabled(true)
        expect(store.enabled && !store.requiresApproval && fake.registerCount == 1, "Explicit enabling registers the main app")
        store.setEnabled(true)
        expect(fake.registerCount == 1, "Repeated enabling does not register twice")
        store.setEnabled(false)
        expect(!store.enabled && fake.unregisterCount == 1 && !store.isBusy, "Disabling reflects the actual unregistered state")

        fake.registeredStatus = .requiresApproval
        store.setEnabled(true)
        expect(store.enabled && store.requiresApproval && store.statusMessage != nil, "Pending approval remains requested but is clearly identified")
        store.setEnabled(true)
        expect(fake.registerCount == 2, "Pending approval does not trigger repeated registration")
        expect(fake.settingsCount == 0, "Settings are never opened automatically")
        store.openSettings()
        expect(fake.settingsCount == 1, "The explicit settings action is routed")
        fake.status = .enabled
        store.refresh()
        expect(store.enabled && !store.requiresApproval, "External approval is reflected")
        fake.status = .notRegistered
        store.refresh()
        expect(!store.enabled && store.statusMessage == nil, "External removal is respected without re-registering")

        fake.registrationFails = true
        store.setEnabled(true)
        expect(!store.enabled && store.statusMessage != nil && !store.isBusy, "Registration failure cannot falsely enable the toggle")
        fake.registrationFails = false
        fake.registeredStatus = .enabled
        store.setEnabled(true)
        fake.unregistrationFails = true
        store.setEnabled(false)
        expect(store.enabled && store.statusMessage == L10n.string("Otomatik başlatma kapatılamadı. Tekrar dene."), "Failed disabling retains the real enabled state")

        fake.unregistrationFails = false
        fake.externalUnregistrationRace = true
        store.setEnabled(false)
        expect(!store.enabled && store.statusMessage == nil, "An already-unregistered race follows system truth")
        fake.externalRegistrationRace = true
        store.setEnabled(true)
        expect(store.enabled && !store.requiresApproval && store.statusMessage == L10n.string("Mac’e giriş yaptığında Ada açılır."), "An already-registered race follows system truth")

        fake.status = .notFound
        store.refresh()
        expect(!store.enabled && !store.requiresApproval && store.statusMessage != nil, "Missing registration is not reported as enabled")
        print("PASS: login-item explicit registration, idempotency, pending approval, external settings changes, errors and races; no system login item changed")
    }
}
