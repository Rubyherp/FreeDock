import Testing

@testable import FreeDock

@Suite("Preferences search")
struct PreferencesSearchMatcherTests {
    @Test("Empty searches show every section")
    func empty() {
        #expect(PreferencesSearchMatcher.matches(query: "", text: "Appearance"))
    }

    @Test("Every token must match regardless of case or accents")
    func tokenized() {
        #expect(PreferencesSearchMatcher.matches(
            query: "ICON magnification",
            text: "Icons & Layout icon size magnification"
        ))
        #expect(PreferencesSearchMatcher.matches(
            query: "resume",
            text: "Résumé appearance"
        ))
        #expect(!PreferencesSearchMatcher.matches(
            query: "icon privacy",
            text: "Icons & Layout icon size"
        ))
    }
}
