import Cocoa
import CoreFoundation

struct SystemDockApp: Equatable, Sendable {
    let path: String
    let label: String?
    let bundleIdentifier: String?
}

struct SystemDockImportPlan: Equatable, Sendable {
    let items: [DockItem]
    let skippedCount: Int
}

struct SystemDockLoadResult: Equatable, Sendable {
    let apps: [SystemDockApp]
    let unavailableCount: Int
}

enum SystemDockImportError: LocalizedError, Equatable {
    case preferencesUnavailable
    case invalidPreferencesFormat

    var errorDescription: String? {
        switch self {
        case .preferencesUnavailable:
            return "FreeDock couldn’t read the macOS Dock preferences."
        case .invalidPreferencesFormat:
            return "The macOS Dock preferences use an unsupported format."
        }
    }
}

enum SystemDockImporter {
    private static let preferencesDomain = "com.apple.dock"
    private static let persistentAppsKey = "persistent-apps"

    static func loadPinnedApps() throws -> SystemDockLoadResult {
        let rawValue = try currentPersistentAppsValue()
        return availableApps(
            from: try parsePersistentApps(rawValue),
            installedPathForApp: installedPath(for:)
        )
    }

    static func availableApps(
        from apps: [SystemDockApp],
        installedPathForApp: (SystemDockApp) -> String?,
        bundleIdentifierForPath: (String) -> String? = AppInfo.resolveBundleID(from:)
    ) -> SystemDockLoadResult {
        var availableApps: [SystemDockApp] = []
        var unavailableCount = 0

        for app in apps {
            guard let installedPath = installedPathForApp(app) else {
                unavailableCount += 1
                continue
            }
            let path = standardizedPath(installedPath)
            let label = normalizedLabel(app.label)
                ?? AppInfo.resolve(from: path).displayName

            availableApps.append(SystemDockApp(
                path: path,
                label: label,
                bundleIdentifier: normalizedBundleIdentifier(bundleIdentifierForPath(path))
                    ?? normalizedBundleIdentifier(app.bundleIdentifier)
            ))
        }

        return SystemDockLoadResult(
            apps: availableApps,
            unavailableCount: unavailableCount
        )
    }

    static func parsePersistentApps(_ value: Any) throws -> [SystemDockApp] {
        guard let tiles = value as? [Any] else {
            throw SystemDockImportError.invalidPreferencesFormat
        }

        return tiles.compactMap { value in
            guard let tile = value as? [String: Any],
                  let tileData = tile["tile-data"] as? [String: Any],
                  let fileData = tileData["file-data"] as? [String: Any],
                  let url = fileURL(from: fileData["_CFURLString"]),
                  url.pathExtension.caseInsensitiveCompare("app") == .orderedSame
            else {
                return nil
            }

            return SystemDockApp(
                path: standardizedPath(url.path),
                label: tileData["file-label"] as? String,
                bundleIdentifier: tileData["bundle-identifier"] as? String
            )
        }
    }

    static func planImport(
        apps: [SystemDockApp],
        existingItems: [DockItem],
        bundleIdentifierForPath: (String) -> String? = AppInfo.resolveBundleID(from:)
    ) -> SystemDockImportPlan {
        var seenPaths = Set(
            existingItems
                .filter { !$0.isSeparator }
                .map { pathIdentity($0.appPath) }
        )
        var seenBundleIdentifiers = Set(
            existingItems
                .filter { !$0.isSeparator }
                .compactMap { bundleIdentifierForPath($0.appPath) }
                .compactMap(normalizedBundleIdentifier)
        )
        var importedItems: [DockItem] = []
        var skippedCount = 0

        for app in apps {
            let path = standardizedPath(app.path)
            let pathKey = pathIdentity(path)
            let bundleIdentifier = normalizedBundleIdentifier(app.bundleIdentifier)
                ?? normalizedBundleIdentifier(bundleIdentifierForPath(path))

            if seenPaths.contains(pathKey)
                || bundleIdentifier.map(seenBundleIdentifiers.contains) == true
            {
                skippedCount += 1
                continue
            }

            let label = normalizedLabel(app.label)
                ?? URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            importedItems.append(DockItem(appPath: path, label: label))
            seenPaths.insert(pathKey)
            if let bundleIdentifier {
                seenBundleIdentifiers.insert(bundleIdentifier)
            }
        }

        return SystemDockImportPlan(
            items: importedItems,
            skippedCount: skippedCount
        )
    }

    private static func currentPersistentAppsValue() throws -> Any {
        if let value = CFPreferencesCopyAppValue(
            persistentAppsKey as CFString,
            preferencesDomain as CFString
        ) {
            return value
        }

        let preferencesURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences")
            .appendingPathComponent("\(preferencesDomain).plist")

        guard let data = try? Data(contentsOf: preferencesURL),
              let propertyList = try? PropertyListSerialization.propertyList(
                  from: data,
                  options: [],
                  format: nil
              ),
              let dictionary = propertyList as? [String: Any],
              let value = dictionary[persistentAppsKey]
        else {
            throw SystemDockImportError.preferencesUnavailable
        }

        return value
    }

    private static func fileURL(from value: Any?) -> URL? {
        if let url = value as? URL, url.isFileURL {
            return url
        }

        guard let string = value as? String else { return nil }
        if let url = URL(string: string), url.isFileURL {
            return url
        }
        if string.hasPrefix("/") {
            return URL(fileURLWithPath: string)
        }
        return nil
    }

    static func resolveInstalledPath(
        for app: SystemDockApp,
        fallbackURLForBundleIdentifier: (String) -> URL?,
        applicationIsValid: (String) -> Bool
    ) -> String? {
        var candidates = [app.path]
        if let bundleIdentifier = normalizedBundleIdentifier(app.bundleIdentifier),
           let fallbackURL = fallbackURLForBundleIdentifier(bundleIdentifier)
        {
            candidates.append(fallbackURL.path)
        }

        return candidates.lazy
            .map(standardizedPath)
            .first(where: applicationIsValid)
    }

    static func isValidApplication(atPath path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        guard url.pathExtension.caseInsensitiveCompare("app") == .orderedSame else {
            return false
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: path,
            isDirectory: &isDirectory
        ),
        isDirectory.boolValue,
        let bundle = Bundle(path: path),
        let executableURL = bundle.executableURL
        else {
            return false
        }

        return FileManager.default.isExecutableFile(atPath: executableURL.path)
    }

    private static func installedPath(for app: SystemDockApp) -> String? {
        resolveInstalledPath(
            for: app,
            fallbackURLForBundleIdentifier: {
                NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)
            },
            applicationIsValid: isValidApplication(atPath:)
        )
    }

    private static func standardizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path)
            .standardizedFileURL
            .path
    }

    private static func pathIdentity(_ path: String) -> String {
        URL(fileURLWithPath: path)
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
    }

    private static func normalizedBundleIdentifier(_ value: String?) -> String? {
        guard let value = normalizedLabel(value) else { return nil }
        return value.lowercased()
    }

    private static func normalizedLabel(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }
}
