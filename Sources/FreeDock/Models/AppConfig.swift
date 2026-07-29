import Foundation

struct AppConfig: Codable, Sendable {
    static let currentFormatVersion = 3

    var profiles: [DockProfile]
    var activeProfileID: UUID

    init(docks: [DockConfig] = []) {
        let profile = DockProfile(name: "Default", docks: docks)
        profiles = [profile]
        activeProfileID = profile.id
    }

    init(profiles: [DockProfile], activeProfileID: UUID? = nil) {
        let availableProfiles = profiles.isEmpty ? [DockProfile(name: "Default")] : profiles
        self.profiles = availableProfiles
        if let activeProfileID,
           availableProfiles.contains(where: { $0.id == activeProfileID })
        {
            self.activeProfileID = activeProfileID
        } else {
            self.activeProfileID = availableProfiles[0].id
        }
    }

    var docks: [DockConfig] {
        get {
            profiles.first(where: { $0.id == activeProfileID })?.docks ?? []
        }
        set {
            guard let index = profiles.firstIndex(where: { $0.id == activeProfileID }) else {
                let profile = DockProfile(name: "Default", docks: newValue)
                profiles = [profile]
                activeProfileID = profile.id
                return
            }
            profiles[index].docks = newValue
        }
    }

    var activeProfileName: String {
        profiles.first(where: { $0.id == activeProfileID })?.name ?? "Default"
    }

    private enum CodingKeys: String, CodingKey {
        case formatVersion
        case profiles
        case activeProfileID
        case docks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let decodedProfiles = try container.decodeIfPresent([DockProfile].self, forKey: .profiles),
           !decodedProfiles.isEmpty
        {
            profiles = decodedProfiles
            let requestedID = try container.decodeIfPresent(UUID.self, forKey: .activeProfileID)
            if let requestedID,
               decodedProfiles.contains(where: { $0.id == requestedID })
            {
                activeProfileID = requestedID
            } else {
                activeProfileID = decodedProfiles[0].id
            }
            return
        }

        let legacyDocks = try container.decodeIfPresent([DockConfig].self, forKey: .docks) ?? []
        let migratedProfile = DockProfile(name: "Default", docks: legacyDocks)
        profiles = [migratedProfile]
        activeProfileID = migratedProfile.id
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentFormatVersion, forKey: .formatVersion)
        try container.encode(profiles, forKey: .profiles)
        try container.encode(activeProfileID, forKey: .activeProfileID)
        try container.encode(docks, forKey: .docks)
    }
}
