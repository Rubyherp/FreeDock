import Testing
import Foundation
@testable import FreeDock

@Test("ConfigManager saves and reloads config")
func saveAndLoad() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("fd-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let path = tempDir.appendingPathComponent("freedock.json")
    let mgr = ConfigManager(configPath: path)
    #expect(!mgr.loadedFromDisk)
    mgr.config = AppConfig(docks: [DockConfig(name: "Saved")])
    mgr.save()
    mgr.saveImmediately()

    let loader = ConfigManager(configPath: path)
    #expect(loader.loadedFromDisk)
    #expect(loader.config.docks.count == 1)
    #expect(loader.config.docks[0].name == "Saved")
}

@Test("Backup file is created on save")
func backupCreated() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("fd-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let path = tempDir.appendingPathComponent("freedock.json")
    let backupPath = tempDir.appendingPathComponent("freedock.json.bak")

    let mgr = ConfigManager(configPath: path)
    mgr.config = AppConfig(docks: [DockConfig(name: "v1")])
    mgr.saveImmediately()
    mgr.config = AppConfig(docks: [DockConfig(name: "v2")])
    mgr.saveImmediately()

    let backupData = try Data(contentsOf: backupPath)
    let backup = try JSONDecoder().decode(AppConfig.self, from: backupData)
    #expect(backup.docks[0].name == "v1")
}

@Test("Load returns empty config for missing file")
func missingFile() {
    let path = FileManager.default.temporaryDirectory.appendingPathComponent("fd-nonexistent-\(UUID().uuidString).json")
    let mgr = ConfigManager(configPath: path)
    #expect(!mgr.loadedFromDisk)
    #expect(mgr.config.docks.isEmpty)
}
