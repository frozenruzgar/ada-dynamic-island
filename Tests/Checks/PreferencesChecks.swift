@testable import Ada
@testable import AdaCore
import Foundation

enum PreferencesChecks {
    static func main() throws {
        let legacy = Data(#"{"shelfRetentionDays":7,"accent":"purple","panelOpacity":0.7,"closeDelay":0.6}"#.utf8)
        let value = try JSONDecoder().decode(IslandPreferences.self, from: legacy)
        precondition(value.accent == .purple && value.closeDelay == 0.6)
        let encoded = try JSONEncoder().encode(value)
        let fields = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        precondition(fields["shelfRetentionDays"] == nil)
        let roundTrip = try JSONDecoder().decode(IslandPreferences.self, from: encoded)
        precondition(roundTrip == value)
        precondition(value.openShelfOnDrag, "Legacy settings keep drag opening")
        var dragDisabled = IslandPreferences()
        dragDisabled.openShelfOnDrag = false
        let savedDragSetting = try JSONEncoder().encode(dragDisabled)
        precondition(try! JSONDecoder().decode(IslandPreferences.self, from: savedDragSetting).openShelfOnDrag == false)
        dragDisabled.resetAppearance()
        precondition(!dragDisabled.openShelfOnDrag, "Appearance reset preserves drag behavior")
        var customized = IslandPreferences()
        customized.expandedWidth = 880
        customized.palette = .forest
        customized.style = .floating
        customized.startupPage = .files
        customized.hoverToOpen = false
        customized.closeDelay = 0.73
        customized.globalShortcutEnabled = false
        customized.displayChoice = .main
        customized.defaultMinutes = 50
        customized.breakMinutes = 12
        customized.pomodoro = false
        customized.monitoringEnabled = false
        customized.showNowPlaying = false
        customized.resetAppearance()
        let fresh = IslandPreferences()
        precondition(!fresh.notifyOnCompletion)
        precondition(customized.expandedWidth == fresh.expandedWidth && customized.palette == fresh.palette)
        precondition(customized.style == fresh.style && customized.startupPage == fresh.startupPage)
        precondition(!customized.hoverToOpen && customized.closeDelay == 0.73)
        precondition(!customized.globalShortcutEnabled && customized.displayChoice == .main)
        precondition(customized.defaultMinutes == 50 && customized.breakMinutes == 12 && !customized.pomodoro)
        precondition(!customized.monitoringEnabled && !customized.showNowPlaying)
        let domain = "AdaPreferenceDelay-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        for (stored, expected) in [(0.37, 0.37), (0.01, 0.12), (2.0, 1.5)] {
            let record: [String: Any] = ["panelOpacity": 0.7, "closeDelay": stored, "hoverSettingsVersion": 1]
            defaults.set(try JSONSerialization.data(withJSONObject: record), forKey: "workspacePreferencesV3")
            let loaded = IslandPreferences.load(defaults: defaults)
            precondition(loaded.closeDelay == expected && IslandPreferences.closeDelayRange.contains(loaded.closeDelay))
        }
        let modern: [String: Any] = ["hoverSettingsVersion": 1, "hoverToOpen": false,
            "expandedWidth": 712, "closeDelay": 0.63, "palette": "forest"]
        defaults.set(try JSONSerialization.data(withJSONObject: modern), forKey: "workspacePreferencesV3")
        var migrated = IslandPreferences.load(defaults: defaults)
        precondition(migrated.schemaVersion == IslandPreferences.currentSchemaVersion)
        precondition(!migrated.hoverToOpen && migrated.expandedWidth == 712 && migrated.closeDelay == 0.63)
        let migratedFields = try JSONSerialization.jsonObject(with: defaults.data(forKey: "workspacePreferencesV3")!) as! [String: Any]
        precondition(migratedFields["schemaVersion"] as? Int == IslandPreferences.currentSchemaVersion)
        precondition(migratedFields["hoverSettingsVersion"] == nil)
        migrated.hoverToOpen = false
        defaults.set(try JSONEncoder().encode(migrated), forKey: "workspacePreferencesV3")
        precondition(!IslandPreferences.load(defaults: defaults).hoverToOpen)
        let oldest = Data(#"{"hoverToOpen":false,"expandedWidth":700,"closeDelay":0.51,"breakMinutes":99,"floatingGap":99}"#.utf8)
        defaults.set(oldest, forKey: "workspacePreferencesV3")
        let upgraded = IslandPreferences.load(defaults: defaults)
        precondition(upgraded.hoverToOpen && upgraded.expandedWidth == 700 && upgraded.closeDelay == 0.51)
        precondition(upgraded.breakMinutes == 30 && upgraded.floatingGap == 40)
        let future = Data(#"{"schemaVersion":99,"hoverToOpen":false,"futureSetting":"preserve"}"#.utf8)
        defaults.set(future, forKey: "workspacePreferencesV3")
        let futureValue = IslandPreferences.load(defaults: defaults)
        precondition(!futureValue.supportsPersistence && !futureValue.hoverToOpen)
        precondition(defaults.data(forKey: "workspacePreferencesV3") == future)
        let corrupt = Data("broken".utf8)
        defaults.set(corrupt, forKey: "workspacePreferencesV3")
        _ = IslandPreferences.load(defaults: defaults)
        precondition(defaults.data(forKey: "workspacePreferencesV3") == corrupt)
        let unknown = Data(#"{"schemaVersion":1,"style":"unknown","accent":7,"palette":null,"displayChoice":"alien","startupPage":"player"}"#.utf8)
        let safe = try JSONDecoder().decode(IslandPreferences.self, from: unknown)
        precondition(safe.style == .notch && safe.accent == .blue && safe.palette == .nebula)
        precondition(safe.displayChoice == .builtin && safe.startupPage == .chatGPT)
        let encodedStyle = try JSONEncoder().encode(IslandStyle.floating)
        precondition(String(data: encodedStyle, encoding: .utf8) == "\"floating\"")
        let unknownStyle = try JSONDecoder().decode(IslandStyle.self, from: Data("\"future\"".utf8))
        precondition(unknownStyle == .notch)
        let motion = try JSONDecoder().decode(IslandPreferences.self, from: Data(#"{"schemaVersion":1,"backgroundMotion":"unknown"}"#.utf8))
        precondition(motion.backgroundMotion == .gentle && motion.backgroundMotion.framesPerSecond == 10)
        let duplicate = ShortcutBinding(keyCode: 0, modifiers: ShortcutBinding.standard.modifiers, key: "a")!
        precondition(duplicate.conflicts(with: .standard))
        precondition(ShortcutBinding(keyCode: 0, modifiers: ShortcutBinding.shift, key: "A") == nil)
        var custom = IslandPreferences()
        custom.panelShortcut = duplicate
        custom.filesShortcut = duplicate
        let decoded = try JSONDecoder().decode(IslandPreferences.self, from: JSONEncoder().encode(custom))
        precondition(decoded.panelShortcut == duplicate && decoded.filesShortcut == nil)
        print("PASS: legacy shelf preference ignored without affecting active preferences; round-trip encoding; appearance reset preserves behavior, display and focus settings; arbitrary close delay and bound clamping; versioned migration, hover opt-out persistence and future/corrupt record preservation; typed options, invalid-value fallbacks and compatible string encoding")
    }
}
