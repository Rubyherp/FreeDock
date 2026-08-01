import Carbon.HIToolbox
import Foundation
import Testing

@testable import FreeDock

@Suite("Individual profile files")
struct ProfileFileCodecTests {
    @Test("Archives preserve profile data and optional shortcuts")
    func roundTrip() throws {
        let profile = DockProfile(
            name: "Work",
            docks: [DockConfig(name: "Main")],
            automationRules: [ProfileAutomationRule(
                triggerKind: .application,
                value: "com.example.Editor",
                label: "Editor"
            )]
        )
        let shortcut = GlobalShortcut(
            keyCode: UInt32(kVK_ANSI_W),
            modifiers: UInt32(controlKey) | UInt32(optionKey)
        )
        let archive = DockProfileArchive(profile: profile, shortcut: shortcut)
        #expect(try ProfileFileCodec.decode(
            ProfileFileCodec.encode(archive)
        ) == archive)
    }

    @Test("Materialized profiles receive fresh nested identities")
    func freshIdentities() {
        let original = DockProfile(
            name: "Work",
            docks: [DockConfig(
                name: "Main",
                items: [DockItem.separator()]
            )],
            automationRules: [ProfileAutomationRule(
                triggerKind: .display,
                value: UUID().uuidString,
                label: "Display"
            )]
        )
        let imported = DockProfileArchive(
            profile: original,
            shortcut: nil
        ).materializedProfile(named: "Work 2")

        #expect(imported.id != original.id)
        #expect(imported.docks[0].id != original.docks[0].id)
        #expect(imported.docks[0].items[0].id != original.docks[0].items[0].id)
        #expect(imported.automationRules[0].id != original.automationRules[0].id)
    }

    @Test("Future profile archive versions are rejected")
    func futureVersion() throws {
        let archive = DockProfileArchive(
            profile: DockProfile(name: "Future"),
            shortcut: nil
        )
        var object = try #require(JSONSerialization.jsonObject(
            with: ProfileFileCodec.encode(archive)
        ) as? [String: Any])
        object["formatVersion"] = DockProfileArchive.currentFormatVersion + 1
        let data = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: ProfileFileCodecError.unsupportedVersion(2)) {
            try ProfileFileCodec.decode(data)
        }
    }
}
