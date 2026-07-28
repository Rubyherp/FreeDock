import Foundation
import OSLog

class ConfigManager {
    let configPath: URL
    let loadedFromDisk: Bool
    private let backupPath: URL
    private let queue = DispatchQueue(label: "com.freedock.config", qos: .utility)
    private var saveWorkItem: DispatchWorkItem?

    var config: AppConfig

    init(configPath: URL) {
        self.configPath = configPath
        self.backupPath = configPath.deletingLastPathComponent()
            .appendingPathComponent(configPath.lastPathComponent + ".bak")
        if let data = try? Data(contentsOf: configPath),
           let decoded = try? JSONDecoder().decode(AppConfig.self, from: data)
        {
            self.config = decoded
            self.loadedFromDisk = true
        } else {
            self.config = AppConfig()
            self.loadedFromDisk = false
        }
    }

    static func load(from path: URL) -> AppConfig {
        guard let data = try? Data(contentsOf: path),
              let config = try? JSONDecoder().decode(AppConfig.self, from: data)
        else { return AppConfig() }
        return config
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

    private func _save(_ config: AppConfig) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(config)
            if FileManager.default.fileExists(atPath: configPath.path) {
                try? FileManager.default.removeItem(at: backupPath)
                try FileManager.default.copyItem(at: configPath, to: backupPath)
            }
            try data.write(to: configPath, options: .atomic)
        } catch {
            os_log(.error, "[FreeDock] Config save error: %{public}@", error.localizedDescription)
        }
    }
}
