import Combine
import Foundation
import ServiceManagement

@MainActor
protocol LoginItemService {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
    func openSettings()
}

@MainActor
private final class MainAppLoginItemService: LoginItemService {
    private let service = SMAppService.mainApp
    var status: SMAppService.Status { service.status }
    func register() throws { try service.register() }
    func unregister() throws { try service.unregister() }
    func openSettings() { SMAppService.openSystemSettingsLoginItems() }
}

/// Registers the main app for the next login, without a helper that relaunches it after quitting.
@MainActor
final class LoginItemStore: ObservableObject {
    /// Includes a registered request awaiting macOS approval; check requiresApproval for readiness.
    @Published private(set) var enabled = false
    @Published private(set) var requiresApproval = false
    @Published private(set) var isBusy = false
    @Published private(set) var statusMessage: String?
    private let service: any LoginItemService

    init(service: (any LoginItemService)? = nil) {
        self.service = service ?? MainAppLoginItemService()
        refresh()
    }

    /// Reflect changes made in System Settings, without overriding them.
    func refresh() { publish(service.status) }

    func setEnabled(_ requested: Bool) {
        guard !isBusy else { return }
        let current = service.status
        publish(current)
        if requested && (current == .enabled || current == .requiresApproval) { return }
        if !requested && (current == .notRegistered || current == .notFound) { return }

        isBusy = true
        defer { isBusy = false }
        var failure: String?
        do {
            if requested { try service.register() }
            else { try service.unregister() }
        } catch {
            failure = requested
                ? "Otomatik başlatma açılamadı. Tekrar dene."
                : "Otomatik başlatma kapatılamadı. Tekrar dene."
        }
        let result = service.status
        // The system may finish an external change while this request is running.
        // Its actual state takes precedence over an already-registered/not-found error.
        if requested && (result == .enabled || result == .requiresApproval) { failure = nil }
        if !requested && result == .notRegistered { failure = nil }
        publish(result, failure: failure)
    }

    func openSettings() { service.openSettings() }

    private func publish(_ status: SMAppService.Status, failure: String? = nil) {
        enabled = status == .enabled || status == .requiresApproval
        requiresApproval = status == .requiresApproval
        if let failure {
            statusMessage = failure
            return
        }
        switch status {
        case .enabled:
            statusMessage = "Mac’e giriş yaptığında Ada açılır."
        case .requiresApproval:
            statusMessage = "Otomatik açılmak için Sistem Ayarları’nda Ada’ya izin ver."
        case .notRegistered:
            statusMessage = nil
        case .notFound:
            statusMessage = "Ada’nın başlangıç kaydı bulunamadı."
        @unknown default:
            statusMessage = "Başlangıç durumu okunamadı."
        }
    }
}
