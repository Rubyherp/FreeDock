import Foundation
import Testing
@testable import FreeDock

@Test("Legacy dock items decode as typed applications and separators")
func dockItemLegacyMigration() throws {
    let appID = UUID()
    let appData = """
    {
      "id": "\(appID.uuidString)",
      "appPath": "/Applications/Safari.app",
      "label": "Safari",
      "isSeparator": false
    }
    """.data(using: .utf8)!
    let app = try JSONDecoder().decode(DockItem.self, from: appData)

    #expect(app.id == appID)
    #expect(app.kind == .application)
    #expect(app.path == "/Applications/Safari.app")
    #expect(app.appPath == app.path)
    #expect(!app.isSeparator)
    #expect(app.folderOptions == nil)

    let separatorData = """
    {
      "id": "\(UUID().uuidString)",
      "appPath": "/a/legacy/value/that/must/be/ignored",
      "isSeparator": true
    }
    """.data(using: .utf8)!
    let separator = try JSONDecoder().decode(DockItem.self, from: separatorData)

    #expect(separator.kind == .separator)
    #expect(separator.path.isEmpty)
    #expect(separator.isSeparator)
}

@Test("Typed dock items round-trip while retaining legacy wire keys")
func typedDockItemsRoundTrip() throws {
    let options = FolderStackOptions(
        presentation: .list,
        sortOrder: .dateModified,
        showHiddenFiles: true
    )
    let items = [
        DockItem(
            kind: .application,
            path: "/Applications/FreeDock.app",
            label: "FreeDock"
        ),
        DockItem(
            kind: .document,
            path: "/Users/test/Notes.txt",
            label: "Notes"
        ),
        DockItem(
            kind: .folder,
            path: "/Users/test/Downloads",
            label: "Downloads",
            folderOptions: options
        ),
        DockItem.separator(),
    ]

    let data = try JSONEncoder().encode(items)
    let decoded = try JSONDecoder().decode([DockItem].self, from: data)
    let objects = try #require(
        JSONSerialization.jsonObject(with: data) as? [[String: Any]]
    )

    #expect(decoded == items)
    #expect(decoded[2].folderOptions == options)
    #expect(objects.allSatisfy { $0["path"] != nil })
    #expect(objects.allSatisfy { $0["appPath"] != nil })
    #expect(objects.allSatisfy { $0["isSeparator"] != nil })
    #expect(objects[2]["kind"] as? String == "folder")
}

@Test("Unknown item and folder option values migrate tolerantly")
func dockItemUnknownValueFallbacks() throws {
    let unknownKindData = """
    {
      "id": "\(UUID().uuidString)",
      "path": "/tmp/example",
      "appPath": "/tmp/stale",
      "kind": "future-smart-stack",
      "isSeparator": false
    }
    """.data(using: .utf8)!
    let unknownKind = try JSONDecoder().decode(
        DockItem.self,
        from: unknownKindData
    )

    #expect(unknownKind.kind == .application)
    #expect(unknownKind.path == "/tmp/example")

    let folderData = """
    {
      "id": "\(UUID().uuidString)",
      "path": "/tmp/folder",
      "kind": "folder",
      "isSeparator": false,
      "folderOptions": {
        "presentation": "future-carousel",
        "sortOrder": "future-relevance",
        "showHiddenFiles": "not-a-boolean"
      }
    }
    """.data(using: .utf8)!
    let folder = try JSONDecoder().decode(DockItem.self, from: folderData)

    #expect(folder.kind == .folder)
    #expect(folder.folderOptions == FolderStackOptions())
}

@Test("Pinning URLs classifies applications, folders, and documents")
func dockItemURLClassification() throws {
    let temporaryDirectory = try makeDockItemTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    let applicationURL = temporaryDirectory.appendingPathComponent("Example.app")
    let folderURL = temporaryDirectory.appendingPathComponent("Projects")
    let documentURL = temporaryDirectory.appendingPathComponent("Notes.txt")
    try FileManager.default.createDirectory(
        at: applicationURL,
        withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
        at: folderURL,
        withIntermediateDirectories: true
    )
    try Data("notes".utf8).write(to: documentURL)

    let application = try #require(DockItem.pinnedItem(at: applicationURL))
    let folder = try #require(DockItem.pinnedItem(at: folderURL))
    let document = try #require(DockItem.pinnedItem(at: documentURL))

    #expect(application.kind == .application)
    #expect(application.label == "Example")
    #expect(folder.kind == .folder)
    #expect(folder.folderOptions == FolderStackOptions())
    #expect(document.kind == .document)
    #expect(
        DockItem.pinnedItem(
            at: temporaryDirectory.appendingPathComponent("Missing")
        ) == nil
    )
    #expect(DockItem.pinnedItem(at: URL(string: "https://example.com")!) == nil)
}

@Test("Dock duplication preserves typed item metadata with fresh IDs")
func typedDockItemDuplication() {
    let options = FolderStackOptions(
        presentation: .grid,
        sortOrder: .kind,
        showHiddenFiles: true
    )
    let original = DockConfig(
        name: "Files",
        items: [
            DockItem(kind: .document, path: "/tmp/Brief.pdf", label: "Brief"),
            DockItem(
                kind: .folder,
                path: "/tmp/Project",
                label: "Project",
                folderOptions: options
            ),
            .separator(),
        ]
    )

    let duplicate = original.duplicated(name: "Files Copy", position: .zero)

    #expect(duplicate.items.map(\.id) != original.items.map(\.id))
    #expect(duplicate.items.map(\.kind) == original.items.map(\.kind))
    #expect(duplicate.items.map(\.path) == original.items.map(\.path))
    #expect(duplicate.items.map(\.label) == original.items.map(\.label))
    #expect(
        duplicate.items.map(\.folderOptions)
            == original.items.map(\.folderOptions)
    )
}

@Test("Dock item planner preserves URL order and skips repeated identities")
func dockItemPlannerOrderAndUniqueness() throws {
    let temporaryDirectory = try makeDockItemTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    let firstURL = temporaryDirectory.appendingPathComponent("First.txt")
    let secondURL = temporaryDirectory.appendingPathComponent("Second.txt")
    let folderURL = temporaryDirectory.appendingPathComponent("Folder")
    let firstAliasURL = temporaryDirectory.appendingPathComponent("First Alias.txt")
    let missingURL = temporaryDirectory.appendingPathComponent("Missing.txt")
    try Data("first".utf8).write(to: firstURL)
    try Data("second".utf8).write(to: secondURL)
    try FileManager.default.createDirectory(
        at: folderURL,
        withIntermediateDirectories: true
    )
    try FileManager.default.createSymbolicLink(
        at: firstAliasURL,
        withDestinationURL: firstURL
    )

    let existing = [
        try #require(DockItem.pinnedItem(at: firstURL)),
        DockItem.separator(),
    ]
    let plan = DockItemPlanner.planAdding(
        urls: [
            secondURL,
            folderURL,
            secondURL,
            firstAliasURL,
            missingURL,
        ],
        to: existing
    )

    #expect(plan.addedCount == 2)
    #expect(plan.skippedCount == 3)
    #expect(plan.items.count == existing.count + 2)
    #expect(plan.items.suffix(2).map(\.path) == [
        secondURL.standardizedFileURL.path,
        folderURL.standardizedFileURL.path,
    ])
    #expect(plan.items.suffix(2).map(\.kind) == [.document, .folder])
}

@Test("Trash items round-trip without a filesystem path")
func trashItemRoundTrip() throws {
    let item = DockItem.trash()
    let data = try JSONEncoder().encode(item)
    let decoded = try JSONDecoder().decode(DockItem.self, from: data)

    #expect(decoded == item)
    #expect(decoded.kind == .trash)
    #expect(decoded.path.isEmpty)
    #expect(decoded.fileURL == nil)
    #expect(decoded.label == "Trash")
}

@Test("Dock item planner allows one Trash item per dock")
func dockItemPlannerTrashUniqueness() throws {
    let existing = [DockItem.separator()]
    let added = DockItemPlanner.planAddingTrash(to: existing)
    let trash = try #require(added.items.last)

    #expect(added.addedCount == 1)
    #expect(added.skippedCount == 0)
    #expect(trash.kind == .trash)

    let duplicate = DockItemPlanner.planAddingTrash(to: added.items)
    #expect(duplicate.items == added.items)
    #expect(duplicate.addedCount == 0)
    #expect(duplicate.skippedCount == 1)
}

private func makeDockItemTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("freedock-items-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
        at: url,
        withIntermediateDirectories: true
    )
    return url
}
