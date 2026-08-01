import Foundation

enum ConfigFileCodecError: LocalizedError, Equatable {
    case emptyFile
    case fileTooLarge
    case unsupportedVersion(Int)
    case duplicateProfile
    case duplicateDock

    var errorDescription: String? {
        switch self {
        case .emptyFile:
            return "The selected file is empty."
        case .fileTooLarge:
            return "The selected file is too large to be a FreeDock configuration."
        case let .unsupportedVersion(version):
            return "This configuration uses format version \(version), which this version of FreeDock cannot import."
        case .duplicateProfile:
            return "The configuration contains duplicate profile identifiers."
        case .duplicateDock:
            return "The configuration contains duplicate dock identifiers."
        }
    }
}

enum ConfigFileCodec {
    static let maximumByteCount = 5 * 1_024 * 1_024

    private struct Header: Decodable {
        let formatVersion: Int?
    }

    static func encode(_ config: AppConfig) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(config)
    }

    static func decode(_ data: Data) throws -> AppConfig {
        guard !data.isEmpty else {
            throw ConfigFileCodecError.emptyFile
        }
        guard data.count <= maximumByteCount else {
            throw ConfigFileCodecError.fileTooLarge
        }

        let decoder = JSONDecoder()
        let header = try decoder.decode(Header.self, from: data)
        if let version = header.formatVersion,
           version > AppConfig.currentFormatVersion
        {
            throw ConfigFileCodecError.unsupportedVersion(version)
        }

        let config = try decoder.decode(AppConfig.self, from: data)
        let profileIDs = config.profiles.map(\.id)
        guard Set(profileIDs).count == profileIDs.count else {
            throw ConfigFileCodecError.duplicateProfile
        }

        let dockIDs = config.profiles.flatMap { $0.docks.map(\.id) }
        guard Set(dockIDs).count == dockIDs.count else {
            throw ConfigFileCodecError.duplicateDock
        }
        return config
    }
}
