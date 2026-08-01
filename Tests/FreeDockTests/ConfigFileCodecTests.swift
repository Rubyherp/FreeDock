import Foundation
import Testing
@testable import FreeDock

@Suite("Configuration file codec")
struct ConfigFileCodecTests {
    @Test("Portable configuration preserves profiles, docks, and history")
    func roundTrip() throws {
        let firstDock = DockConfig(name: "Work")
        let secondDock = DockConfig(name: "Reference")
        let firstProfile = DockProfile(name: "Office", docks: [firstDock])
        let secondProfile = DockProfile(name: "Research", docks: [secondDock])
        let recentURL = URL(fileURLWithPath: "/tmp/FreeDock Notes.txt")
        let record = RecentFileRecord(
            path: recentURL.path,
            displayName: "FreeDock Notes",
            lastOpenedAt: Date(timeIntervalSince1970: 42)
        )
        let config = AppConfig(
            profiles: [firstProfile, secondProfile],
            activeProfileID: secondProfile.id,
            recentFiles: [record],
            themes: [DockTheme(name: "Work Glass", dock: firstDock)]
        )

        let decoded = try ConfigFileCodec.decode(
            ConfigFileCodec.encode(config)
        )

        #expect(decoded.profiles.map { $0.name } == ["Office", "Research"])
        #expect(
            decoded.profiles.flatMap { $0.docks }.map { $0.name }
                == ["Work", "Reference"]
        )
        #expect(decoded.activeProfileID == secondProfile.id)
        #expect(decoded.recentFiles.compactMap { $0.fileURL } == [recentURL])
        #expect(decoded.themes.map(\.name) == ["Work Glass"])
    }

    @Test("Future configuration formats are rejected")
    func rejectsFutureVersion() throws {
        let data = Data("""
        {
          "formatVersion": \(AppConfig.currentFormatVersion + 1),
          "profiles": []
        }
        """.utf8)

        #expect(throws: ConfigFileCodecError.unsupportedVersion(
            AppConfig.currentFormatVersion + 1
        )) {
            try ConfigFileCodec.decode(data)
        }
    }

    @Test("Empty and oversized files are rejected before decoding")
    func rejectsInvalidSizes() {
        #expect(throws: ConfigFileCodecError.emptyFile) {
            try ConfigFileCodec.decode(Data())
        }
        #expect(throws: ConfigFileCodecError.fileTooLarge) {
            try ConfigFileCodec.decode(
                Data(count: ConfigFileCodec.maximumByteCount + 1)
            )
        }
    }

    @Test("Duplicate identifiers are rejected")
    func rejectsDuplicateIdentifiers() throws {
        let profileID = UUID()
        let dockID = UUID()
        let duplicateProfiles = AppConfig(
            profiles: [
                DockProfile(id: profileID, name: "One"),
                DockProfile(id: profileID, name: "Two")
            ]
        )
        #expect(throws: ConfigFileCodecError.duplicateProfile) {
            try ConfigFileCodec.decode(
                ConfigFileCodec.encode(duplicateProfiles)
            )
        }

        let duplicateDocks = AppConfig(
            profiles: [
                DockProfile(
                    name: "One",
                    docks: [DockConfig(id: dockID, name: "A")]
                ),
                DockProfile(
                    name: "Two",
                    docks: [DockConfig(id: dockID, name: "B")]
                )
            ]
        )
        #expect(throws: ConfigFileCodecError.duplicateDock) {
            try ConfigFileCodec.decode(
                ConfigFileCodec.encode(duplicateDocks)
            )
        }

        let themeID = UUID()
        let duplicateThemes = AppConfig(
            themes: [
                DockTheme(
                    id: themeID,
                    name: "One",
                    appearance: .glass,
                    surfaceOpacity: 1,
                    blurStyle: .regular,
                    cornerRadius: 18,
                    shadowStrength: 1
                ),
                DockTheme(
                    id: themeID,
                    name: "Two",
                    appearance: .dark,
                    surfaceOpacity: 0.8,
                    blurStyle: .strong,
                    cornerRadius: 22,
                    shadowStrength: 1.5
                ),
            ]
        )
        #expect(throws: ConfigFileCodecError.duplicateTheme) {
            try ConfigFileCodec.decode(
                ConfigFileCodec.encode(duplicateThemes)
            )
        }
    }
}
