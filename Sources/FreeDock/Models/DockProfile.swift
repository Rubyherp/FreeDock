import Foundation

enum ProfileAutomationTriggerKind: String, Codable, CaseIterable, Sendable {
    case application
    case display
}

struct ProfileAutomationRule: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var triggerKind: ProfileAutomationTriggerKind
    var value: String
    var label: String
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        triggerKind: ProfileAutomationTriggerKind,
        value: String,
        label: String,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.triggerKind = triggerKind
        self.value = value
        self.label = label
        self.isEnabled = isEnabled
    }
}

struct DockProfile: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var name: String
    var docks: [DockConfig]
    var automationRules: [ProfileAutomationRule]

    init(
        id: UUID = UUID(),
        name: String,
        docks: [DockConfig] = [],
        automationRules: [ProfileAutomationRule] = []
    ) {
        self.id = id
        self.name = name
        self.docks = docks
        self.automationRules = automationRules
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case docks
        case automationRules
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        docks = try container.decodeIfPresent(
            [DockConfig].self,
            forKey: .docks
        ) ?? []
        automationRules = try container.decodeIfPresent(
            [ProfileAutomationRule].self,
            forKey: .automationRules
        ) ?? []
    }
}

enum ProfileAutomationPlanner {
    static func matchingProfileID(
        triggerKind: ProfileAutomationTriggerKind,
        value: String,
        profiles: [DockProfile]
    ) -> UUID? {
        profiles.first(where: { profile in
            profile.automationRules.contains(where: { rule in
                rule.isEnabled
                    && rule.triggerKind == triggerKind
                    && rule.value.caseInsensitiveCompare(value) == .orderedSame
            })
        })?.id
    }
}
