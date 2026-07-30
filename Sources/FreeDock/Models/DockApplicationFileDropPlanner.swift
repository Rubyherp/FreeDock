import Foundation

/// A URL-level validation failure while planning a Finder drop onto an app.
///
/// The planner deliberately performs lexical validation only. The integration
/// layer remains responsible for authoritatively classifying the target as an
/// application and checking that paths still exist immediately before asking
/// AppKit to open them.
enum DockApplicationFileDropURLRejection: Error, Equatable, Sendable {
    case notFileURL
    case nonLocalFileURL
    case missingPath
    case relativePath
}

/// Why a Finder drop cannot be opened with its pinned application.
enum DockApplicationFileDropRejection: Equatable, Sendable {
    case missingApplicationURL
    case invalidApplicationURL(DockApplicationFileDropURLRejection)
    case emptyDrop
    case invalidDroppedURL(
        index: Int,
        reason: DockApplicationFileDropURLRejection
    )
}

/// A validated request to open files with one exact application target.
struct DockApplicationFileDropPlan: Equatable, Sendable {
    let applicationURL: URL
    let fileURLs: [URL]

    /// Original payload indices omitted because an equivalent earlier URL won.
    let duplicateInputIndices: [Int]

    var removedDuplicateCount: Int {
        duplicateInputIndices.count
    }
}

enum DockApplicationFileDropOutcome: Equatable, Sendable {
    case ready(DockApplicationFileDropPlan)
    case rejected(DockApplicationFileDropRejection)

    var plan: DockApplicationFileDropPlan? {
        guard case let .ready(plan) = self else { return nil }
        return plan
    }

    var rejection: DockApplicationFileDropRejection? {
        guard case let .rejected(rejection) = self else { return nil }
        return rejection
    }

    var isReady: Bool {
        plan != nil
    }
}

/// Pure validation and stable normalization for Finder files dropped on an app.
enum DockApplicationFileDropPlanner {
    /// Builds an atomic request suitable for
    /// `NSWorkspace.open(_:withApplicationAt:configuration:)`.
    ///
    /// The application and every dropped value must be absolute local file
    /// URLs. The integration layer must first establish that the target really
    /// is an application; the planner intentionally does not require a `.app`
    /// suffix because a valid app can be reached through an extensionless
    /// symlink. Input order is retained while lexical path duplicates are
    /// removed after their first occurrence. Symlinks are intentionally not
    /// resolved so planning never reads the file system.
    static func plan(
        applicationURL: URL?,
        droppedURLs: [URL]
    ) -> DockApplicationFileDropOutcome {
        guard let applicationURL else {
            return .rejected(.missingApplicationURL)
        }

        let normalizedApplicationURL: URL
        switch normalizeLocalFileURL(applicationURL) {
        case let .success(url):
            normalizedApplicationURL = url
        case let .failure(reason):
            return .rejected(.invalidApplicationURL(reason))
        }

        guard !droppedURLs.isEmpty else {
            return .rejected(.emptyDrop)
        }

        var seenPaths = Set<String>()
        var normalizedURLs: [URL] = []
        var duplicateIndices: [Int] = []
        normalizedURLs.reserveCapacity(droppedURLs.count)

        for (index, inputURL) in droppedURLs.enumerated() {
            let normalizedURL: URL
            switch normalizeLocalFileURL(inputURL) {
            case let .success(url):
                normalizedURL = url
            case let .failure(reason):
                return .rejected(
                    .invalidDroppedURL(index: index, reason: reason)
                )
            }

            if seenPaths.insert(normalizedURL.path).inserted {
                normalizedURLs.append(normalizedURL)
            } else {
                duplicateIndices.append(index)
            }
        }

        return .ready(
            DockApplicationFileDropPlan(
                applicationURL: normalizedApplicationURL,
                fileURLs: normalizedURLs,
                duplicateInputIndices: duplicateIndices
            )
        )
    }

    private static func normalizeLocalFileURL(
        _ url: URL
    ) -> Result<URL, DockApplicationFileDropURLRejection> {
        guard url.isFileURL else {
            return .failure(.notFileURL)
        }

        if let host = url.host,
           !host.isEmpty,
           host.caseInsensitiveCompare("localhost") != .orderedSame
        {
            return .failure(.nonLocalFileURL)
        }

        // Foundation versions disagree about `URL.path` for opaque relative
        // file URLs such as `file:Document.txt`. Classify the stable lexical
        // form first so the result is deterministic across supported macOS
        // releases.
        if hasOpaqueRelativeFilePath(url) {
            return .failure(.relativePath)
        }

        let path = url.path
        guard !path.isEmpty else {
            return .failure(.missingPath)
        }
        guard path.hasPrefix("/") else {
            return .failure(.relativePath)
        }

        return .success(
            URL(fileURLWithPath: path).standardizedFileURL
        )
    }

    private static func hasOpaqueRelativeFilePath(_ url: URL) -> Bool {
        let absoluteString = url.absoluteString
        guard let schemeSeparator = absoluteString.firstIndex(of: ":") else {
            return false
        }

        let resource = absoluteString[absoluteString.index(after: schemeSeparator)...]
        let pathResource = resource.prefix { character in
            character != "?" && character != "#"
        }
        return !pathResource.isEmpty && !pathResource.hasPrefix("//")
    }
}
