import Foundation

enum QuickLaunchMatchKind: Int, Equatable, Sendable {
    case exact
    case prefix
    case wordPrefix
    case substring
}

struct QuickLaunchSearchResult: Identifiable, Equatable, Sendable {
    let item: DockItem
    let displayLabel: String
    let dockIndex: Int
    let matchKind: QuickLaunchMatchKind?

    var id: DockItem.ID {
        item.id
    }
}

enum QuickLaunchSearch {
    static func results(
        in items: [DockItem],
        matching query: String
    ) -> [QuickLaunchSearchResult] {
        let normalizedQuery = normalize(query)
        let candidates = items.enumerated().compactMap { index, item in
            candidate(for: item, at: index)
        }

        guard !normalizedQuery.isEmpty else {
            return candidates.map {
                QuickLaunchSearchResult(
                    item: $0.item,
                    displayLabel: $0.displayLabel,
                    dockIndex: $0.dockIndex,
                    matchKind: nil
                )
            }
        }

        var buckets = Array(
            repeating: [QuickLaunchSearchResult](),
            count: QuickLaunchMatchKind.substring.rawValue + 1
        )

        for candidate in candidates {
            guard let matchKind = bestMatch(
                for: normalizedQuery,
                in: candidate.searchableFields
            ) else {
                continue
            }

            buckets[matchKind.rawValue].append(
                QuickLaunchSearchResult(
                    item: candidate.item,
                    displayLabel: candidate.displayLabel,
                    dockIndex: candidate.dockIndex,
                    matchKind: matchKind
                )
            )
        }

        return buckets.flatMap { $0 }
    }

    static func displayLabel(for item: DockItem) -> String {
        if let label = trimmedNonEmpty(item.label) {
            return label
        }
        if let smartStackSource = item.smartStackSource {
            return smartStackSource.defaultLabel
        }

        let component = URL(fileURLWithPath: item.path).lastPathComponent
        guard !component.isEmpty else {
            return ""
        }
        if item.kind == .application {
            return (component as NSString).deletingPathExtension
        }
        return component
    }

    private struct Candidate {
        let item: DockItem
        let displayLabel: String
        let dockIndex: Int
        let searchableFields: [String]
    }

    private static func candidate(
        for item: DockItem,
        at index: Int
    ) -> Candidate? {
        guard !item.isSeparator else {
            return nil
        }

        let normalizedPath = normalize(item.path)
        guard item.smartStackSource != nil || !normalizedPath.isEmpty else {
            return nil
        }

        let displayLabel = displayLabel(for: item)
        let normalizedLabel = normalize(displayLabel)
        let fields = [normalizedLabel, normalizedPath].filter { !$0.isEmpty }

        guard !fields.isEmpty else {
            return nil
        }
        return Candidate(
            item: item,
            displayLabel: displayLabel,
            dockIndex: index,
            searchableFields: fields
        )
    }

    private static func bestMatch(
        for query: String,
        in fields: [String]
    ) -> QuickLaunchMatchKind? {
        let phraseMatch = bestFieldMatch(for: query, in: fields)
        let tokens = query.split(separator: " ").map(String.init)
        var tokenAggregate = QuickLaunchMatchKind.exact

        for token in tokens {
            guard let tokenMatch = bestFieldMatch(for: token, in: fields) else {
                return nil
            }
            if tokenMatch.rawValue > tokenAggregate.rawValue {
                tokenAggregate = tokenMatch
            }
        }

        guard let phraseMatch else {
            return tokenAggregate
        }
        return phraseMatch.rawValue < tokenAggregate.rawValue
            ? phraseMatch
            : tokenAggregate
    }

    private static func bestFieldMatch(
        for query: String,
        in fields: [String]
    ) -> QuickLaunchMatchKind? {
        var best: QuickLaunchMatchKind?

        for field in fields {
            let matchKind: QuickLaunchMatchKind?
            if field == query {
                matchKind = .exact
            } else if field.hasPrefix(query) {
                matchKind = .prefix
            } else if hasWordPrefix(query, in: field) {
                matchKind = .wordPrefix
            } else if field.contains(query) {
                matchKind = .substring
            } else {
                matchKind = nil
            }

            guard let matchKind else {
                continue
            }
            if best == nil || matchKind.rawValue < best!.rawValue {
                best = matchKind
            }
        }
        return best
    }

    private static func hasWordPrefix(
        _ query: String,
        in field: String
    ) -> Bool {
        var index = field.startIndex
        while index < field.endIndex {
            let isBoundary: Bool
            if index == field.startIndex {
                isBoundary = true
            } else {
                let previousIndex = field.index(before: index)
                isBoundary = !isWordCharacter(field[previousIndex])
            }

            if isBoundary, field[index...].hasPrefix(query) {
                return true
            }
            field.formIndex(after: &index)
        }
        return false
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber
    }

    private static func normalize(_ value: String) -> String {
        let locale = Locale(identifier: "en_US_POSIX")
        return value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: locale
            )
            .lowercased(with: locale)
    }

    private static func trimmedNonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

enum QuickLaunchNavigationDirection: Sendable {
    case next
    case previous
}

struct QuickLaunchSelection: Equatable, Sendable {
    private(set) var selectedItemID: DockItem.ID?

    init(selectedItemID: DockItem.ID? = nil) {
        self.selectedItemID = selectedItemID
    }

    mutating func reconcile(with results: [QuickLaunchSearchResult]) {
        guard !results.isEmpty else {
            selectedItemID = nil
            return
        }
        if let selectedItemID,
           results.contains(where: { $0.id == selectedItemID })
        {
            return
        }
        selectedItemID = results[0].id
    }

    mutating func move(
        _ direction: QuickLaunchNavigationDirection,
        in results: [QuickLaunchSearchResult]
    ) {
        guard !results.isEmpty else {
            selectedItemID = nil
            return
        }

        guard let selectedItemID,
              let currentIndex = results.firstIndex(
                  where: { $0.id == selectedItemID }
              )
        else {
            self.selectedItemID = direction == .next
                ? results[0].id
                : results[results.count - 1].id
            return
        }

        let nextIndex: Int
        switch direction {
        case .next:
            nextIndex = (currentIndex + 1) % results.count
        case .previous:
            nextIndex = (currentIndex - 1 + results.count) % results.count
        }
        self.selectedItemID = results[nextIndex].id
    }

    func selectedResult(
        in results: [QuickLaunchSearchResult]
    ) -> QuickLaunchSearchResult? {
        guard let selectedItemID else {
            return nil
        }
        return results.first { $0.id == selectedItemID }
    }
}
