import Foundation

struct DockProfileArchive: Codable, Equatable, Sendable {
    static let currentFormatVersion = 1

    var formatVersion: Int
    var profile: DockProfile
    var shortcut: GlobalShortcut?

    init(profile: DockProfile, shortcut: GlobalShortcut?) {
        formatVersion = Self.currentFormatVersion
        self.profile = profile
        self.shortcut = shortcut
    }

    func materializedProfile(named name: String) -> DockProfile {
        DockProfile(
            name: name,
            docks: profile.docks.map {
                $0.duplicated(name: $0.name, position: $0.position)
            },
            automationRules: profile.automationRules.map {
                ProfileAutomationRule(
                    triggerKind: $0.triggerKind,
                    value: $0.value,
                    label: $0.label,
                    isEnabled: $0.isEnabled
                )
            }
        )
    }
}

enum ProfileFileCodecError: LocalizedError, Equatable {
    case emptyFile
    case fileTooLarge
    case unsupportedVersion(Int)
    case duplicateDock
    case duplicateItem

    var errorDescription: String? {
        switch self {
        case .emptyFile:
            return "The selected profile file is empty."
        case .fileTooLarge:
            return "The selected profile file is too large."
        case let .unsupportedVersion(version):
            return "This profile uses unsupported format version \(version)."
        case .duplicateDock:
            return "The profile contains duplicate dock identifiers."
        case .duplicateItem:
            return "The profile contains duplicate dock-item identifiers."
        }
    }
}

enum ProfileFileCodec {
    static let maximumByteCount = ConfigFileCodec.maximumByteCount

    static func encode(_ archive: DockProfileArchive) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(archive)
    }

    static func decode(_ data: Data) throws -> DockProfileArchive {
        guard !data.isEmpty else { throw ProfileFileCodecError.emptyFile }
        guard data.count <= maximumByteCount else {
            throw ProfileFileCodecError.fileTooLarge
        }
        let archive = try JSONDecoder().decode(DockProfileArchive.self, from: data)
        guard archive.formatVersion <= DockProfileArchive.currentFormatVersion else {
            throw ProfileFileCodecError.unsupportedVersion(archive.formatVersion)
        }
        let dockIDs = archive.profile.docks.map(\.id)
        guard Set(dockIDs).count == dockIDs.count else {
            throw ProfileFileCodecError.duplicateDock
        }
        let itemIDs = archive.profile.docks.flatMap { $0.items.map(\.id) }
        guard Set(itemIDs).count == itemIDs.count else {
            throw ProfileFileCodecError.duplicateItem
        }
        return archive
    }
}
