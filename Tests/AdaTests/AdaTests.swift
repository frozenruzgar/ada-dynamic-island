import XCTest
@testable import AdaCheckSuite

final class AdaTests: XCTestCase {
    @MainActor func testCorePolicies() async throws { try CoreChecks.main() }
    @MainActor func testAssistantChecks() async throws { await AssistantChecks.main() }
    @MainActor func testBatteryEventChecks() async throws { BatteryEventChecks.main() }
    @MainActor func testCalendarChecks() async throws { CalendarChecks.main() }
    @MainActor func testClockModelChecks() async throws { ClockModelChecks.main() }
    @MainActor func testCloudChecks() async throws { try CloudChecks.main() }
    @MainActor func testDashboardTilesChecks() async throws { try DashboardTilesChecks.main() }
    @MainActor func testFocusNotificationChecks() async throws { await FocusNotificationChecks.main() }
    @MainActor func testLocalizationChecks() async throws { try LocalizationChecks.main() }
    @MainActor func testInstallationChecks() async throws { try InstallationChecks.main() }
    @MainActor func testLoginItemChecks() async throws { LoginItemChecks.main() }
    @MainActor func testNoteChecks() async throws { try await NoteChecks.main() }
    @MainActor func testNowPlayingChecks() async throws { NowPlayingChecks.main() }
    @MainActor func testPreferencesChecks() async throws { try PreferencesChecks.main() }
    @MainActor func testPrompterChecks() async throws { PrompterChecks.main() }
    @MainActor func testSettingsLayoutChecks() async throws { SettingsLayoutChecks.main() }
    @MainActor func testShelfChecks() async throws { try await ShelfChecks.main() }
    @MainActor func testShelfStorageChecks() async throws { try await ShelfStorageChecks.main() }
    @MainActor func testSystemChecks() async throws { SystemChecks.main() }
    @MainActor func testWelcomeChecks() async throws { try WelcomeChecks.main() }
    @MainActor func testWorkspaceChecks() async throws { try WorkspaceChecks.main() }
}
