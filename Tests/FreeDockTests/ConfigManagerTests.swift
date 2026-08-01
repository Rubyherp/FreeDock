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

@Test("ConfigManager keeps three rotating backup generations")
func rotatingBackups() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("fd-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
        at: tempDir,
        withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let path = tempDir.appendingPathComponent("freedock.json")
    let manager = ConfigManager(configPath: path)
    for version in 1...4 {
        manager.config = AppConfig(docks: [
            DockConfig(name: "v\(version)"),
        ])
        manager.saveImmediately()
    }

    let names = try [".bak", ".bak.1", ".bak.2"].map { suffix in
        let data = try Data(contentsOf: URL(fileURLWithPath: path.path + suffix))
        return try ConfigFileCodec.decode(data).docks[0].name
    }
    #expect(names == ["v3", "v2", "v1"])
}

@Test("ConfigManager recovers from the newest valid backup")
func recoversFromBackup() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("fd-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
        at: tempDir,
        withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let path = tempDir.appendingPathComponent("freedock.json")
    let manager = ConfigManager(configPath: path)
    manager.config = AppConfig(docks: [DockConfig(name: "Working")])
    manager.saveImmediately()
    manager.config = AppConfig(docks: [DockConfig(name: "Current")])
    manager.saveImmediately()
    try Data("not json".utf8).write(to: path)

    let recovered = ConfigManager(configPath: path)
    #expect(recovered.loadedFromDisk)
    #expect(recovered.loadSource == .backup(0))
    #expect(recovered.config.docks[0].name == "Working")
}

@Test("ConfigManager skips corrupt backup generations")
func skipsCorruptBackups() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("fd-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
        at: tempDir,
        withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let path = tempDir.appendingPathComponent("freedock.json")
    let manager = ConfigManager(configPath: path)
    for version in 1...3 {
        manager.config = AppConfig(docks: [DockConfig(name: "v\(version)")])
        manager.saveImmediately()
    }
    try Data("corrupt primary".utf8).write(to: path)
    try Data("corrupt newest backup".utf8).write(
        to: URL(fileURLWithPath: path.path + ".bak")
    )

    let recovered = ConfigManager(configPath: path)
    #expect(recovered.loadSource == .backup(1))
    #expect(recovered.config.docks[0].name == "v1")
}

@Test("Saving after corruption preserves the valid backup")
func corruptPrimaryIsNotRotated() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("fd-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
        at: tempDir,
        withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let path = tempDir.appendingPathComponent("freedock.json")
    let manager = ConfigManager(configPath: path)
    manager.config = AppConfig(docks: [DockConfig(name: "Safe")])
    manager.saveImmediately()
    manager.config = AppConfig(docks: [DockConfig(name: "Current")])
    manager.saveImmediately()
    try Data("corrupt".utf8).write(to: path)

    let recovered = ConfigManager(configPath: path)
    recovered.saveImmediately()

    let backup = try ConfigFileCodec.decode(Data(
        contentsOf: URL(fileURLWithPath: path.path + ".bak")
    ))
    #expect(backup.docks[0].name == "Safe")
    #expect(ConfigManager.load(from: path).docks[0].name == "Safe")
}

@Test("Manual restore persists the latest working backup")
func manualRestore() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("fd-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
        at: tempDir,
        withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let path = tempDir.appendingPathComponent("freedock.json")
    let manager = ConfigManager(configPath: path)
    manager.config = AppConfig(docks: [DockConfig(name: "Previous")])
    manager.saveImmediately()
    manager.config = AppConfig(docks: [DockConfig(name: "Current")])
    manager.saveImmediately()

    #expect(manager.restoreLatestBackup())
    #expect(manager.config.docks[0].name == "Previous")
    #expect(ConfigManager.load(from: path).docks[0].name == "Previous")
}

@Test("ConfigManager creates a missing configuration directory")
func createsMissingDirectory() {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("fd-test-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let path = tempDir
        .appendingPathComponent("nested")
        .appendingPathComponent("freedock.json")
    let manager = ConfigManager(configPath: path)
    manager.config = AppConfig(docks: [DockConfig(name: "Saved")])
    manager.saveImmediately()

    #expect(FileManager.default.fileExists(atPath: path.path))
    #expect(ConfigManager.load(from: path).docks[0].name == "Saved")
}
