import CoreGraphics
import Foundation
import Testing
@testable import FreeDock

@Suite("Dock application windows")
struct DockApplicationWindowTests {
    @Test("All useful top-level windows remain while system dialogs do not")
    func allUsefulWindowsRemain() {
        let instanceID = UUID()
        let dialogID = UUID()
        let standardID = UUID()
        let windows = DockApplicationWindowPlanner.windows(
            from: [
                candidate(
                    id: dialogID,
                    instanceID: instanceID,
                    title: "Composition Surface",
                    role: .dialog
                ),
                candidate(
                    id: standardID,
                    instanceID: instanceID,
                    title: "Project",
                    role: .standard
                ),
                candidate(
                    id: UUID(),
                    instanceID: instanceID,
                    title: "Voice Controls",
                    role: .systemDialog
                ),
            ]
        )

        #expect(Set(windows.map(\.id)) == [dialogID, standardID])
    }

    @Test("Dialogs remain available when an instance has no standard window")
    func dialogFallback() {
        let instanceID = UUID()
        let dialogID = UUID()
        let windows = DockApplicationWindowPlanner.windows(
            from: [
                candidate(
                    id: dialogID,
                    instanceID: instanceID,
                    title: "Preferences",
                    role: .dialog
                ),
                candidate(
                    id: UUID(),
                    instanceID: instanceID,
                    title: "System",
                    role: .systemDialog
                ),
            ]
        )

        #expect(windows.map(\.id) == [dialogID])
    }

    @Test("Custom window subroles remain available as a final fallback")
    func customRoleFallback() {
        let instanceID = UUID()
        let customID = UUID()
        let windows = DockApplicationWindowPlanner.windows(
            from: [
                candidate(
                    id: customID,
                    instanceID: instanceID,
                    title: "Custom Window",
                    role: .other
                ),
                candidate(
                    id: UUID(),
                    instanceID: instanceID,
                    title: "System",
                    role: .systemDialog
                ),
            ]
        )

        #expect(windows.map(\.id) == [customID])
    }

    @Test("Duplicate titles and separate instances retain exact identities")
    func duplicateTitlesRemainSeparate() {
        let firstID = UUID()
        let secondID = UUID()
        let windows = DockApplicationWindowPlanner.windows(
            from: [
                candidate(
                    id: firstID,
                    instanceID: UUID(),
                    title: "Untitled"
                ),
                candidate(
                    id: secondID,
                    instanceID: UUID(),
                    title: "Untitled"
                ),
            ]
        )

        #expect(Set(windows.map(\.id)) == [firstID, secondID])
    }

    @Test("Titles fall back to document names and then an untitled label")
    func titleFallbacks() {
        let documentID = UUID()
        let untitledID = UUID()
        let windows = DockApplicationWindowPlanner.windows(
            from: [
                candidate(
                    id: documentID,
                    title: "   ",
                    documentPath: "/tmp/Project Notes.txt"
                ),
                candidate(
                    id: untitledID,
                    title: nil,
                    documentPath: nil
                ),
            ]
        )
        let byID = Dictionary(
            uniqueKeysWithValues: windows.map { ($0.id, $0) }
        )

        #expect(byID[documentID]?.title == "Project Notes.txt")
        #expect(
            byID[untitledID]?.title
                == "Untitled Example Window"
        )
    }

    @Test("Focused and main windows lead while minimized windows sort last")
    func nativeOrdering() {
        let focusedID = UUID()
        let mainID = UUID()
        let ordinaryID = UUID()
        let minimizedID = UUID()
        let instanceID = UUID()
        let windows = DockApplicationWindowPlanner.windows(
            from: [
                candidate(
                    id: minimizedID,
                    instanceID: instanceID,
                    title: "Minimized",
                    isMinimized: true,
                    sourceOrder: 0
                ),
                candidate(
                    id: ordinaryID,
                    instanceID: instanceID,
                    title: "Ordinary",
                    sourceOrder: 1
                ),
                candidate(
                    id: mainID,
                    instanceID: instanceID,
                    title: "Main",
                    isMain: true,
                    sourceOrder: 2
                ),
                candidate(
                    id: focusedID,
                    instanceID: instanceID,
                    title: "Focused",
                    isFocused: true,
                    sourceOrder: 3
                ),
            ]
        )

        #expect(
            windows.map(\.id)
                == [focusedID, mainID, ordinaryID, minimizedID]
        )
    }

    @Test("Focus planning restores hidden and minimized targets first")
    func focusPlanning() throws {
        let window = try #require(
            DockApplicationWindowPlanner.windows(
                from: [
                    candidate(
                        isMinimized: true,
                        isHidden: true
                    ),
                ]
            ).first
        )

        #expect(
            DockApplicationWindowPlanner.focusSteps(for: window)
                == [
                    .unhideApplication,
                    .restoreWindow,
                    .makeMain,
                    .setFocusedWindow,
                    .activateApplication,
                    .raiseWindow,
                ]
        )
    }

    @Test("Capture matching uses PID, title, and frame")
    func captureMatching() {
        let candidateID = UUID()
        let candidate = candidate(
            id: candidateID,
            processIdentifier: 42,
            title: "Project",
            frame: CGRect(x: 20, y: 30, width: 900, height: 700)
        )
        let matches = DockApplicationWindowPlanner.captureMatches(
            candidates: [candidate],
            captureWindows: [
                serverWindow(
                    id: 7,
                    processIdentifier: 99,
                    title: "Project",
                    frame: candidate.frame!
                ),
                serverWindow(
                    id: 8,
                    processIdentifier: 42,
                    title: "Project",
                    frame: candidate.frame!
                ),
            ]
        )

        #expect(
            matches == [
                DockApplicationWindowPlanner.Match(
                    accessibilityWindowID: candidateID,
                    captureWindowID: 8
                ),
            ]
        )
    }

    @Test("Explicit one-to-one frame and title evidence still matches")
    func explicitOneToOneEvidenceMatches() {
        let sharedFrame = CGRect(
            x: 20,
            y: 30,
            width: 900,
            height: 700
        )
        let frameCandidate = candidate(
            title: nil,
            frame: sharedFrame
        )
        let titleCandidate = candidate(
            title: "Project",
            frame: nil
        )

        #expect(
            DockApplicationWindowPlanner.captureMatches(
                candidates: [frameCandidate],
                captureWindows: [
                    serverWindow(
                        id: 9,
                        title: nil,
                        frame: sharedFrame
                    ),
                ]
            ).map(\.captureWindowID) == [9]
        )
        #expect(
            DockApplicationWindowPlanner.captureMatches(
                candidates: [titleCandidate],
                captureWindows: [
                    serverWindow(
                        id: 10,
                        title: "Project",
                        frame: CGRect(
                            x: 1_200,
                            y: 80,
                            width: 640,
                            height: 480
                        )
                    ),
                ]
            ).map(\.captureWindowID) == [10]
        )
    }

    @Test("A nonmatching offscreen capture remains independently discoverable")
    func nonmatchingOffscreenCaptureRemains() {
        let current = candidate(
            title: "Current Window",
            frame: CGRect(
                x: 20,
                y: 30,
                width: 900,
                height: 700
            ),
            isFocused: true
        )
        let otherDesktop = serverWindow(
            id: 11,
            title: "Other Desktop",
            frame: CGRect(
                x: -1_200,
                y: 80,
                width: 640,
                height: 480
            ),
            isOnScreen: false
        )

        #expect(
            DockApplicationWindowPlanner.captureMatches(
                candidates: [current],
                captureWindows: [otherDesktop]
            ).isEmpty
        )
        #expect(
            DockApplicationWindowPlanner
                .unrepresentedCaptureWindows(
                    candidates: [current],
                    captureWindows: [otherDesktop]
                )
                .map(\.windowID) == [11]
        )
    }

    @Test("Blank metadata is not representation evidence")
    func blankMetadataDoesNotDeduplicate() {
        let blankCandidate = candidate(
            title: nil,
            frame: nil
        )
        let blankCapture = serverWindow(
            id: 12,
            title: nil,
            isOnScreen: false
        )

        #expect(
            DockApplicationWindowPlanner.captureMatches(
                candidates: [blankCandidate],
                captureWindows: [blankCapture]
            ).isEmpty
        )
        #expect(
            DockApplicationWindowPlanner
                .unrepresentedCaptureWindows(
                    candidates: [blankCandidate],
                    captureWindows: [blankCapture]
                )
                .map(\.windowID) == [12]
        )
    }

    @Test("Focused and main AX windows consume the on-screen equal frame")
    func currentWindowWinsEqualFrameAmbiguity() {
        let sharedFrame = CGRect(
            x: 0,
            y: 0,
            width: 1_440,
            height: 900
        )
        let currentCapture = serverWindow(
            id: 13,
            title: nil,
            frame: sharedFrame,
            isOnScreen: true
        )
        let otherDesktopCapture = serverWindow(
            id: 14,
            title: nil,
            frame: sharedFrame,
            isOnScreen: false
        )
        let candidates = [
            candidate(
                title: nil,
                frame: sharedFrame,
                isFocused: true
            ),
            candidate(
                title: nil,
                frame: sharedFrame,
                isMain: true
            ),
        ]
        let captureOrders = [
            [otherDesktopCapture, currentCapture],
            [currentCapture, otherDesktopCapture],
        ]

        for candidate in candidates {
            for captures in captureOrders {
                #expect(
                    DockApplicationWindowPlanner.captureMatches(
                        candidates: [candidate],
                        captureWindows: captures
                    ).map(\.captureWindowID) == [13]
                )
                #expect(
                    DockApplicationWindowPlanner
                        .unrepresentedCaptureWindows(
                            candidates: [candidate],
                            captureWindows: captures
                        )
                        .map(\.windowID) == [14]
                )
            }
        }
    }

    @Test("Duplicate titles are disambiguated by frame")
    func duplicateTitleCaptureMatching() {
        let firstID = UUID()
        let secondID = UUID()
        let matches = DockApplicationWindowPlanner.captureMatches(
            candidates: [
                candidate(
                    id: firstID,
                    title: "Untitled",
                    frame: CGRect(
                        x: -1200,
                        y: 20,
                        width: 800,
                        height: 600
                    )
                ),
                candidate(
                    id: secondID,
                    title: "Untitled",
                    frame: CGRect(
                        x: 40,
                        y: 60,
                        width: 1000,
                        height: 700
                    )
                ),
            ],
            captureWindows: [
                serverWindow(
                    id: 10,
                    title: "Untitled",
                    frame: CGRect(
                        x: 41,
                        y: 60,
                        width: 1000,
                        height: 700
                    )
                ),
                serverWindow(
                    id: 11,
                    title: "Untitled",
                    frame: CGRect(
                        x: -1200,
                        y: 20,
                        width: 800,
                        height: 600
                    )
                ),
            ]
        )

        #expect(
            Set(matches) == Set([
                DockApplicationWindowPlanner.Match(
                    accessibilityWindowID: firstID,
                    captureWindowID: 11
                ),
                DockApplicationWindowPlanner.Match(
                    accessibilityWindowID: secondID,
                    captureWindowID: 10
                ),
            ])
        )
    }

    @Test("Ambiguous duplicate titles do not receive the wrong capture")
    func ambiguousCaptureDoesNotMatch() {
        let matches = DockApplicationWindowPlanner.captureMatches(
            candidates: [
                candidate(title: "Untitled", frame: nil),
                candidate(title: "Untitled", frame: nil),
            ],
            captureWindows: [
                serverWindow(id: 20, title: "Untitled"),
                serverWindow(id: 21, title: "Untitled"),
            ]
        )

        #expect(matches.isEmpty)
    }

    @Test("Ambiguous catalogs preserve extra WindowServer windows once")
    func ambiguousCatalogPreservesExtraWindows() {
        let candidates = [
            candidate(title: "Untitled", frame: nil),
            candidate(title: "Untitled", frame: nil),
        ]
        let captures = [
            serverWindow(id: 30, title: "Untitled"),
            serverWindow(id: 31, title: "Untitled"),
            serverWindow(id: 32, title: "Untitled"),
        ]

        let unrepresented =
            DockApplicationWindowPlanner
                .unrepresentedCaptureWindows(
                    candidates: candidates,
                    captureWindows: captures
                )

        #expect(unrepresented.map(\.windowID) == [32])
    }

    @Test("Duplicate frames consume accessible windows only once")
    func duplicateFramesPreserveExtraWindows() {
        let sharedFrame = CGRect(
            x: 24,
            y: 36,
            width: 900,
            height: 700
        )
        let candidates = [
            candidate(title: nil, frame: sharedFrame),
            candidate(title: nil, frame: sharedFrame),
        ]
        let captures = [
            serverWindow(id: 33, title: nil, frame: sharedFrame),
            serverWindow(id: 34, title: nil, frame: sharedFrame),
            serverWindow(id: 35, title: nil, frame: sharedFrame),
        ]

        let unrepresented =
            DockApplicationWindowPlanner
                .unrepresentedCaptureWindows(
                    candidates: candidates,
                    captureWindows: captures
                )

        #expect(unrepresented.map(\.windowID) == [35])
    }

    @Test("Representation matching remains isolated by process")
    func representationMatchingUsesProcessIdentifier() {
        let candidates = [
            candidate(
                processIdentifier: 42,
                title: "Untitled",
                frame: nil
            ),
        ]
        let captures = [
            serverWindow(
                id: 36,
                processIdentifier: 99,
                title: "Untitled"
            ),
            serverWindow(
                id: 37,
                processIdentifier: 42,
                title: "Untitled"
            ),
        ]

        let unrepresented =
            DockApplicationWindowPlanner
                .unrepresentedCaptureWindows(
                    candidates: candidates,
                    captureWindows: captures
                )

        #expect(unrepresented.map(\.windowID) == [36])
    }

    @Test("Excluded system dialogs are not reintroduced by capture fallback")
    func systemDialogsStayExcluded() {
        let frame = CGRect(
            x: 40,
            y: 50,
            width: 420,
            height: 260
        )
        let unrepresented =
            DockApplicationWindowPlanner
                .unrepresentedCaptureWindows(
                    candidates: [
                        candidate(
                            title: "System Dialog",
                            frame: frame,
                            role: .systemDialog
                        ),
                    ],
                    captureWindows: [
                        serverWindow(
                            id: 40,
                            title: "System Dialog",
                            frame: frame
                        ),
                    ]
                )

        #expect(unrepresented.isEmpty)
    }

    @Test("Genuinely missing accessible windows remain discoverable")
    func missingAccessibleWindowRemains() {
        let unrepresented =
            DockApplicationWindowPlanner
                .unrepresentedCaptureWindows(
                    candidates: [
                        candidate(title: "First"),
                    ],
                    captureWindows: [
                        serverWindow(id: 50, title: "First"),
                        serverWindow(id: 51, title: "Second"),
                    ]
                )

        #expect(unrepresented.map(\.windowID) == [51])
    }

    @Test("Transient snapshots retain identity and rebase dynamic state")
    func transientSnapshotsRemainStable() {
        let instanceID = UUID()
        let firstID = UUID()
        let secondID = UUID()
        let retained =
            DockApplicationWindowPlanner.retainedCandidates(
                from: [
                    candidate(
                        id: firstID,
                        instanceID: instanceID,
                        title: "Later",
                        isHidden: false,
                        isActive: false,
                        sourceOrder: 12
                    ),
                    candidate(
                        id: secondID,
                        instanceID: instanceID,
                        title: "Earlier",
                        isHidden: false,
                        isActive: false,
                        sourceOrder: 4
                    ),
                    candidate(
                        instanceID: UUID(),
                        title: "Different process",
                        sourceOrder: 0
                    ),
                ],
                applicationInstanceID: instanceID,
                applicationName: "Renamed Example",
                isApplicationHidden: true,
                isApplicationActive: true,
                startingSourceOrder: 7
            )

        #expect(retained.map(\.id) == [secondID, firstID])
        #expect(retained.map(\.sourceOrder) == [7, 8])
        #expect(
            retained.allSatisfy {
                $0.applicationName == "Renamed Example"
                    && $0.isApplicationHidden
                    && $0.isApplicationActive
            }
        )
        #expect(retained.map(\.title) == ["Earlier", "Later"])
    }

    @Test("A retained snapshot keeps transient queries displayable")
    func retainedSnapshotMakesQueryReady() {
        #expect(
            DockApplicationWindowPlanner.nativeQueryStatus(
                successfulQueryCount: 0,
                temporaryFailureCount: 1,
                retainedCandidateCount: 2
            ) == .ready
        )
        #expect(
            DockApplicationWindowPlanner.nativeQueryStatus(
                successfulQueryCount: 0,
                temporaryFailureCount: 1,
                retainedCandidateCount: 0
            ) == .temporarilyUnavailable
        )
        #expect(
            DockApplicationWindowPlanner.nativeQueryStatus(
                successfulQueryCount: 1,
                temporaryFailureCount: 1,
                retainedCandidateCount: 0
            ) == .ready
        )
    }

    private func candidate(
        id: UUID = UUID(),
        instanceID: UUID = UUID(),
        processIdentifier: pid_t = 42,
        title: String? = "Window",
        documentPath: String? = nil,
        frame: CGRect? = nil,
        role: DockApplicationWindowRole = .standard,
        isMinimized: Bool = false,
        isHidden: Bool = false,
        isActive: Bool = false,
        isMain: Bool = false,
        isFocused: Bool = false,
        sourceOrder: Int = 0
    ) -> DockApplicationWindowCandidate {
        DockApplicationWindowCandidate(
            id: id,
            applicationInstanceID: instanceID,
            processIdentifier: processIdentifier,
            applicationName: "Example",
            title: title,
            documentPath: documentPath,
            frame: frame,
            role: role,
            isMinimized: isMinimized,
            isApplicationHidden: isHidden,
            isApplicationActive: isActive,
            isMain: isMain,
            isFocused: isFocused,
            sourceOrder: sourceOrder
        )
    }

    private func serverWindow(
        id: CGWindowID,
        processIdentifier: pid_t = 42,
        title: String? = "Window",
        frame: CGRect = CGRect(
            x: 0,
            y: 0,
            width: 800,
            height: 600
        ),
        isOnScreen: Bool = true
    ) -> DockWindowServerWindow {
        DockWindowServerWindow(
            windowID: id,
            processIdentifier: processIdentifier,
            title: title,
            frame: frame,
            isOnScreen: isOnScreen,
            sourceOrder: Int(id)
        )
    }
}
