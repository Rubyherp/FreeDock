import Foundation
import Testing
@testable import FreeDock

@Test("Folder stacks filter hidden files and treat packages as leaf entries")
func folderStackFilteringAndPackages() throws {
    let temporaryDirectory = try makeFolderStackTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    let applicationURL = temporaryDirectory.appendingPathComponent("Example.app")
    let folderURL = temporaryDirectory.appendingPathComponent("Projects")
    let documentURL = temporaryDirectory.appendingPathComponent("Notes.txt")
    let hiddenURL = temporaryDirectory.appendingPathComponent(".secret.txt")
    try FileManager.default.createDirectory(
        at: applicationURL,
        withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
        at: folderURL,
        withIntermediateDirectories: true
    )
    try Data("notes".utf8).write(to: documentURL)
    try Data("secret".utf8).write(to: hiddenURL)

    let defaultSnapshot = try FolderStackLoader.load(
        folderURL: temporaryDirectory,
        options: FolderStackOptions()
    )
    #expect(defaultSnapshot.totalCount == 3)
    #expect(!defaultSnapshot.isTruncated)
    #expect(!defaultSnapshot.entries.map(\.name).contains(".secret.txt"))
    #expect(
        defaultSnapshot.entries.first(
            where: { $0.url.lastPathComponent == "Projects" }
        )?.isFolder == true
    )
    #expect(
        defaultSnapshot.entries.first(
            where: { $0.url.lastPathComponent == "Example.app" }
        )?.isFolder == false
    )
    #expect(
        defaultSnapshot.entries.first(
            where: { $0.url.lastPathComponent == "Example.app" }
        )?.kindDescription == "Application"
    )

    let hiddenSnapshot = try FolderStackLoader.load(
        folderURL: temporaryDirectory,
        options: FolderStackOptions(showHiddenFiles: true)
    )
    #expect(hiddenSnapshot.totalCount == 4)
    #expect(hiddenSnapshot.entries.map(\.name).contains(".secret.txt"))
}

@Test("Folder stacks apply deterministic name and modification-date sorting")
func folderStackSorting() throws {
    let temporaryDirectory = try makeFolderStackTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    let alphaURL = temporaryDirectory.appendingPathComponent("Alpha.txt")
    let betaURL = temporaryDirectory.appendingPathComponent("beta.txt")
    let newestURL = temporaryDirectory.appendingPathComponent("Newest.txt")
    try Data("a".utf8).write(to: alphaURL)
    try Data("b".utf8).write(to: betaURL)
    try Data("new".utf8).write(to: newestURL)

    let oldDate = Date(timeIntervalSince1970: 1_000)
    let middleDate = Date(timeIntervalSince1970: 2_000)
    let newDate = Date(timeIntervalSince1970: 3_000)
    try FileManager.default.setAttributes(
        [.modificationDate: oldDate],
        ofItemAtPath: alphaURL.path
    )
    try FileManager.default.setAttributes(
        [.modificationDate: middleDate],
        ofItemAtPath: betaURL.path
    )
    try FileManager.default.setAttributes(
        [.modificationDate: newDate],
        ofItemAtPath: newestURL.path
    )

    let nameSnapshot = try FolderStackLoader.load(
        folderURL: temporaryDirectory,
        options: FolderStackOptions(sortOrder: .name)
    )
    #expect(nameSnapshot.entries.map(\.name) == [
        "Alpha.txt",
        "beta.txt",
        "Newest.txt",
    ])

    let dateSnapshot = try FolderStackLoader.load(
        folderURL: temporaryDirectory,
        options: FolderStackOptions(sortOrder: .dateModified)
    )
    #expect(dateSnapshot.entries.map(\.name) == [
        "Newest.txt",
        "beta.txt",
        "Alpha.txt",
    ])
}

@Test("Folder stack kind sorting uses kind then name")
func folderStackKindSorting() throws {
    let temporaryDirectory = try makeFolderStackTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    let applicationURL = temporaryDirectory.appendingPathComponent("Zulu.app")
    let folderURL = temporaryDirectory.appendingPathComponent("Alpha Folder")
    let documentURL = temporaryDirectory.appendingPathComponent("Middle.txt")
    try FileManager.default.createDirectory(
        at: applicationURL,
        withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
        at: folderURL,
        withIntermediateDirectories: true
    )
    try Data("middle".utf8).write(to: documentURL)

    let snapshot = try FolderStackLoader.load(
        folderURL: temporaryDirectory,
        options: FolderStackOptions(sortOrder: .kind)
    )
    let descriptions = snapshot.entries.map(\.kindDescription)

    #expect(descriptions.first == "Application")
    #expect(descriptions.dropFirst().first == "Folder")
    #expect(
        zip(descriptions, descriptions.dropFirst()).allSatisfy {
            $0.0.localizedStandardCompare($0.1) != .orderedDescending
        }
    )
}

@Test("Folder stacks honor requested limits and the global 200-item cap")
func folderStackLimitAndCap() throws {
    let temporaryDirectory = try makeFolderStackTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    for index in 0 ..< 205 {
        let url = temporaryDirectory.appendingPathComponent(
            String(format: "Item-%03d.txt", index)
        )
        try Data().write(to: url)
    }

    let limited = try FolderStackLoader.load(
        folderURL: temporaryDirectory,
        options: FolderStackOptions(),
        limit: 3
    )
    #expect(limited.entries.count == 3)
    #expect(limited.totalCount == 205)
    #expect(limited.isTruncated)

    let capped = try FolderStackLoader.load(
        folderURL: temporaryDirectory,
        options: FolderStackOptions(),
        limit: 1_000
    )
    #expect(capped.entries.count == FolderStackLoader.maximumItemCount)
    #expect(capped.totalCount == 205)
    #expect(capped.isTruncated)
}

@Test("Folder stack snapshots are live")
func folderStackSnapshotsAreLive() throws {
    let temporaryDirectory = try makeFolderStackTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    let first = try FolderStackLoader.load(
        folderURL: temporaryDirectory,
        options: FolderStackOptions()
    )
    #expect(first.totalCount == 0)

    try Data("new".utf8).write(
        to: temporaryDirectory.appendingPathComponent("New.txt")
    )
    let second = try FolderStackLoader.load(
        folderURL: temporaryDirectory,
        options: FolderStackOptions()
    )
    #expect(second.totalCount == 1)
    #expect(second.entries.first?.name == "New.txt")
}

@Test("Folder stack loader rejects documents and application packages")
func folderStackRejectsNonFolders() throws {
    let temporaryDirectory = try makeFolderStackTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    let documentURL = temporaryDirectory.appendingPathComponent("Notes.txt")
    let applicationURL = temporaryDirectory.appendingPathComponent("Example.app")
    try Data("notes".utf8).write(to: documentURL)
    try FileManager.default.createDirectory(
        at: applicationURL,
        withIntermediateDirectories: true
    )

    #expect(throws: FolderStackLoaderError.self) {
        try FolderStackLoader.load(
            folderURL: documentURL,
            options: FolderStackOptions()
        )
    }
    #expect(throws: FolderStackLoaderError.self) {
        try FolderStackLoader.load(
            folderURL: applicationURL,
            options: FolderStackOptions()
        )
    }
}

private func makeFolderStackTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("freedock-stack-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
        at: url,
        withIntermediateDirectories: true
    )
    return url
}
