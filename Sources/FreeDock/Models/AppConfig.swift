import Foundation

struct AppConfig: Codable, Sendable {
    static let currentFormatVersion = 10

    var profiles: [DockProfile]
    var activeProfileID: UUID
    var recentFiles: [RecentFileRecord]
    var globalShortcuts: GlobalShortcutSettings
    var recentApplications: [RecentApplicationRecord]
    var themes: [DockTheme]

    init(
        docks: [DockConfig] = [],
        recentFiles: [RecentFileRecord] = [],
        globalShortcuts: GlobalShortcutSettings = GlobalShortcutSettings(),
        recentApplications: [RecentApplicationRecord] = [],
        themes: [DockTheme] = []
    ) {
        let profile = DockProfile(name: "Default", docks: docks)
        profiles = [profile]
        activeProfileID = profile.id
        self.recentFiles = RecentFileHistoryPlanner.normalized(
            recentFiles,
            limit: RecentFileHistoryPlanner.maximumLimit
        )
        self.globalShortcuts = globalShortcuts
        self.globalShortcuts.reconcileProfiles(profiles)
        self.recentApplications = RecentApplicationHistoryPlanner.normalized(
            recentApplications
        )
        self.themes = themes
    }

    init(
        profiles: [DockProfile],
        activeProfileID: UUID? = nil,
        recentFiles: [RecentFileRecord] = [],
        globalShortcuts: GlobalShortcutSettings = GlobalShortcutSettings(),
        recentApplications: [RecentApplicationRecord] = [],
        themes: [DockTheme] = []
    ) {
        let availableProfiles = profiles.isEmpty ? [DockProfile(name: "Default")] : profiles
        self.profiles = availableProfiles
        if let activeProfileID,
           availableProfiles.contains(where: { $0.id == activeProfileID })
        {
            self.activeProfileID = activeProfileID
        } else {
            self.activeProfileID = availableProfiles[0].id
        }
        self.recentFiles = RecentFileHistoryPlanner.normalized(
            recentFiles,
            limit: RecentFileHistoryPlanner.maximumLimit
        )
        self.globalShortcuts = globalShortcuts
        self.globalShortcuts.reconcileProfiles(availableProfiles)
        self.recentApplications = RecentApplicationHistoryPlanner.normalized(
            recentApplications
        )
        self.themes = themes
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
        case recentFiles
        case globalShortcuts
        case recentApplications
        case themes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        recentFiles = RecentFileHistoryPlanner.normalized(
            (try? container.decode(
                [RecentFileRecord].self,
                forKey: .recentFiles
            )) ?? [],
            limit: RecentFileHistoryPlanner.maximumLimit
        )
        globalShortcuts = (try? container.decode(
            GlobalShortcutSettings.self,
            forKey: .globalShortcuts
        )) ?? GlobalShortcutSettings()
        recentApplications = RecentApplicationHistoryPlanner.normalized(
            (try? container.decode(
                [RecentApplicationRecord].self,
                forKey: .recentApplications
            )) ?? []
        )
        themes = (try? container.decode([DockTheme].self, forKey: .themes)) ?? []

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
            globalShortcuts.reconcileProfiles(profiles)
            return
        }

        let legacyDocks = try container.decodeIfPresent([DockConfig].self, forKey: .docks) ?? []
        let migratedProfile = DockProfile(name: "Default", docks: legacyDocks)
        profiles = [migratedProfile]
        activeProfileID = migratedProfile.id
        globalShortcuts.reconcileProfiles(profiles)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentFormatVersion, forKey: .formatVersion)
        try container.encode(profiles, forKey: .profiles)
        try container.encode(activeProfileID, forKey: .activeProfileID)
        try container.encode(docks, forKey: .docks)
        try container.encode(recentFiles, forKey: .recentFiles)
        try container.encode(globalShortcuts, forKey: .globalShortcuts)
        try container.encode(recentApplications, forKey: .recentApplications)
        try container.encode(themes, forKey: .themes)
    }
}
