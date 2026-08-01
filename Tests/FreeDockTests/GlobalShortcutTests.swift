import Carbon.HIToolbox
import Foundation
import Testing
@testable import FreeDock

@Suite("Configurable global shortcuts")
struct GlobalShortcutTests {
    @Test("Default shortcuts preserve existing behavior")
    func defaults() {
        let settings = GlobalShortcutSettings()
        #expect(settings.showHideDocks.displayName == "⌃⌥Space")
        #expect(settings.quickLaunch.displayName == "⇧⌘Space")
        #expect(settings.validationError() == nil)
    }

    @Test("Shortcut settings round-trip in application config")
    func configRoundTrip() throws {
        let profile = DockProfile(name: "Work")
        var settings = GlobalShortcutSettings(
            showHideDocks: GlobalShortcut(
                keyCode: UInt32(kVK_ANSI_D),
                modifiers: UInt32(cmdKey) | UInt32(optionKey)
            ),
            quickLaunch: GlobalShortcut(
                keyCode: UInt32(kVK_ANSI_F),
                modifiers: UInt32(controlKey) | UInt32(shiftKey)
            )
        )
        settings.reconcileProfiles([profile])
        let config = AppConfig(profiles: [profile], globalShortcuts: settings)
        let decoded = try JSONDecoder().decode(
            AppConfig.self,
            from: JSONEncoder().encode(config)
        )
        #expect(decoded.globalShortcuts == settings)
    }

    @Test("Older configs receive default shortcuts")
    func legacyDefaults() throws {
        let data = Data("""
        { "formatVersion": 4, "docks": [] }
        """.utf8)
        let decoded = try JSONDecoder().decode(AppConfig.self, from: data)
        #expect(decoded.globalShortcuts.showHideDocks == .defaultShowHide)
        #expect(decoded.globalShortcuts.quickLaunch == .defaultQuickLaunch)
        #expect(decoded.globalShortcuts.shortcut(
            forProfile: decoded.activeProfileID
        ) == GlobalShortcutSettings.defaultProfileShortcuts[0])
    }

    @Test("Duplicate and modifierless shortcuts are rejected")
    func basicValidation() {
        let duplicate = GlobalShortcutSettings(
            showHideDocks: .defaultShowHide,
            quickLaunch: .defaultShowHide
        )
        #expect(duplicate.validationError()?.contains("same") == true)

        let modifierless = GlobalShortcut(
            keyCode: UInt32(kVK_ANSI_A),
            modifiers: 0
        )
        let invalid = GlobalShortcutSettings(
            showHideDocks: modifierless
        )
        #expect(invalid.validationError()?.contains("modifier") == true)
    }

    @Test("Profile shortcuts cannot collide with another global action")
    func profileCollision() {
        let profileID = UUID()
        let settings = GlobalShortcutSettings(
            profileShortcuts: [ProfileShortcutAssignment(
                profileID: profileID,
                shortcut: .defaultShowHide
            )]
        )
        #expect(settings.validationError()?.contains("unique") == true)
    }

    @Test("Profile shortcuts follow profile identity and can stay cleared")
    func profileIdentityAndClearing() {
        let work = DockProfile(name: "Work")
        let personal = DockProfile(name: "Personal")
        var settings = GlobalShortcutSettings()
        settings.reconcileProfiles([work, personal])
        let workShortcut = settings.shortcut(forProfile: work.id)
        let personalShortcut = settings.shortcut(forProfile: personal.id)

        settings.reconcileProfiles([personal, work])
        #expect(settings.shortcut(forProfile: work.id) == workShortcut)
        #expect(settings.shortcut(forProfile: personal.id) == personalShortcut)

        settings.setProfileShortcut(nil, for: work.id)
        settings.reconcileProfiles([personal, work])
        #expect(settings.shortcut(forProfile: work.id) == nil)
    }

    @Test("New profiles receive the next unused default shortcut")
    func newProfileDefault() {
        let first = DockProfile(name: "First")
        let second = DockProfile(name: "Second")
        var settings = GlobalShortcutSettings()
        settings.reconcileProfiles([first])
        settings.reconcileProfiles([first, second])

        #expect(settings.shortcut(forProfile: first.id)
            == GlobalShortcutSettings.defaultProfileShortcuts[0])
        #expect(settings.shortcut(forProfile: second.id)
            == GlobalShortcutSettings.defaultProfileShortcuts[1])
    }
}
