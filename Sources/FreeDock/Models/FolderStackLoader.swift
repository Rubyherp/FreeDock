import Foundation
import UniformTypeIdentifiers

struct FolderStackEntry: Identifiable, Equatable, Sendable {
    var id: URL { url }

    let url: URL
    let name: String
    let isFolder: Bool
    let modificationDate: Date?
    let kindDescription: String
}

struct FolderStackSnapshot: Equatable, Sendable {
    let entries: [FolderStackEntry]
    let totalCount: Int
    let isTruncated: Bool
}

enum FolderStackLoaderError: LocalizedError, Equatable {
    case notFolder(URL)

    var errorDescription: String? {
        switch self {
        case let .notFolder(url):
            return "\(url.lastPathComponent) is not a readable folder."
        }
    }
}

enum FolderStackLoader {
    static let maximumItemCount = 200

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
            .map(entry(for:))
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

    private static func entry(for url: URL) -> FolderStackEntry {
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
            name: values?.localizedName ?? url.lastPathComponent,
            isFolder: isFolder,
            modificationDate: values?.contentModificationDate,
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
}
