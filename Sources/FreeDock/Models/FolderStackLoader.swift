import Foundation
import UniformTypeIdentifiers

struct FolderStackEntry: Identifiable, Equatable, Sendable {
    var id: URL { url }

    let url: URL
    let name: String
    let isFolder: Bool
    let modificationDate: Date?
    let recentlyOpenedAt: Date?
    let kindDescription: String
}

struct FolderStackSnapshot: Equatable, Sendable {
    let entries: [FolderStackEntry]
    let totalCount: Int
    let isTruncated: Bool
}

enum FolderStackLoaderError: LocalizedError, Equatable {
    case notFolder(URL)
    case missingFolderPath
    case downloadsUnavailable

    var errorDescription: String? {
        switch self {
        case let .notFolder(url):
            return "\(url.lastPathComponent) is not a readable folder."
        case .missingFolderPath:
            return "The folder stack has no folder path."
        case .downloadsUnavailable:
            return "The Downloads folder is unavailable."
        }
    }
}

enum FolderStackLoader {
    static let maximumItemCount = 200

    /// Unified entry point for normal folders and source-driven smart stacks.
    static func load(
        item: DockItem,
        recentFiles: [RecentFileRecord] = [],
        downloadsURL: URL? = nil,
        limit: Int = maximumItemCount
    ) throws -> FolderStackSnapshot {
        let options = item.folderOptions
            ?? item.smartStackSource?.defaultOptions
            ?? FolderStackOptions()

        switch item.smartStackSource {
        case .recentFiles:
            return load(
                recentFiles: recentFiles,
                options: options,
                limit: limit
            )

        case .downloads:
            guard let downloadsURL = resolvedDownloadsURL(downloadsURL) else {
                throw FolderStackLoaderError.downloadsUnavailable
            }
            return try load(
                folderURL: downloadsURL,
                options: options,
                limit: limit
            )

        case nil:
            guard let folderURL = item.fileURL else {
                throw FolderStackLoaderError.missingFolderPath
            }
            return try load(
                folderURL: folderURL,
                options: options,
                limit: limit
            )
        }
    }

    /// Loads a fresh snapshot every time so stacks track changes on disk.
    static func load(
        folderURL: URL,
        options: FolderStackOptions,
        limit: Int = maximumItemCount
    ) throws -> FolderStackSnapshot {
        guard folderURL.isFileURL else {
            throw FolderStackLoaderError.notFolder(folderURL)
        }

        let standardizedURL = folderURL.standardizedFileURL
        let folderValues = try? standardizedURL.resourceValues(
            forKeys: [.contentTypeKey, .isDirectoryKey, .isPackageKey]
        )
        let isApplication =
            standardizedURL.pathExtension.caseInsensitiveCompare("app")
                == .orderedSame
            || folderValues?.contentType?.conforms(to: .application) == true
        guard folderValues?.isDirectory == true,
              folderValues?.isPackage != true,
              !isApplication
        else {
            throw FolderStackLoaderError.notFolder(standardizedURL)
        }

        let enumerationOptions: FileManager.DirectoryEnumerationOptions =
            options.showHiddenFiles ? [] : [.skipsHiddenFiles]
        let resourceKeys: [URLResourceKey] = [
            .contentTypeKey,
            .isDirectoryKey,
            .isPackageKey,
            .localizedNameKey,
            .contentModificationDateKey,
        ]
        let childURLs = try FileManager.default.contentsOfDirectory(
            at: standardizedURL,
            includingPropertiesForKeys: resourceKeys,
            options: enumerationOptions
        )
        let sortedEntries = childURLs
            .map { entry(for: $0) }
            .sorted { lhs, rhs in
                ordered(lhs, before: rhs, by: options.sortOrder)
            }

        let effectiveLimit = min(max(limit, 0), maximumItemCount)
        let visibleEntries = Array(sortedEntries.prefix(effectiveLimit))
        return FolderStackSnapshot(
            entries: visibleEntries,
            totalCount: sortedEntries.count,
            isTruncated: sortedEntries.count > visibleEntries.count
        )
    }

    static func load(
        recentFiles: [RecentFileRecord],
        options: FolderStackOptions = SmartStackSource.recentFiles.defaultOptions,
        limit: Int = maximumItemCount
    ) -> FolderStackSnapshot {
        let records = RecentFileHistoryPlanner.normalized(
            recentFiles,
            limit: RecentFileHistoryPlanner.maximumLimit
        )
        let entries = records.compactMap { record -> FolderStackEntry? in
            guard let url = record.fileURL,
                  let item = DockItem.pinnedItem(at: url),
                  item.kind == .document,
                  options.showHiddenFiles || !isHidden(url)
            else {
                return nil
            }
            return entry(
                for: url,
                nameOverride: record.displayName,
                recentlyOpenedAt: record.lastOpenedAt
            )
        }
        .sorted { lhs, rhs in
            ordered(lhs, before: rhs, by: options.sortOrder)
        }

        let effectiveLimit = min(max(limit, 0), maximumItemCount)
        let visibleEntries = Array(entries.prefix(effectiveLimit))
        return FolderStackSnapshot(
            entries: visibleEntries,
            totalCount: entries.count,
            isTruncated: entries.count > visibleEntries.count
        )
    }

    private static func entry(
        for url: URL,
        nameOverride: String? = nil,
        recentlyOpenedAt: Date? = nil
    ) -> FolderStackEntry {
        let values = try? url.resourceValues(
            forKeys: [
                .contentTypeKey,
                .isDirectoryKey,
                .isPackageKey,
                .localizedNameKey,
                .contentModificationDateKey,
            ]
        )
        let isPackage = values?.isPackage ?? false
        let isDirectory = values?.isDirectory ?? false
        let contentType = values?.contentType
        let isApplication =
            isDirectory
            && (
                url.pathExtension.caseInsensitiveCompare("app") == .orderedSame
                || contentType?.conforms(to: .application) == true
            )
        let isFolder = isDirectory && !isPackage && !isApplication
        let kindDescription: String
        if isFolder {
            kindDescription = "Folder"
        } else if isApplication {
            kindDescription = "Application"
        } else {
            kindDescription = contentType?.localizedDescription
                ?? (isPackage ? "Package" : "Document")
        }

        return FolderStackEntry(
            url: url.standardizedFileURL,
            name: normalizedName(nameOverride)
                ?? values?.localizedName
                ?? url.lastPathComponent,
            isFolder: isFolder,
            modificationDate: values?.contentModificationDate,
            recentlyOpenedAt: recentlyOpenedAt,
            kindDescription: kindDescription
        )
    }

    private static func ordered(
        _ lhs: FolderStackEntry,
        before rhs: FolderStackEntry,
        by sortOrder: FolderStackOptions.SortOrder
    ) -> Bool {
        switch sortOrder {
        case .name:
            return orderedByName(lhs, before: rhs)

        case .dateModified:
            let lhsDate = lhs.modificationDate ?? .distantPast
            let rhsDate = rhs.modificationDate ?? .distantPast
            if lhsDate != rhsDate {
                return lhsDate > rhsDate
            }
            return orderedByName(lhs, before: rhs)

        case .kind:
            let comparison = lhs.kindDescription.localizedStandardCompare(
                rhs.kindDescription
            )
            if comparison != .orderedSame {
                return comparison == .orderedAscending
            }
            return orderedByName(lhs, before: rhs)

        case .recentlyOpened:
            let lhsDate = lhs.recentlyOpenedAt
                ?? lhs.modificationDate
                ?? .distantPast
            let rhsDate = rhs.recentlyOpenedAt
                ?? rhs.modificationDate
                ?? .distantPast
            if lhsDate != rhsDate {
                return lhsDate > rhsDate
            }
            return orderedByName(lhs, before: rhs)
        }
    }

    private static func orderedByName(
        _ lhs: FolderStackEntry,
        before rhs: FolderStackEntry
    ) -> Bool {
        let comparison = lhs.name.localizedStandardCompare(rhs.name)
        if comparison != .orderedSame {
            return comparison == .orderedAscending
        }
        return lhs.url.path < rhs.url.path
    }

    private static func isHidden(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isHiddenKey])
        return values?.isHidden == true || url.lastPathComponent.hasPrefix(".")
    }

    private static func normalizedName(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    private static func resolvedDownloadsURL(_ override: URL?) -> URL? {
        override?.standardizedFileURL
            ?? FileManager.default.urls(
                for: .downloadsDirectory,
                in: .userDomainMask
            ).first?.standardizedFileURL
    }
}
