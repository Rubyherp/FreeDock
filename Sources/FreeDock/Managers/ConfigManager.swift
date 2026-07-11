import Foundation
import OSLog

class ConfigManager {
    let configPath: URL
    private let backupPath: URL
    private let queue = DispatchQueue(label: "com.freedock.config", qos: .utility)
    private var saveWorkItem: DispatchWorkItem?

    var config: AppConfig

    init(configPath: URL) {
        self.configPath = configPath
        self.backupPath = configPath.deletingLastPathComponent()
            .appendingPathComponent(configPath.lastPathComponent + ".bak")
        self.config = Self.load(from: configPath)
    }

    static func load(from path: URL) -> AppConfig {
        guard let data = try? Data(contentsOf: path),
              let config = try? JSONDecoder().decode(AppConfig.self, from: data)
        else { return AppConfig() }
        return config
    }

    func save() {
        saveWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in self?._save() }
        saveWorkItem = workItem
        queue.asyncAfter(deadline: .now() + 0.5, execute: workItem)
    }

    func saveImmediately() {
        saveWorkItem?.cancel()
        queue.sync { [weak self] in self?._save() }
    }

    private func _save() {
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
