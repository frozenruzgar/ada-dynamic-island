import Foundation
/// Same cases run through XCTest on full Xcode and the CLT fallback locally.
@MainActor public enum AdaCheckSuite {
    public static func runAll() async throws {
        try await CoreChecks.main()
        await AssistantChecks.main()
        BatteryEventChecks.main()
        CalendarChecks.main()
        ClockModelChecks.main()
        try CloudChecks.main()
        try DashboardTilesChecks.main()
        await FocusNotificationChecks.main()
        try LocalizationChecks.main()
        try InstallationChecks.main()
        LoginItemChecks.main()
        try await NoteChecks.main()
        NowPlayingChecks.main()
        try PreferencesChecks.main()
        PrompterChecks.main()
        SettingsLayoutChecks.main()
        try await ShelfChecks.main()
        try await ShelfStorageChecks.main()
        SystemChecks.main()
        try WelcomeChecks.main()
        try WorkspaceChecks.main()
    }
}
