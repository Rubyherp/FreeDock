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
                            orientation: .vertical, iconSize: 64, items: [item])
    let data = try JSONEncoder().encode(config)
    let decoded = try JSONDecoder().decode(DockConfig.self, from: data)
    #expect(decoded.name == "Test")
    #expect(decoded.orientation == .vertical)
    #expect(decoded.iconSize == 64)
    #expect(decoded.items.count == 1)
    #expect(decoded.position == CGPoint(x: 100, y: 200))
    #expect(decoded.autoHideWhenDocked)
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
