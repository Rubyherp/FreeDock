import Testing
import Foundation
@testable import FreeDock

@Test("DockItem encodes and decodes round-trip")
func dockItemRoundTrip() throws {
    let item = DockItem(id: UUID(), appPath: "/Applications/Safari.app", label: "Safari")
    let data = try JSONEncoder().encode(item)
    let decoded = try JSONDecoder().decode(DockItem.self, from: data)
    #expect(decoded.appPath == "/Applications/Safari.app")
    #expect(decoded.label == "Safari")
}

@Test("DockConfig round-trips all fields")
func dockConfigRoundTrip() throws {
    let item = DockItem(appPath: "/App.app")
    let config = DockConfig(id: UUID(), name: "Test", position: CGPoint(x: 100, y: 200),
                            orientation: .vertical, iconSize: 64, items: [item],
                            autoHideWhenDocked: false, magnificationEnabled: false,
                            magnification: 1.55, itemSpacing: 9, appearance: .dark,
                            surfaceOpacity: 0.65, blurStyle: .strong,
                            cornerRadius: 24, shadowStrength: 1.6,
                            showRunningIndicators: false, autoHideDelay: 2.4)
    let data = try JSONEncoder().encode(config)
    let decoded = try JSONDecoder().decode(DockConfig.self, from: data)
    #expect(decoded.name == "Test")
    #expect(decoded.orientation == .vertical)
    #expect(decoded.iconSize == 64)
    #expect(decoded.items.count == 1)
    #expect(decoded.position == CGPoint(x: 100, y: 200))
    #expect(!decoded.autoHideWhenDocked)
    #expect(!decoded.magnificationEnabled)
    #expect(decoded.magnification == 1.55)
    #expect(decoded.itemSpacing == 9)
    #expect(decoded.appearance == .dark)
    #expect(decoded.surfaceOpacity == 0.65)
    #expect(decoded.blurStyle == .strong)
    #expect(decoded.cornerRadius == 24)
    #expect(decoded.shadowStrength == 1.6)
    #expect(!decoded.showRunningIndicators)
    #expect(decoded.autoHideDelay == 2.4)
}

@Test("DockConfig defaults edge auto-hide when loading an older config")
func dockConfigMigratesAutoHidePreference() throws {
    let data = """
    {
      "id": "F8CCF00C-3001-4D86-B572-1B5E4B5DBFEA",
      "name": "Legacy Dock",
      "position": [40, 80],
      "orientation": "horizontal",
      "iconSize": 48,
      "items": []
    }
    """.data(using: .utf8)!

    let decoded = try JSONDecoder().decode(DockConfig.self, from: data)
    #expect(decoded.autoHideWhenDocked)
    #expect(decoded.magnificationEnabled)
    #expect(decoded.magnification == 1.30)
    #expect(decoded.itemSpacing == 3)
    #expect(decoded.appearance == .glass)
    #expect(decoded.surfaceOpacity == 1)
    #expect(decoded.blurStyle == .regular)
    #expect(decoded.cornerRadius == 18)
    #expect(decoded.shadowStrength == 1)
    #expect(decoded.showRunningIndicators)
    #expect(decoded.autoHideDelay == 1)
}

@Test("DockConfig normalizes out-of-range preferences")
func dockConfigNormalizesPreferences() {
    let config = DockConfig(
        name: "Extreme",
        iconSize: 500,
        magnification: 0.2,
        itemSpacing: -4,
        surfaceOpacity: 0,
        cornerRadius: 100,
        shadowStrength: 9,
        autoHideDelay: 0
    )

    #expect(config.iconSize == DockConfig.iconSizeRange.upperBound)
    #expect(config.magnification == DockConfig.magnificationRange.lowerBound)
    #expect(config.itemSpacing == DockConfig.itemSpacingRange.lowerBound)
    #expect(config.surfaceOpacity == DockConfig.surfaceOpacityRange.lowerBound)
    #expect(config.cornerRadius == DockConfig.cornerRadiusRange.upperBound)
    #expect(config.shadowStrength == DockConfig.shadowStrengthRange.upperBound)
    #expect(config.autoHideDelay == DockConfig.autoHideDelayRange.lowerBound)
}

@Test("Duplicating a dock preserves settings with fresh identities")
func dockConfigDuplicate() {
    let original = DockConfig(
        name: "Original",
        position: CGPoint(x: 10, y: 20),
        orientation: .vertical,
        iconSize: 72,
        items: [
            DockItem(appPath: "/Applications/Test.app", label: "Test"),
            .separator(),
        ],
        autoHideWhenDocked: false,
        magnificationEnabled: false,
        magnification: 1.5,
        itemSpacing: 8,
        appearance: .dark,
        surfaceOpacity: 0.55,
        blurStyle: .light,
        cornerRadius: 22,
        shadowStrength: 1.8,
        showRunningIndicators: false,
        autoHideDelay: 2
    )

    let duplicate = original.duplicated(
        name: "Original Copy",
        position: CGPoint(x: 42, y: 20)
    )

    #expect(duplicate.id != original.id)
    #expect(duplicate.name == "Original Copy")
    #expect(duplicate.position == CGPoint(x: 42, y: 20))
    #expect(duplicate.orientation == original.orientation)
    #expect(duplicate.iconSize == original.iconSize)
    #expect(duplicate.autoHideWhenDocked == original.autoHideWhenDocked)
    #expect(duplicate.magnificationEnabled == original.magnificationEnabled)
    #expect(duplicate.magnification == original.magnification)
    #expect(duplicate.itemSpacing == original.itemSpacing)
    #expect(duplicate.appearance == original.appearance)
    #expect(duplicate.surfaceOpacity == original.surfaceOpacity)
    #expect(duplicate.blurStyle == original.blurStyle)
    #expect(duplicate.cornerRadius == original.cornerRadius)
    #expect(duplicate.shadowStrength == original.shadowStrength)
    #expect(duplicate.showRunningIndicators == original.showRunningIndicators)
    #expect(duplicate.autoHideDelay == original.autoHideDelay)
    #expect(duplicate.items.map(\.id) != original.items.map(\.id))
    #expect(duplicate.items.map(\.appPath) == original.items.map(\.appPath))
    #expect(duplicate.items.map(\.isSeparator) == original.items.map(\.isSeparator))
}

@Test("Applying dock settings preserves dock content and placement")
func dockConfigApplySettings() {
    let source = DockConfig(
        name: "Source",
        orientation: .vertical,
        iconSize: 88,
        autoHideWhenDocked: false,
        magnificationEnabled: false,
        magnification: 1.6,
        itemSpacing: 12,
        appearance: .light,
        surfaceOpacity: 0.7,
        blurStyle: .strong,
        cornerRadius: 26,
        shadowStrength: 1.4,
        showRunningIndicators: false,
        autoHideDelay: 3
    )
    var target = DockConfig(
        name: "Target",
        position: CGPoint(x: 80, y: 120),
        items: [DockItem(appPath: "/Applications/Target.app")]
    )
    let originalID = target.id
    let originalItems = target.items
    let originalPosition = target.position

    target.apply(settings: source.settings)

    #expect(target.id == originalID)
    #expect(target.name == "Target")
    #expect(target.items == originalItems)
    #expect(target.position == originalPosition)
    #expect(target.settings == source.settings)
}

@Test("Unknown dock appearance falls back to glass")
func dockConfigUnknownAppearanceFallback() throws {
    let data = """
    {
      "id": "F8CCF00C-3001-4D86-B572-1B5E4B5DBFEA",
      "name": "Future Dock",
      "position": [40, 80],
      "orientation": "horizontal",
      "iconSize": 48,
      "items": [],
      "appearance": "future-material",
      "blurStyle": "future-blur"
    }
    """.data(using: .utf8)!

    let decoded = try JSONDecoder().decode(DockConfig.self, from: data)
    #expect(decoded.appearance == .glass)
    #expect(decoded.blurStyle == .regular)
}

@Test("AppConfig holds multiple docks")
func appConfigMultiple() throws {
    let config = AppConfig(docks: [
        DockConfig(name: "A"),
        DockConfig(name: "B")
    ])
    let data = try JSONEncoder().encode(config)
    let decoded = try JSONDecoder().decode(AppConfig.self, from: data)
    #expect(decoded.docks.count == 2)
}

@Test("Legacy top-level docks migrate into a default profile")
func appConfigMigratesLegacyDocks() throws {
    let dockID = UUID()
    let legacy = """
    {
      "docks": [
        {
          "id": "\(dockID.uuidString)",
          "name": "Legacy",
          "position": [12, 34],
          "orientation": "vertical",
          "iconSize": 64,
          "items": [],
          "autoHideWhenDocked": false
        }
      ]
    }
    """.data(using: .utf8)!

    let decoded = try JSONDecoder().decode(AppConfig.self, from: legacy)
    #expect(decoded.profiles.count == 1)
    #expect(decoded.activeProfileName == "Default")
    #expect(decoded.docks.count == 1)
    #expect(decoded.docks[0].id == dockID)
    #expect(decoded.docks[0].name == "Legacy")
}

@Test("Profiles round-trip with the active profile preserved")
func appConfigProfilesRoundTrip() throws {
    let work = DockProfile(name: "Work", docks: [DockConfig(name: "Work Dock")])
    let personal = DockProfile(name: "Personal", docks: [DockConfig(name: "Personal Dock")])
    let config = AppConfig(profiles: [work, personal], activeProfileID: personal.id)

    let data = try JSONEncoder().encode(config)
    let decoded = try JSONDecoder().decode(AppConfig.self, from: data)

    #expect(decoded.profiles == [work, personal])
    #expect(decoded.activeProfileID == personal.id)
    #expect(decoded.docks.first?.name == "Personal Dock")
}

@Test("Invalid active profile falls back to the first profile")
func appConfigInvalidActiveProfileFallback() throws {
    let first = DockProfile(name: "First")
    let second = DockProfile(name: "Second")
    let config = AppConfig(profiles: [first, second], activeProfileID: first.id)
    let encoded = try JSONEncoder().encode(config)
    var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    object["activeProfileID"] = UUID().uuidString
    let data = try JSONSerialization.data(withJSONObject: object)

    let decoded = try JSONDecoder().decode(AppConfig.self, from: data)
    #expect(decoded.activeProfileID == first.id)
}

@Test("Empty profile collections normalize to a default profile")
func appConfigNormalizesEmptyProfiles() throws {
    let data = """
    {
      "formatVersion": 2,
      "profiles": [],
      "activeProfileID": "\(UUID().uuidString)"
    }
    """.data(using: .utf8)!

    let decoded = try JSONDecoder().decode(AppConfig.self, from: data)
    #expect(decoded.profiles.count == 1)
    #expect(decoded.activeProfileName == "Default")
    #expect(decoded.docks.isEmpty)
}

@Test("Profile data takes precedence over the compatibility dock mirror")
func appConfigProfilesWinOverLegacyMirror() throws {
    let profileDock = DockConfig(name: "Profile Dock")
    let profile = DockProfile(name: "Current", docks: [profileDock])
    let config = AppConfig(profiles: [profile], activeProfileID: profile.id)
    let encoded = try JSONEncoder().encode(config)
    var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    let mirrorData = try JSONEncoder().encode([DockConfig(name: "Stale Mirror")])
    object["docks"] = try JSONSerialization.jsonObject(with: mirrorData)
    let data = try JSONSerialization.data(withJSONObject: object)

    let decoded = try JSONDecoder().decode(AppConfig.self, from: data)
    #expect(decoded.docks.first?.name == "Profile Dock")
}

@Test("Mutating docks only changes the active profile")
func appConfigActiveDockWriteback() {
    let first = DockProfile(name: "First", docks: [DockConfig(name: "A")])
    let second = DockProfile(name: "Second", docks: [DockConfig(name: "B")])
    var config = AppConfig(profiles: [first, second], activeProfileID: second.id)

    config.docks[0].name = "Updated"

    #expect(config.profiles[0].docks[0].name == "A")
    #expect(config.profiles[1].docks[0].name == "Updated")
}

@Test("Encoded profiles include an active-dock compatibility mirror")
func appConfigEncodesCompatibilityMirror() throws {
    let profile = DockProfile(name: "Work", docks: [DockConfig(name: "Visible")])
    let config = AppConfig(profiles: [profile], activeProfileID: profile.id)
    let data = try JSONEncoder().encode(config)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let mirroredDocks = try #require(object["docks"] as? [[String: Any]])

    #expect(object["formatVersion"] as? Int == AppConfig.currentFormatVersion)
    #expect(mirroredDocks.first?["name"] as? String == "Visible")
}

@Test("Empty config is valid")
func emptyConfig() throws {
    let config = AppConfig(docks: [])
    let data = try JSONEncoder().encode(config)
    let decoded = try JSONDecoder().decode(AppConfig.self, from: data)
    #expect(decoded.docks.isEmpty)
}

@Test("Orientation raw values")
func orientationRawValues() {
    #expect(Orientation.horizontal.rawValue == "horizontal")
    #expect(Orientation.vertical.rawValue == "vertical")
}

@Test("Global shortcuts provide unique keys for nine profiles")
func globalShortcutProfileKeys() {
    #expect(GlobalShortcutManager.profileKeyCodes.count == 9)
    #expect(Set(GlobalShortcutManager.profileKeyCodes).count == 9)
    #expect(GlobalShortcutManager.standardModifiers != 0)
}

@MainActor
@Test("Dock state applies advanced appearance changes")
func dockStateAppliesAdvancedAppearance() {
    let state = DockState(config: DockConfig(name: "Initial"))
    let updated = DockConfig(
        name: "Updated",
        magnificationEnabled: false,
        magnification: 1.65,
        appearance: .dark,
        surfaceOpacity: 0.55,
        blurStyle: .strong,
        cornerRadius: 28,
        shadowStrength: 1.75
    )

    state.apply(updated)

    #expect(!state.magnificationEnabled)
    #expect(state.magnification == 1.65)
    #expect(state.appearance == .dark)
    #expect(state.surfaceOpacity == 0.55)
    #expect(state.blurStyle == .strong)
    #expect(state.cornerRadius == 28)
    #expect(state.shadowStrength == 1.75)
}

@MainActor
@Test("Preferences keep selection by dock ID and clamp live changes")
func preferencesStoreSelectionAndUpdates() {
    let first = DockConfig(name: "First")
    let second = DockConfig(name: "Second")
    var received: (UUID, DockPreferenceChange)?
    var managementAction: DockManagementAction?
    let profileID = UUID()
    let workProfile = DockProfile(id: profileID, name: "Work", docks: [first, second])
    let store = DockPreferencesStore(
        profiles: [workProfile],
        activeProfileID: profileID
    ) { dockID, change in
        received = (dockID, change)
    } onManagementAction: { action in
        managementAction = action
    }
    #expect(store.activeProfileName == "Work")
    #expect(!store.canDeleteActiveProfile)
    #expect(store.canCopySelectedDockSettings)

    store.selectedDockID = second.id
    store.reload(
        profiles: [
            DockProfile(
                id: profileID,
                name: "Work",
                docks: [
                    DockConfig(id: first.id, name: "First"),
                    DockConfig(id: second.id, name: "Renamed"),
                ]
            ),
        ],
        activeProfileID: profileID
    )
    #expect(store.selectedDockID == second.id)

    store.updateSelected(.magnification(9))
    #expect(store.selectedDock?.magnification == DockConfig.magnificationRange.upperBound)
    #expect(received?.0 == second.id)
    #expect(received?.1 == .magnification(9))

    store.updateSelected(.magnificationEnabled(false))
    store.updateSelected(.surfaceOpacity(0))
    store.updateSelected(.blurStyle(.strong))
    store.updateSelected(.shadowStrength(9))
    #expect(store.selectedDock?.magnificationEnabled == false)
    #expect(store.selectedDock?.surfaceOpacity == DockConfig.surfaceOpacityRange.lowerBound)
    #expect(store.selectedDock?.blurStyle == .strong)
    #expect(store.selectedDock?.shadowStrength == DockConfig.shadowStrengthRange.upperBound)
    #expect(received?.1 == .shadowStrength(9))

    store.perform(.importSystemDockApps(second.id))
    #expect(managementAction == .importSystemDockApps(second.id))

    let replacement = DockConfig(name: "Personal Dock")
    let personalProfile = DockProfile(name: "Personal", docks: [replacement])
    store.reload(
        profiles: [workProfile, personalProfile],
        activeProfileID: personalProfile.id
    )
    #expect(store.selectedDockID == replacement.id)
    #expect(store.activeProfileName == "Personal")
    #expect(store.canDeleteActiveProfile)
    #expect(!store.canCopySelectedDockSettings)

    store.perform(.copyDockSettingsToAll(replacement.id))
    #expect(managementAction == .copyDockSettingsToAll(replacement.id))
}
