import Foundation
import Testing
@testable import FreeDock

@Test("System Dock parser preserves app order and decodes file URLs")
func systemDockParserPreservesOrder() throws {
    let persistentApps: [Any] = [
        systemDockTile(
            url: "file:///Applications/First.app/",
            label: "First",
            bundleIdentifier: "com.example.first"
        ),
        systemDockTile(
            url: "file:///System/Applications/System%20Settings.app/",
            label: "System Settings",
            bundleIdentifier: "com.apple.systempreferences"
        ),
        systemDockTile(
            url: "/Applications/Legacy.app",
            label: "Legacy",
            bundleIdentifier: nil
        ),
    ]

    let apps = try SystemDockImporter.parsePersistentApps(persistentApps)

    #expect(apps.map(\.path) == [
        "/Applications/First.app",
        "/System/Applications/System Settings.app",
        "/Applications/Legacy.app",
    ])
    #expect(apps.map(\.label) == ["First", "System Settings", "Legacy"])
    #expect(apps.map(\.bundleIdentifier) == [
        "com.example.first",
        "com.apple.systempreferences",
        nil,
    ])
}

@Test("System Dock parser skips malformed and non-app tiles independently")
func systemDockParserSkipsUnsupportedTiles() throws {
    let persistentApps: [Any] = [
        ["tile-data": ["file-label": "Missing file data"]],
        systemDockTile(
            url: "https://example.com/NotAnApp.app",
            label: "Web",
            bundleIdentifier: nil
        ),
        systemDockTile(
            url: "file:///Users/example/Downloads/",
            label: "Downloads",
            bundleIdentifier: nil
        ),
        systemDockTile(
            url: "file:///Applications/Valid.app/",
            label: "Valid",
            bundleIdentifier: "com.example.valid"
        ),
    ]

    let apps = try SystemDockImporter.parsePersistentApps(persistentApps)

    #expect(apps.count == 1)
    #expect(apps.first?.path == "/Applications/Valid.app")
}

@Test("System Dock parser distinguishes an empty Dock from an invalid format")
func systemDockParserValidatesTopLevelFormat() throws {
    #expect(try SystemDockImporter.parsePersistentApps([]).isEmpty)

    var receivedError: SystemDockImportError?
    do {
        _ = try SystemDockImporter.parsePersistentApps(["persistent-apps": "invalid"])
    } catch let error as SystemDockImportError {
        receivedError = error
    } catch {
        Issue.record("Unexpected parser error: \(error)")
    }

    #expect(receivedError == .invalidPreferencesFormat)
}

@Test("System Dock availability keeps valid apps and counts unavailable entries")
func systemDockAvailability() {
    let apps = [
        SystemDockApp(
            path: "/Applications/Available.app",
            label: "Available",
            bundleIdentifier: "com.example.available"
        ),
        SystemDockApp(
            path: "/Applications/Missing.app",
            label: "Missing",
            bundleIdentifier: "com.example.missing"
        ),
    ]

    let result = SystemDockImporter.availableApps(
        from: apps,
        installedPathForApp: { app in
            app.bundleIdentifier == "com.example.available"
                ? "/Resolved/Available.app"
                : nil
        }
    )

    #expect(result.apps == [
        SystemDockApp(
            path: "/Resolved/Available.app",
            label: "Available",
            bundleIdentifier: "com.example.available"
        ),
    ])
    #expect(result.unavailableCount == 1)
}

@Test("System Dock availability trusts the installed bundle over stale metadata")
func systemDockAvailabilityUsesInstalledBundleIdentifier() {
    let app = SystemDockApp(
        path: "/Applications/Replaced.app",
        label: "Replaced",
        bundleIdentifier: "com.example.stale"
    )

    let result = SystemDockImporter.availableApps(
        from: [app],
        installedPathForApp: { $0.path },
        bundleIdentifierForPath: { _ in "com.example.current" }
    )

    #expect(result.apps.first?.bundleIdentifier == "com.example.current")
}

@Test("System Dock path resolution prefers the exact pinned app")
func systemDockPathResolutionPrefersPinnedPath() {
    let pinnedPath = "/Applications/Pinned Beta.app"
    let fallbackPath = "/Applications/Pinned.app"
    let app = SystemDockApp(
        path: pinnedPath,
        label: "Pinned Beta",
        bundleIdentifier: "com.example.pinned"
    )

    let resolvedPinnedPath = SystemDockImporter.resolveInstalledPath(
        for: app,
        fallbackURLForBundleIdentifier: { _ in
            URL(fileURLWithPath: fallbackPath)
        },
        applicationIsValid: { $0 == pinnedPath || $0 == fallbackPath }
    )
    #expect(resolvedPinnedPath == pinnedPath)

    let resolvedFallbackPath = SystemDockImporter.resolveInstalledPath(
        for: app,
        fallbackURLForBundleIdentifier: { _ in
            URL(fileURLWithPath: fallbackPath)
        },
        applicationIsValid: { $0 == fallbackPath }
    )
    #expect(resolvedFallbackPath == fallbackPath)
}

@Test("System Dock app validation requires a launchable bundle")
func systemDockApplicationValidation() throws {
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("freedock-import-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
        at: temporaryDirectory,
        withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    let directoryOnly = temporaryDirectory.appendingPathComponent("Directory.app")
    try FileManager.default.createDirectory(
        at: directoryOnly,
        withIntermediateDirectories: true
    )
    #expect(!SystemDockImporter.isValidApplication(atPath: directoryOnly.path))

    let missingExecutable = temporaryDirectory.appendingPathComponent("Missing.app")
    try createTestApplication(at: missingExecutable, includeExecutable: false)
    #expect(!SystemDockImporter.isValidApplication(atPath: missingExecutable.path))

    let validApplication = temporaryDirectory.appendingPathComponent("Valid.app")
    try createTestApplication(at: validApplication, includeExecutable: true)
    #expect(SystemDockImporter.isValidApplication(atPath: validApplication.path))
}

@Test("System Dock imports preserve stable symlink paths")
func systemDockImportPreservesSymlinkPath() throws {
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("freedock-symlink-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
        at: temporaryDirectory,
        withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    let targetURL = temporaryDirectory.appendingPathComponent("Physical.app")
    let symlinkURL = temporaryDirectory.appendingPathComponent("Stable.app")
    try FileManager.default.createDirectory(
        at: targetURL,
        withIntermediateDirectories: true
    )
    try FileManager.default.createSymbolicLink(
        at: symlinkURL,
        withDestinationURL: targetURL
    )

    let app = SystemDockApp(
        path: symlinkURL.path,
        label: "Stable",
        bundleIdentifier: nil
    )
    let firstPlan = SystemDockImporter.planImport(
        apps: [app],
        existingItems: [],
        bundleIdentifierForPath: { _ in nil }
    )
    #expect(firstPlan.items.first?.appPath == symlinkURL.path)
    #expect(firstPlan.items.first?.kind == .application)

    let secondPlan = SystemDockImporter.planImport(
        apps: [app],
        existingItems: [DockItem(appPath: targetURL.path)],
        bundleIdentifierForPath: { _ in nil }
    )
    #expect(secondPlan.items.isEmpty)
}

@Test("System Dock import appends only missing apps and is idempotent")
func systemDockImportPlanDeduplicates() {
    let existingApp = DockItem(
        appPath: "/Applications/Alpha.app",
        label: "Alpha"
    )
    let separator = DockItem.separator()
    let existingItems = [existingApp, separator]
    let apps = [
        SystemDockApp(
            path: "/Applications/Alpha.app",
            label: "Alpha",
            bundleIdentifier: "com.example.alpha"
        ),
        SystemDockApp(
            path: "/System/Volumes/Alternate/Alpha.app",
            label: "Alpha Alternate",
            bundleIdentifier: "com.example.alpha"
        ),
        SystemDockApp(
            path: "/Applications/Beta.app",
            label: "Beta",
            bundleIdentifier: "com.example.beta"
        ),
        SystemDockApp(
            path: "/Applications/Beta.app/",
            label: "Beta Duplicate",
            bundleIdentifier: "com.example.beta"
        ),
        SystemDockApp(
            path: "/Applications/Gamma.app",
            label: "Gamma",
            bundleIdentifier: nil
        ),
    ]
    let bundleIdentifierForPath: (String) -> String? = { path in
        if path.localizedCaseInsensitiveContains("Alpha") {
            return "com.example.alpha"
        }
        if path.localizedCaseInsensitiveContains("Beta") {
            return "com.example.beta"
        }
        return nil
    }

    let plan = SystemDockImporter.planImport(
        apps: apps,
        existingItems: existingItems,
        bundleIdentifierForPath: bundleIdentifierForPath
    )
    let mergedItems = existingItems + plan.items

    #expect(plan.items.map(\.appPath) == [
        "/Applications/Beta.app",
        "/Applications/Gamma.app",
    ])
    #expect(plan.items.map(\.label) == ["Beta", "Gamma"])
    #expect(plan.items.allSatisfy { $0.kind == .application })
    #expect(plan.items.allSatisfy { $0.folderOptions == nil })
    #expect(plan.skippedCount == 3)
    #expect(mergedItems[0] == existingApp)
    #expect(mergedItems[1] == separator)

    let secondPlan = SystemDockImporter.planImport(
        apps: apps,
        existingItems: mergedItems,
        bundleIdentifierForPath: bundleIdentifierForPath
    )
    #expect(secondPlan.items.isEmpty)
    #expect(secondPlan.skippedCount == apps.count)
}

@Test("System Dock path deduplication preserves case-distinct apps")
func systemDockImportPreservesCaseDistinctPaths() {
    let apps = [
        SystemDockApp(
            path: "/Volumes/CaseSensitive/Foo.app",
            label: "Foo",
            bundleIdentifier: nil
        ),
        SystemDockApp(
            path: "/Volumes/CaseSensitive/foo.app",
            label: "foo",
            bundleIdentifier: nil
        ),
    ]

    let plan = SystemDockImporter.planImport(
        apps: apps,
        existingItems: [],
        bundleIdentifierForPath: { _ in nil }
    )

    #expect(plan.items.count == 2)
    #expect(plan.items.allSatisfy { $0.kind == .application })
}

@Test("System Dock bundle deduplication only considers application items")
func systemDockImportIgnoresNonApplicationBundleIdentities() {
    let documentPath = "/Users/example/Documents/Reference.pdf"
    let existingDocument = DockItem(
        kind: .document,
        path: documentPath,
        label: "Reference"
    )
    let app = SystemDockApp(
        path: "/Applications/Reference.app",
        label: "Reference",
        bundleIdentifier: "com.example.reference"
    )
    var resolvedPaths: [String] = []

    let plan = SystemDockImporter.planImport(
        apps: [app],
        existingItems: [existingDocument],
        bundleIdentifierForPath: { path in
            resolvedPaths.append(path)
            return path == documentPath ? "com.example.reference" : nil
        }
    )

    #expect(resolvedPaths.isEmpty)
    #expect(plan.skippedCount == 0)
    #expect(plan.items.count == 1)
    #expect(plan.items.first?.kind == .application)
    #expect(plan.items.first?.path == "/Applications/Reference.app")
}

private func systemDockTile(
    url: String,
    label: String,
    bundleIdentifier: String?
) -> [String: Any] {
    var tileData: [String: Any] = [
        "file-data": ["_CFURLString": url],
        "file-label": label,
    ]
    if let bundleIdentifier {
        tileData["bundle-identifier"] = bundleIdentifier
    }
    return ["tile-data": tileData]
}

private func createTestApplication(
    at applicationURL: URL,
    includeExecutable: Bool
) throws {
    let contentsURL = applicationURL.appendingPathComponent("Contents")
    let executableDirectory = contentsURL.appendingPathComponent("MacOS")
    try FileManager.default.createDirectory(
        at: executableDirectory,
        withIntermediateDirectories: true
    )

    let propertyList: [String: Any] = [
        "CFBundleIdentifier": "com.example.\(UUID().uuidString.lowercased())",
        "CFBundleExecutable": "TestExecutable",
        "CFBundlePackageType": "APPL",
    ]
    let propertyListData = try PropertyListSerialization.data(
        fromPropertyList: propertyList,
        format: .xml,
        options: 0
    )
    try propertyListData.write(
        to: contentsURL.appendingPathComponent("Info.plist"),
        options: .atomic
    )

    guard includeExecutable else { return }
    let executableURL = executableDirectory.appendingPathComponent("TestExecutable")
    try Data("#!/bin/sh\n".utf8).write(to: executableURL, options: .atomic)
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: executableURL.path
    )
}
