import Foundation

enum PreferencesSearchMatcher {
    static func matches(query: String, text: String) -> Bool {
        let tokens = query
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: .current
            )
            .split(whereSeparator: \.isWhitespace)
        guard !tokens.isEmpty else { return true }
        let candidate = text.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: .current
        )
        return tokens.allSatisfy { candidate.contains($0) }
    }
}
