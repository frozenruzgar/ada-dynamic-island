import AdaCore
import AppKit
import Combine
import UserNotifications

@MainActor
protocol FocusNotificationClient {
    func requestAuthorization() async throws -> Bool
    func post(title: String, body: String) async throws
}

@MainActor
private final class SystemFocusNotificationClient: NSObject, FocusNotificationClient, UNUserNotificationCenterDelegate {
    private var center: UNUserNotificationCenter {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        return center
    }
    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert])
    }
    func post(title: String, body: String) async throws {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        // The existing timer sound preference already handles sound; avoid doubles.
        let request = UNNotificationRequest(identifier: "ada.focus." + UUID().uuidString, content: content, trigger: nil)
        try await center.add(request)
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner])
    }
}

@MainActor
final class FocusNotificationStore: ObservableObject {
    @Published private(set) var isRequesting = false
    @Published private(set) var statusMessage: String?
    private let client: FocusNotificationClient

    init(client: FocusNotificationClient? = nil) {
        // Creating the adapter never creates the system center or asks permission.
        self.client = client ?? SystemFocusNotificationClient()
    }
    func requestEnable() async -> Bool {
        guard !isRequesting else { return false }
        isRequesting = true
        defer { isRequesting = false }
        do {
            let allowed = try await client.requestAuthorization()
            statusMessage = allowed ? nil : L10n.string("Bildirim izni kapalı. Sistem Ayarları → Bildirimler bölümünden Ada’yı kontrol et.")
            return allowed
        } catch {
            statusMessage = L10n.string("Bildirim izni alınamadı: \(error.localizedDescription)")
            return false
        }
    }
    func sendCompletion(enabled: Bool, isBreak: Bool) async {
        guard enabled else { return }
        let title = isBreak ? L10n.string("Mola tamamlandı") : L10n.string("Odak tamamlandı")
        let body = isBreak ? L10n.string("Hazır olduğunda yeni bir odak oturumu başlatabilirsin.")
            : L10n.string("Bir mola verebilirsin.")
        do { try await client.post(title: title, body: body) }
        catch { statusMessage = L10n.string("Bildirim gönderilemedi: \(error.localizedDescription)") }
    }
}
