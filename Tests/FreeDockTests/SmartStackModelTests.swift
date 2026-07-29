import Foundation
import Testing
@testable import FreeDock

@Test("Smart stack factories use source-specific defaults and dynamic paths")
func smartStackFactoryDefaults() {
    let recent = DockItem.recentFilesStack()
    let downloads = DockItem.downloadsStack()
    let normalFolder = DockItem(
        kind: .folder,
        path: "/Users/example/Projects",
        label: "Projects"
    )

    #expect(recent.kind == .folder)
    #expect(recent.smartStackSource == .recentFiles)
    #expect(recent.path.isEmpty)
    #expect(recent.fileURL == nil)
    #expect(recent.label == "Recent Files")
    #expect(recent.folderOptions == FolderStackOptions(
        presentation: .list,
        sortOrder: .recentlyOpened
    ))

    #expect(downloads.kind == .folder)
    #expect(downloads.smartStackSource == .downloads)
    #expect(downloads.path.isEmpty)
    #expect(downloads.label == "Downloads")
    #expect(downloads.folderOptions == FolderStackOptions(
        presentation: .automatic,
        sortOrder: .dateModified
    ))

    #expect(normalFolder.smartStackSource == nil)
    #expect(normalFolder.path == "/Users/example/Projects")
    #expect(normalFolder.folderOptions == FolderStackOptions())
}

@Test("Smart stacks round-trip compatibly and duplicate with fresh identities")
func smartStackCodableAndDuplication() throws {
    let options = FolderStackOptions(
        presentation: .grid,
        sortOrder: .kind,
        showHiddenFiles: true
    )
    let original = DockItem.downloadsStack(
        label: "Incoming",
        options: options
    )
    let data = try JSONEncoder().encode(original)
    let object = try #require(
        JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
    let decoded = try JSONDecoder().decode(DockItem.self, from: data)
    let duplicate = original.duplicated()

    #expect(decoded == original)
    #expect(object["kind"] as? String == "folder")
    #expect(object["smartStackSource"] as? String == "downloads")
    #expect(object["path"] as? String == "")
    #expect(object["appPath"] as? String == "")
    #expect(object["isSeparator"] as? Bool == false)
    #expect(duplicate.id != original.id)
    #expect(duplicate.smartStackSource == original.smartStackSource)
    #expect(duplicate.folderOptions == options)
    #expect(duplicate.label == "Incoming")
}

@Test("Legacy and unknown folder sources remain normal folders")
func smartStackSourceMigrationFallback() throws {
    let legacyData = """
    {
      "id": "\(UUID().uuidString)",
      "path": "/Users/example/Projects",
      "appPath": "/Users/example/Projects",
      "kind": "folder",
      "isSeparator": false
    }
    """.data(using: .utf8)!
    let legacy = try JSONDecoder().decode(DockItem.self, from: legacyData)

    #expect(legacy.kind == .folder)
    #expect(legacy.smartStackSource == nil)
    #expect(legacy.path == "/Users/example/Projects")
    #expect(legacy.folderOptions == FolderStackOptions())

    let unknownData = """
    {
      "id": "\(UUID().uuidString)",
      "path": "/Users/example/Archive",
      "appPath": "/Users/example/Archive",
      "kind": "folder",
      "smartStackSource": "future-cloud-files",
      "isSeparator": false
    }
    """.data(using: .utf8)!
    let unknown = try JSONDecoder().decode(DockItem.self, from: unknownData)

    #expect(unknown.smartStackSource == nil)
    #expect(unknown.path == "/Users/example/Archive")
}

@Test("App config persists bounded recent history and migrates older data")
func appConfigRecentFilePersistence() throws {
    let records = (0 ..< 110).map { index in
        RecentFileRecord(
            path: "/tmp/Recent-\(index).txt",
            displayName: "Recent \(index)",
            lastOpenedAt: Date(timeIntervalSince1970: Double(index))
        )
    }
    let config = AppConfig(docks: [], recentFiles: records)
    let data = try JSONEncoder().encode(config)
    let object = try #require(
        JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
    let decoded = try JSONDecoder().decode(AppConfig.self, from: data)

    #expect(config.recentFiles.count == RecentFileHistoryPlanner.maximumLimit)
    #expect(decoded.recentFiles == config.recentFiles)
    #expect(object["formatVersion"] as? Int == 4)
    #expect((object["recentFiles"] as? [[String: Any]])?.count == 100)

    let legacyData = """
    {
      "formatVersion": 3,
      "docks": []
    }
    """.data(using: .utf8)!
    let legacy = try JSONDecoder().decode(AppConfig.self, from: legacyData)
    #expect(legacy.recentFiles.isEmpty)
}

@Test("Recent history accepts only existing local documents")
func recentFileHistoryLocalDocumentsOnly() throws {
    let temporaryDirectory = try makeSmartStackTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    let documentURL = temporaryDirectory.appendingPathComponent("Notes.txt")
    let folderURL = temporaryDirectory.appendingPathComponent("Folder")
    let applicationURL = temporaryDirectory.appendingPathComponent("Example.app")
    try Data("notes".utf8).write(to: documentURL)
    try FileManager.default.createDirectory(
        at: folderURL,
        withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
        at: applicationURL,
        withIntermediateDirectories: true
    )

    let accepted = RecentFileHistoryPlanner.planRecording(
        url: documentURL,
        displayName: "  My Notes  ",
        openedAt: Date(timeIntervalSince1970: 10),
        records: []
    )
    #expect(accepted.didRecord)
    #expect(accepted.records.count == 1)
    #expect(accepted.records.first?.displayName == "My Notes")

    for rejectedURL in [
        folderURL,
        applicationURL,
        temporaryDirectory.appendingPathComponent("Missing.txt"),
        URL(string: "https://example.com/file.txt")!,
    ] {
        let rejected = RecentFileHistoryPlanner.planRecording(
            url: rejectedURL,
            records: accepted.records
        )
        #expect(!rejected.didRecord)
        #expect(rejected.records == accepted.records)
    }
}

@Test("Recent history deduplicates canonical paths and moves reopened files")
func recentFileHistoryCanonicalDeduplication() throws {
    let temporaryDirectory = try makeSmartStackTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    let targetURL = temporaryDirectory.appendingPathComponent("Document.txt")
    let aliasURL = temporaryDirectory.appendingPathComponent("Document Alias.txt")
    try Data("document".utf8).write(to: targetURL)
    try FileManager.default.createSymbolicLink(
        at: aliasURL,
        withDestinationURL: targetURL
    )
    let firstDate = Date(timeIntervalSince1970: 10)
    let secondDate = Date(timeIntervalSince1970: 20)

    let first = RecentFileHistoryPlanner.planRecording(
        url: targetURL,
        openedAt: firstDate,
        records: []
    )
    let second = RecentFileHistoryPlanner.planRecording(
        url: aliasURL,
        openedAt: secondDate,
        records: first.records
    )

    #expect(second.didRecord)
    #expect(second.records.count == 1)
    #expect(second.records.first?.path == aliasURL.standardizedFileURL.path)
    #expect(second.records.first?.lastOpenedAt == secondDate)
}

@Test("Recent history defaults to 50 and never exceeds 100 records")
func recentFileHistoryCapsAndOrdering() {
    let records = (0 ..< 120).map { index in
        RecentFileRecord(
            path: "/tmp/History-\(index).txt",
            lastOpenedAt: Date(timeIntervalSince1970: Double(index))
        )
    }

    let defaultHistory = RecentFileHistoryPlanner.normalized(records)
    let hardCappedHistory = RecentFileHistoryPlanner.normalized(
        records,
        limit: 1_000
    )

    #expect(defaultHistory.count == 50)
    #expect(defaultHistory.first?.path == "/tmp/History-119.txt")
    #expect(defaultHistory.last?.path == "/tmp/History-70.txt")
    #expect(hardCappedHistory.count == 100)
    #expect(hardCappedHistory.last?.path == "/tmp/History-20.txt")
}

@Test("Smart stack planner rejects source and Downloads-folder duplicates per dock")
func smartStackAdditionPlanning() throws {
    let temporaryDirectory = try makeSmartStackTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let downloadsURL = temporaryDirectory.appendingPathComponent("Downloads")
    let downloadsAliasURL = temporaryDirectory
        .appendingPathComponent("Downloads Alias")
    try FileManager.default.createDirectory(
        at: downloadsURL,
        withIntermediateDirectories: true
    )
    try FileManager.default.createSymbolicLink(
        at: downloadsAliasURL,
        withDestinationURL: downloadsURL
    )

    let addRecent = DockItemPlanner.planAdding(
        smartStack: .recentFiles,
        to: [],
        downloadsURL: downloadsURL
    )
    let repeatRecent = DockItemPlanner.planAdding(
        smartStack: .recentFiles,
        to: addRecent.items,
        downloadsURL: downloadsURL
    )
    #expect(addRecent.addedCount == 1)
    #expect(addRecent.items.last?.smartStackSource == .recentFiles)
    #expect(repeatRecent.addedCount == 0)
    #expect(repeatRecent.skippedCount == 1)

    let normalDownloads = try #require(
        DockItem.pinnedItem(at: downloadsAliasURL)
    )
    let smartAfterFolder = DockItemPlanner.planAdding(
        smartStack: .downloads,
        to: [normalDownloads],
        downloadsURL: downloadsURL
    )
    #expect(smartAfterFolder.addedCount == 0)
    #expect(smartAfterFolder.skippedCount == 1)

    let normalAfterSmart = DockItemPlanner.planAdding(
        urls: [downloadsAliasURL],
        to: [.downloadsStack()],
        downloadsURL: downloadsURL
    )
    #expect(normalAfterSmart.addedCount == 0)
    #expect(normalAfterSmart.skippedCount == 1)

    let sameSourceInAnotherDock = DockItemPlanner.planAdding(
        smartStack: .downloads,
        to: [],
        downloadsURL: downloadsURL
    )
    #expect(sameSourceInAnotherDock.addedCount == 1)
}

@Test("Recent smart stack snapshots omit stale and hidden records")
func recentSmartStackSnapshot() throws {
    let temporaryDirectory = try makeSmartStackTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    let olderURL = temporaryDirectory.appendingPathComponent("Older.txt")
    let newerURL = temporaryDirectory.appendingPathComponent("Newer.txt")
    let hiddenURL = temporaryDirectory.appendingPathComponent(".Hidden.txt")
    let missingURL = temporaryDirectory.appendingPathComponent("Missing.txt")
    try Data("older".utf8).write(to: olderURL)
    try Data("newer".utf8).write(to: newerURL)
    try Data("hidden".utf8).write(to: hiddenURL)
    let olderDate = Date(timeIntervalSince1970: 10)
    let newerDate = Date(timeIntervalSince1970: 20)
    let hiddenDate = Date(timeIntervalSince1970: 30)
    let records = [
        RecentFileRecord(
            path: olderURL.path,
            displayName: "Older Custom",
            lastOpenedAt: olderDate
        ),
        RecentFileRecord(
            path: newerURL.path,
            lastOpenedAt: newerDate
        ),
        RecentFileRecord(
            path: hiddenURL.path,
            lastOpenedAt: hiddenDate
        ),
        RecentFileRecord(
            path: missingURL.path,
            lastOpenedAt: Date(timeIntervalSince1970: 40)
        ),
    ]

    let snapshot = try FolderStackLoader.load(
        item: .recentFilesStack(),
        recentFiles: records
    )

    #expect(snapshot.totalCount == 2)
    #expect(snapshot.entries.map(\.url.lastPathComponent) == [
        "Newer.txt",
        "Older.txt",
    ])
    #expect(snapshot.entries.map(\.recentlyOpenedAt) == [
        newerDate,
        olderDate,
    ])
    #expect(snapshot.entries.last?.name == "Older Custom")

    let showingHidden = try FolderStackLoader.load(
        item: .recentFilesStack(
            options: FolderStackOptions(
                presentation: .list,
                sortOrder: .recentlyOpened,
                showHiddenFiles: true
            )
        ),
        recentFiles: records
    )
    #expect(showingHidden.totalCount == 3)
    #expect(showingHidden.entries.first?.url.lastPathComponent == ".Hidden.txt")
}

@Test("Downloads smart stacks resolve dynamically and preserve folder loading")
func downloadsSmartStackSnapshot() throws {
    let downloadsURL = try makeSmartStackTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: downloadsURL) }

    let olderURL = downloadsURL.appendingPathComponent("Older.txt")
    let newerURL = downloadsURL.appendingPathComponent("Newer.txt")
    try Data("older".utf8).write(to: olderURL)
    try Data("newer".utf8).write(to: newerURL)
    try FileManager.default.setAttributes(
        [.modificationDate: Date(timeIntervalSince1970: 10)],
        ofItemAtPath: olderURL.path
    )
    try FileManager.default.setAttributes(
        [.modificationDate: Date(timeIntervalSince1970: 20)],
        ofItemAtPath: newerURL.path
    )

    let downloads = try FolderStackLoader.load(
        item: .downloadsStack(),
        downloadsURL: downloadsURL
    )
    #expect(downloads.entries.map(\.name) == ["Newer.txt", "Older.txt"])
    #expect(downloads.entries.allSatisfy { $0.recentlyOpenedAt == nil })

    let normalFolder = DockItem.folder(at: downloadsURL)
    let unifiedFolderSnapshot = try FolderStackLoader.load(item: normalFolder)
    let originalFolderSnapshot = try FolderStackLoader.load(
        folderURL: downloadsURL,
        options: FolderStackOptions()
    )
    #expect(unifiedFolderSnapshot == originalFolderSnapshot)
}

private func makeSmartStackTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("freedock-smart-stack-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
        at: url,
        withIntermediateDirectories: true
    )
    return url
}
