import Foundation
import OSLog

enum ConfigLoadSource: Equatable {
    case primary
    case backup(Int)
    case fresh
}

final class ConfigManager {
    static let backupGenerationCount = 3

    let configPath: URL
    let loadedFromDisk: Bool
    let loadSource: ConfigLoadSource
    private let backupPaths: [URL]
    private let queue = DispatchQueue(label: "com.freedock.config", qos: .utility)
    private var saveWorkItem: DispatchWorkItem?

    var config: AppConfig

    init(configPath: URL) {
        self.configPath = configPath
        backupPaths = Self.makeBackupPaths(for: configPath)

        let candidates: [(URL, ConfigLoadSource)] = [(configPath, .primary)]
            + backupPaths.enumerated().map { ($0.element, .backup($0.offset)) }
        if let loaded = candidates.lazy.compactMap({ url, source in
            Self.decodeConfig(at: url).map { ($0, source) }
        }).first {
            config = loaded.0
            loadSource = loaded.1
            loadedFromDisk = true
        } else {
            config = AppConfig()
            loadSource = .fresh
            loadedFromDisk = false
        }
    }

    static func load(from path: URL) -> AppConfig {
        decodeConfig(at: path) ?? AppConfig()
    }

    var hasRecoverableBackup: Bool {
        backupPaths.contains { Self.decodeConfig(at: $0) != nil }
    }

    func save() {
        saveWorkItem?.cancel()
        let snapshot = config
        let workItem = DispatchWorkItem { [weak self] in self?._save(snapshot) }
        saveWorkItem = workItem
        queue.asyncAfter(deadline: .now() + 0.5, execute: workItem)
    }

    func saveImmediately() {
        saveWorkItem?.cancel()
        let snapshot = config
        queue.sync { [weak self] in self?._save(snapshot) }
    }

    @discardableResult
    func restoreLatestBackup() -> Bool {
        saveWorkItem?.cancel()
        guard let restored = backupPaths.lazy.compactMap({
            Self.decodeConfig(at: $0)
        }).first else { return false }
        config = restored
        queue.sync { [weak self] in self?._save(restored) }
        return true
    }

    private func _save(_ config: AppConfig) {
        let performanceInterval = PerformanceTrace.begin("ConfigSave")
        defer { PerformanceTrace.end(performanceInterval) }
        do {
            let data = try ConfigFileCodec.encode(config)
            try FileManager.default.createDirectory(
                at: configPath.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if Self.decodeConfig(at: configPath) != nil {
                try rotateBackups()
            }
            try data.write(to: configPath, options: .atomic)
        } catch {
            os_log(
                .error,
                "[FreeDock] Config save error: %{public}@",
                error.localizedDescription
            )
        }
    }

    private func rotateBackups() throws {
        let fileManager = FileManager.default
        if let oldest = backupPaths.last,
           fileManager.fileExists(atPath: oldest.path)
        {
            try fileManager.removeItem(at: oldest)
        }
        if backupPaths.count > 1 {
            for index in stride(
                from: backupPaths.count - 1,
                through: 1,
                by: -1
            ) {
                let source = backupPaths[index - 1]
                let destination = backupPaths[index]
                if fileManager.fileExists(atPath: source.path) {
                    try fileManager.moveItem(at: source, to: destination)
                }
            }
        }
        try fileManager.copyItem(at: configPath, to: backupPaths[0])
    }

    private static func decodeConfig(at url: URL) -> AppConfig? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? ConfigFileCodec.decode(data)
    }

    private static func makeBackupPaths(for configPath: URL) -> [URL] {
        let directory = configPath.deletingLastPathComponent()
        let name = configPath.lastPathComponent
        return (0..<backupGenerationCount).map { generation in
            let suffix = generation == 0 ? ".bak" : ".bak.\(generation)"
            return directory.appendingPathComponent(name + suffix)
        }
    }
}
