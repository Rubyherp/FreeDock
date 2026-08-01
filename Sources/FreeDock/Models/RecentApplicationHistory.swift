import Foundation

struct RecentApplicationRecord: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var bundleIdentifier: String
    var path: String
    var displayName: String
    var lastUsedAt: Date

    init(
        id: UUID = UUID(),
        bundleIdentifier: String,
        path: String,
        displayName: String,
        lastUsedAt: Date
    ) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.path = path
        self.displayName = displayName
        self.lastUsedAt = lastUsedAt
    }
}

enum RecentApplicationHistoryPlanner {
    static let maximumLimit = 50

    static func recording(
        bundleIdentifier: String,
        path: String,
        displayName: String,
        usedAt: Date,
        in records: [RecentApplicationRecord]
    ) -> [RecentApplicationRecord] {
        guard !bundleIdentifier.isEmpty, path.hasPrefix("/") else {
            return normalized(records)
        }
        var updated = normalized(records)
        let existingID = updated.first(where: {
            $0.bundleIdentifier == bundleIdentifier
        })?.id
        updated.removeAll { $0.bundleIdentifier == bundleIdentifier }
        updated.insert(
            RecentApplicationRecord(
                id: existingID ?? UUID(),
                bundleIdentifier: bundleIdentifier,
                path: path,
                displayName: displayName,
                lastUsedAt: usedAt
            ),
            at: 0
        )
        return Array(updated.prefix(maximumLimit))
    }

    static func normalized(
        _ records: [RecentApplicationRecord]
    ) -> [RecentApplicationRecord] {
        var seen = Set<String>()
        return records
            .sorted { $0.lastUsedAt > $1.lastUsedAt }
            .filter {
                !$0.bundleIdentifier.isEmpty
                    && $0.path.hasPrefix("/")
                    && seen.insert($0.bundleIdentifier).inserted
            }
            .prefix(maximumLimit)
            .map { $0 }
    }
}

enum DynamicApplicationSectionPlanner {
    static func items(
        records: [RecentApplicationRecord],
        runningBundleIDs: Set<String>,
        pinnedItems: [DockItem],
        limit: Int
    ) -> [DockItem] {
        let pinnedPaths = Set(
            pinnedItems
                .filter { $0.kind == .application }
                .map { URL(fileURLWithPath: $0.path).standardizedFileURL.path }
        )
        let ordered = RecentApplicationHistoryPlanner.normalized(records)
            .filter {
                !pinnedPaths.contains(
                    URL(fileURLWithPath: $0.path).standardizedFileURL.path
                )
            }
            .sorted { left, right in
                let leftRunning = runningBundleIDs.contains(left.bundleIdentifier)
                let rightRunning = runningBundleIDs.contains(right.bundleIdentifier)
                if leftRunning != rightRunning { return leftRunning }
                return left.lastUsedAt > right.lastUsedAt
            }

        return ordered.prefix(max(1, min(limit, 10))).map {
            DockItem.application(
                at: URL(fileURLWithPath: $0.path),
                id: $0.id,
                label: $0.displayName
            )
        }
    }
}
