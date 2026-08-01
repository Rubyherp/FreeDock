import Foundation
import Testing

@testable import FreeDock

@Suite("Profile automation")
struct ProfileAutomationTests {
    @Test("Application and display rules match their owning profile")
    func matching() {
        let work = DockProfile(
            name: "Work",
            automationRules: [
                ProfileAutomationRule(
                    triggerKind: .application,
                    value: "com.apple.dt.Xcode",
                    label: "Xcode"
                )
            ]
        )
        let presentation = DockProfile(
            name: "Presentation",
            automationRules: [
                ProfileAutomationRule(
                    triggerKind: .display,
                    value: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
                    label: "Studio Display"
                )
            ]
        )

        #expect(ProfileAutomationPlanner.matchingProfileID(
            triggerKind: .application,
            value: "com.apple.dt.xcode",
            profiles: [work, presentation]
        ) == work.id)
        #expect(ProfileAutomationPlanner.matchingProfileID(
            triggerKind: .display,
            value: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
            profiles: [work, presentation]
        ) == presentation.id)
    }

    @Test("Disabled rules do not activate profiles")
    func disabled() {
        let profile = DockProfile(
            name: "Work",
            automationRules: [
                ProfileAutomationRule(
                    triggerKind: .application,
                    value: "com.example.Editor",
                    label: "Editor",
                    isEnabled: false
                )
            ]
        )
        #expect(ProfileAutomationPlanner.matchingProfileID(
            triggerKind: .application,
            value: "com.example.Editor",
            profiles: [profile]
        ) == nil)
    }

    @Test("Older profiles decode with no automation rules")
    func migration() throws {
        let id = UUID()
        let data = Data("""
        { "id": "\(id.uuidString)", "name": "Legacy", "docks": [] }
        """.utf8)
        let profile = try JSONDecoder().decode(DockProfile.self, from: data)
        #expect(profile.automationRules.isEmpty)
    }
}
