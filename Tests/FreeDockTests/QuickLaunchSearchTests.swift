import Foundation
import Testing
@testable import FreeDock

@Test("Empty quick launch query keeps launchable dock order")
func quickLaunchEmptyQuery() {
    let first = quickLaunchItem(
        1,
        kind: .application,
        path: "/Applications/First.app",
        label: "First"
    )
    let separator = DockItem.separator(id: quickLaunchID(2))
    let stack = DockItem.recentFilesStack(id: quickLaunchID(3))
    let malformed = quickLaunchItem(
        4,
        kind: .document,
        path: "",
        label: "Missing target"
    )
    let last = quickLaunchItem(
        5,
        kind: .document,
        path: "/tmp/Last.pdf",
        label: "Last"
    )

    let results = QuickLaunchSearch.results(
        in: [first, separator, stack, malformed, last],
        matching: "   "
    )

    #expect(results.map(\.id) == [first.id, stack.id, last.id])
    #expect(results.map(\.dockIndex) == [0, 2, 4])
    #expect(results.allSatisfy { $0.matchKind == nil })
}

@Test("Quick launch ranks match quality and preserves dock order within tiers")
func quickLaunchRanking() {
    let substring = quickLaunchItem(1, label: "XalphaY")
    let prefixFirst = quickLaunchItem(2, label: "Alphabet")
    let wordPrefixFirst = quickLaunchItem(3, label: "Project Alpha")
    let exactLabel = quickLaunchItem(4, label: "Alpha")
    let prefixSecond = quickLaunchItem(5, label: "Alpha Notes")
    let wordPrefixSecond = quickLaunchItem(6, label: "Open Alpha")
    let exactPath = quickLaunchItem(
        7,
        path: "alpha",
        label: "Different label"
    )

    let results = QuickLaunchSearch.results(
        in: [
            substring,
            prefixFirst,
            wordPrefixFirst,
            exactLabel,
            prefixSecond,
            wordPrefixSecond,
            exactPath,
        ],
        matching: "alpha"
    )

    #expect(
        results.map(\.id) == [
            exactLabel.id,
            exactPath.id,
            prefixFirst.id,
            prefixSecond.id,
            wordPrefixFirst.id,
            wordPrefixSecond.id,
            substring.id,
        ]
    )
    #expect(
        results.map(\.matchKind) == [
            .exact,
            .exact,
            .prefix,
            .prefix,
            .wordPrefix,
            .wordPrefix,
            .substring,
        ]
    )
}

@Test("Quick launch searches labels and paths without filesystem resolution")
func quickLaunchSearchFields() {
    let safari = quickLaunchItem(
        1,
        kind: .application,
        path: "/Applications/Safari.app",
        label: nil
    )
    let report = quickLaunchItem(
        2,
        kind: .document,
        path: "/Users/example/Documents/Annual Report.pdf",
        label: nil
    )
    let custom = quickLaunchItem(
        3,
        path: "/Applications/Utility.app",
        label: "Launch Tool"
    )

    let safariResults = QuickLaunchSearch.results(
        in: [safari, report, custom],
        matching: "Safari"
    )
    let pathResults = QuickLaunchSearch.results(
        in: [safari, report, custom],
        matching: "documents"
    )
    let labelResults = QuickLaunchSearch.results(
        in: [safari, report, custom],
        matching: "launch"
    )

    #expect(safariResults.map(\.id) == [safari.id])
    #expect(safariResults.first?.displayLabel == "Safari")
    #expect(safariResults.first?.matchKind == .exact)
    #expect(pathResults.map(\.id) == [report.id])
    #expect(pathResults.first?.matchKind == .wordPrefix)
    #expect(labelResults.map(\.id) == [custom.id])
    #expect(labelResults.first?.matchKind == .prefix)
}

@Test("Quick launch matching is case, width, diacritic, and whitespace tolerant")
func quickLaunchNormalizedMatching() {
    let resume = quickLaunchItem(1, label: "  Résumé   Writer  ")
    let fullWidth = quickLaunchItem(2, label: "Ｆｉｎｄｅｒ")

    let resumeResults = QuickLaunchSearch.results(
        in: [resume, fullWidth],
        matching: "resume writer"
    )
    let finderResults = QuickLaunchSearch.results(
        in: [resume, fullWidth],
        matching: "finder"
    )

    #expect(resumeResults.map(\.id) == [resume.id])
    #expect(resumeResults.first?.matchKind == .exact)
    #expect(finderResults.map(\.id) == [fullWidth.id])
    #expect(finderResults.first?.matchKind == .exact)
}

@Test("Quick launch tokens match across labels and paths in any order")
func quickLaunchTokenizedFieldMatching() {
    let annualPDF = quickLaunchItem(
        1,
        kind: .document,
        path: "/Users/example/Archive/Board-Packet.PDF",
        label: "Annual Report"
    )

    let forwardResults = QuickLaunchSearch.results(
        in: [annualPDF],
        matching: "annual pdf"
    )
    let reverseResults = QuickLaunchSearch.results(
        in: [annualPDF],
        matching: "  ＰＤＦ   ANNUAL  "
    )

    #expect(forwardResults.map(\.id) == [annualPDF.id])
    #expect(reverseResults.map(\.id) == [annualPDF.id])
    #expect(forwardResults.first?.matchKind == .wordPrefix)
    #expect(reverseResults.first?.matchKind == .wordPrefix)
}

@Test("Every quick launch token must match the same candidate")
func quickLaunchRequiresEveryToken() {
    let annualOnly = quickLaunchItem(
        1,
        kind: .document,
        path: "/Users/example/Annual Notes.txt",
        label: "Annual Notes"
    )
    let pdfOnly = quickLaunchItem(
        2,
        kind: .document,
        path: "/Users/example/Archive.pdf",
        label: "Quarterly Archive"
    )

    let results = QuickLaunchSearch.results(
        in: [annualOnly, pdfOnly],
        matching: "annual pdf"
    )

    #expect(results.isEmpty)
}

@Test("Tokenized quick launch ranking uses the weakest token match")
func quickLaunchTokenizedRanking() {
    let weaker = quickLaunchItem(1, label: "XalphaY Beta")
    let strongerFirst = quickLaunchItem(2, label: "Alpha Project Beta")
    let strongerSecond = quickLaunchItem(3, label: "Alpha Beta Notes")

    let results = QuickLaunchSearch.results(
        in: [weaker, strongerFirst, strongerSecond],
        matching: "beta alpha"
    )

    #expect(
        results.map(\.id) == [
            strongerFirst.id,
            strongerSecond.id,
            weaker.id,
        ]
    )
    #expect(
        results.map(\.matchKind) == [
            .wordPrefix,
            .wordPrefix,
            .substring,
        ]
    )
}

@Test("Quick launch returns no results for an unmatched query")
func quickLaunchNoMatch() {
    let results = QuickLaunchSearch.results(
        in: [
            quickLaunchItem(1, label: "Safari"),
            quickLaunchItem(2, label: "Notes"),
        ],
        matching: "Terminal"
    )

    #expect(results.isEmpty)
}

@Test("Quick launch selection moves in both directions with wraparound")
func quickLaunchSelectionWraparound() {
    let results = QuickLaunchSearch.results(
        in: [
            quickLaunchItem(1, label: "First"),
            quickLaunchItem(2, label: "Second"),
            quickLaunchItem(3, label: "Third"),
        ],
        matching: ""
    )
    var selection = QuickLaunchSelection()

    selection.reconcile(with: results)
    #expect(selection.selectedItemID == results[0].id)

    selection.move(.next, in: results)
    #expect(selection.selectedItemID == results[1].id)
    selection.move(.next, in: results)
    #expect(selection.selectedItemID == results[2].id)
    selection.move(.next, in: results)
    #expect(selection.selectedItemID == results[0].id)

    selection.move(.previous, in: results)
    #expect(selection.selectedItemID == results[2].id)
}

@Test("Quick launch selection reconciles safely when results change")
func quickLaunchSelectionReconciliation() {
    let allResults = QuickLaunchSearch.results(
        in: [
            quickLaunchItem(1, label: "First"),
            quickLaunchItem(2, label: "Second"),
            quickLaunchItem(3, label: "Third"),
        ],
        matching: ""
    )
    var selection = QuickLaunchSelection(
        selectedItemID: allResults[1].id
    )

    let retainedResults = [allResults[1], allResults[2]]
    selection.reconcile(with: retainedResults)
    #expect(selection.selectedItemID == allResults[1].id)
    #expect(selection.selectedResult(in: retainedResults) == allResults[1])

    let replacementResults = [allResults[2]]
    selection.reconcile(with: replacementResults)
    #expect(selection.selectedItemID == allResults[2].id)

    selection.reconcile(with: [])
    #expect(selection.selectedItemID == nil)
    #expect(selection.selectedResult(in: []) == nil)
}

@Test("Quick launch navigation recovers from an absent selection")
func quickLaunchMissingSelectionNavigation() {
    let results = QuickLaunchSearch.results(
        in: [
            quickLaunchItem(1, label: "First"),
            quickLaunchItem(2, label: "Second"),
        ],
        matching: ""
    )
    var selection = QuickLaunchSelection(
        selectedItemID: quickLaunchID(99)
    )

    selection.move(.previous, in: results)
    #expect(selection.selectedItemID == results[1].id)

    selection = QuickLaunchSelection(selectedItemID: quickLaunchID(99))
    selection.move(.next, in: results)
    #expect(selection.selectedItemID == results[0].id)

    selection.move(.next, in: [])
    #expect(selection.selectedItemID == nil)
}

private func quickLaunchItem(
    _ id: Int,
    kind: DockItemKind = .application,
    path: String? = nil,
    label: String?
) -> DockItem {
    DockItem(
        id: quickLaunchID(id),
        kind: kind,
        path: path ?? "/tmp/\(id).app",
        label: label
    )
}

private func quickLaunchID(_ value: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
}
