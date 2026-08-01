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
        let settings = GlobalShortcutSettings(
            showHideDocks: GlobalShortcut(
                keyCode: UInt32(kVK_ANSI_D),
                modifiers: UInt32(cmdKey) | UInt32(optionKey)
            ),
            quickLaunch: GlobalShortcut(
                keyCode: UInt32(kVK_ANSI_F),
                modifiers: UInt32(controlKey) | UInt32(shiftKey)
            )
        )
        let config = AppConfig(globalShortcuts: settings)
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
        #expect(decoded.globalShortcuts == GlobalShortcutSettings())
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

    @Test("Fixed profile combinations stay reserved")
    func profileCollision() {
        let settings = GlobalShortcutSettings(
            showHideDocks: GlobalShortcut(
                keyCode: UInt32(kVK_ANSI_1),
                modifiers: GlobalShortcutManager.standardModifiers
            )
        )
        #expect(settings.validationError()?.contains("profile") == true)
    }
}
