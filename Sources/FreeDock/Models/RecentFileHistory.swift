import Foundation

struct RecentFileRecord: Codable, Identifiable, Equatable, Hashable, Sendable {
    var id: String { path }

    var path: String
    var displayName: String?
    var lastOpenedAt: Date

    init(
        path: String,
        displayName: String? = nil,
        lastOpenedAt: Date
    ) {
        self.path = path
        self.displayName = displayName
        self.lastOpenedAt = lastOpenedAt
    }

    var fileURL: URL? {
        guard path.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: path)
    }

    private enum CodingKeys: String, CodingKey {
        case path
        case displayName
        case lastOpenedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = (try? container.decode(String.self, forKey: .path)) ?? ""
        displayName = try? container.decode(
            String.self,
            forKey: .displayName
        )
        lastOpenedAt =
            (try? container.decode(Date.self, forKey: .lastOpenedAt))
            ?? .distantPast
    }
}

struct RecentFileHistoryPlan: Equatable, Sendable {
    let records: [RecentFileRecord]
    let didRecord: Bool
}

enum RecentFileHistoryPlanner {
    static let defaultLimit = 50
    static let maximumLimit = 100

    /// Records only existing local documents. Callers decide which FreeDock open
    /// actions should count; applications, folders, and remote URLs are rejected.
    static func planRecording(
        url: URL,
        displayName: String? = nil,
        openedAt: Date = Date(),
        records: [RecentFileRecord],
        limit: Int = defaultLimit
    ) -> RecentFileHistoryPlan {
        let effectiveLimit = clampedLimit(limit)
        let existingRecords = normalized(records, limit: effectiveLimit)
        guard effectiveLimit > 0,
              url.isFileURL,
              let item = DockItem.pinnedItem(at: url),
              item.kind == .document
        else {
            return RecentFileHistoryPlan(
                records: existingRecords,
                didRecord: false
            )
        }

        let standardizedURL = url.standardizedFileURL
        let record = RecentFileRecord(
            path: standardizedURL.path,
            displayName: normalizedName(displayName) ?? item.label,
            lastOpenedAt: openedAt
        )
        let updatedRecords = normalized(
            [record] + records,
            limit: effectiveLimit
        )
        let didRecord = updatedRecords.contains {
            pathIdentity(for: $0.path) == pathIdentity(for: record.path)
                && $0.lastOpenedAt == openedAt
        }
        return RecentFileHistoryPlan(
            records: updatedRecords,
            didRecord: didRecord
        )
    }

    /// Produces a deterministic newest-first, canonical-path-unique history.
    static func normalized(
        _ records: [RecentFileRecord],
        limit: Int = defaultLimit
    ) -> [RecentFileRecord] {
        let effectiveLimit = clampedLimit(limit)
        guard effectiveLimit > 0 else { return [] }

        let sortedRecords = records
            .filter { $0.fileURL != nil }
            .sorted { lhs, rhs in
                if lhs.lastOpenedAt != rhs.lastOpenedAt {
                    return lhs.lastOpenedAt > rhs.lastOpenedAt
                }
                return lhs.path < rhs.path
            }
        var seenPaths = Set<String>()
        var result: [RecentFileRecord] = []
        result.reserveCapacity(min(sortedRecords.count, effectiveLimit))

        for record in sortedRecords {
            let identity = pathIdentity(for: record.path)
            guard seenPaths.insert(identity).inserted else { continue }
            result.append(record)
            if result.count == effectiveLimit {
                break
            }
        }
        return result
    }

    static func pathIdentity(for path: String) -> String {
        URL(fileURLWithPath: path)
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
    }

    private static func clampedLimit(_ limit: Int) -> Int {
        min(max(limit, 0), maximumLimit)
    }

    private static func normalizedName(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }
}
