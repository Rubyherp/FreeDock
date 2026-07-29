import CoreGraphics
import Foundation

struct DockApplicationWindow: Identifiable, Equatable, Sendable {
    let id: UUID
    let applicationInstanceID: UUID
    let applicationName: String
    let title: String
    let captureWindowID: CGWindowID?
    let isMinimized: Bool
    let isApplicationHidden: Bool
    let isOnScreen: Bool?
    let canFocusExactly: Bool
    let isMain: Bool
    let isFocused: Bool
}

enum DockApplicationWindowQueryStatus: Equatable, Sendable {
    case ready
    case permissionRequired
    case applicationNotRunning
    case temporarilyUnavailable
}

struct DockApplicationWindowQuery: Equatable, Sendable {
    let status: DockApplicationWindowQueryStatus
    let windows: [DockApplicationWindow]
}

enum DockApplicationWindowFocusResult: Equatable, Sendable {
    case accepted
    case permissionRequired
    case staleWindow
    case applicationNotRunning
    case temporarilyUnavailable
    case unsupported
    case activationRejected
}

enum DockApplicationWindowRole: Equatable, Sendable {
    case standard
    case dialog
    case systemDialog
    case other
}

struct DockApplicationWindowCandidate: Equatable, Sendable {
    let id: UUID
    let applicationInstanceID: UUID
    let processIdentifier: pid_t
    let applicationName: String
    let title: String?
    let documentPath: String?
    let frame: CGRect?
    let role: DockApplicationWindowRole
    let isMinimized: Bool
    let isApplicationHidden: Bool
    let isApplicationActive: Bool
    let isMain: Bool
    let isFocused: Bool
    let sourceOrder: Int
}

struct DockWindowServerWindow: Equatable, Sendable {
    let windowID: CGWindowID
    let processIdentifier: pid_t
    let title: String?
    let frame: CGRect
    let isOnScreen: Bool
    let sourceOrder: Int
}

enum DockApplicationWindowFocusStep: Equatable, Sendable {
    case unhideApplication
    case restoreWindow
    case makeMain
    case setFocusedWindow
    case activateApplication
    case raiseWindow
}

enum DockApplicationWindowPlanner {
    struct Match: Equatable, Hashable, Sendable {
        let accessibilityWindowID: UUID
        let captureWindowID: CGWindowID
    }

    static func windows(
        from candidates: [DockApplicationWindowCandidate],
        captureWindows: [DockWindowServerWindow] = []
    ) -> [DockApplicationWindow] {
        let selected = selectedCandidates(from: candidates)
        let matches = captureMatches(
            candidates: selected,
            captureWindows: captureWindows
        )
        let captureIDByAccessibilityID = Dictionary(
            uniqueKeysWithValues: matches.map {
                ($0.accessibilityWindowID, $0.captureWindowID)
            }
        )
        let captureByID = Dictionary(
            uniqueKeysWithValues: captureWindows.map {
                ($0.windowID, $0)
            }
        )

        return selected
            .sorted(by: orderedBefore)
            .map { candidate in
                let captureID =
                    captureIDByAccessibilityID[candidate.id]
                let capture = captureID.flatMap {
                    captureByID[$0]
                }
                return DockApplicationWindow(
                    id: candidate.id,
                    applicationInstanceID:
                        candidate.applicationInstanceID,
                    applicationName: candidate.applicationName,
                    title: resolvedTitle(for: candidate),
                    captureWindowID: captureID,
                    isMinimized: candidate.isMinimized,
                    isApplicationHidden:
                        candidate.isApplicationHidden,
                    isOnScreen: capture?.isOnScreen,
                    canFocusExactly: true,
                    isMain: candidate.isMain,
                    isFocused: candidate.isFocused
                )
            }
    }

    static func selectedCandidates(
        from candidates: [DockApplicationWindowCandidate]
    ) -> [DockApplicationWindowCandidate] {
        candidates.filter { $0.role != .systemDialog }
    }

    static func captureMatches(
        candidates: [DockApplicationWindowCandidate],
        captureWindows: [DockWindowServerWindow]
    ) -> [Match] {
        var unusedCaptureIDs = Set(
            captureWindows.map(\.windowID)
        )
        var matches: [Match] = []

        for candidate in candidates.sorted(by: orderedBefore) {
            let available = captureWindows.filter {
                unusedCaptureIDs.contains($0.windowID)
                    && $0.processIdentifier
                        == candidate.processIdentifier
            }
            guard let capture = bestCaptureMatch(
                for: candidate,
                among: available,
                allCandidates: candidates
            ) else {
                continue
            }
            unusedCaptureIDs.remove(capture.windowID)
            matches.append(
                Match(
                    accessibilityWindowID: candidate.id,
                    captureWindowID: capture.windowID
                )
            )
        }
        return matches
    }

    static func unrepresentedCaptureWindows(
        candidates: [DockApplicationWindowCandidate],
        captureWindows: [DockWindowServerWindow]
    ) -> [DockWindowServerWindow] {
        let matches = captureMatches(
            candidates: selectedCandidates(from: candidates),
            captureWindows: captureWindows
        )
        let matchedCandidateIDs = Set(
            matches.map(\.accessibilityWindowID)
        )
        let matchedCaptureIDs = Set(
            matches.map(\.captureWindowID)
        )
        var remainingCandidates = candidates.filter {
            !matchedCandidateIDs.contains($0.id)
        }
        var result: [DockWindowServerWindow] = []

        for capture in captureWindows where
            !matchedCaptureIDs.contains(capture.windowID)
        {
            if let index = representationIndex(
                for: capture,
                in: remainingCandidates
            ) {
                remainingCandidates.remove(at: index)
            } else {
                result.append(capture)
            }
        }
        return result
    }

    static func retainedCandidates(
        from candidates: [DockApplicationWindowCandidate],
        applicationInstanceID: UUID,
        applicationName: String,
        isApplicationHidden: Bool,
        isApplicationActive: Bool,
        startingSourceOrder: Int
    ) -> [DockApplicationWindowCandidate] {
        candidates
            .filter {
                $0.applicationInstanceID == applicationInstanceID
            }
            .sorted {
                if $0.sourceOrder != $1.sourceOrder {
                    return $0.sourceOrder < $1.sourceOrder
                }
                return $0.id.uuidString < $1.id.uuidString
            }
            .enumerated()
            .map { offset, candidate in
                DockApplicationWindowCandidate(
                    id: candidate.id,
                    applicationInstanceID:
                        candidate.applicationInstanceID,
                    processIdentifier: candidate.processIdentifier,
                    applicationName: applicationName,
                    title: candidate.title,
                    documentPath: candidate.documentPath,
                    frame: candidate.frame,
                    role: candidate.role,
                    isMinimized: candidate.isMinimized,
                    isApplicationHidden: isApplicationHidden,
                    isApplicationActive: isApplicationActive,
                    isMain: candidate.isMain,
                    isFocused: candidate.isFocused,
                    sourceOrder: startingSourceOrder + offset
                )
            }
    }

    static func nativeQueryStatus(
        successfulQueryCount: Int,
        temporaryFailureCount: Int,
        retainedCandidateCount: Int
    ) -> DockApplicationWindowQueryStatus {
        if successfulQueryCount > 0 || retainedCandidateCount > 0 {
            return .ready
        }
        return temporaryFailureCount > 0
            ? .temporarilyUnavailable
            : .ready
    }

    static func focusSteps(
        for window: DockApplicationWindow
    ) -> [DockApplicationWindowFocusStep] {
        var steps: [DockApplicationWindowFocusStep] = []
        if window.isApplicationHidden {
            steps.append(.unhideApplication)
        }
        if window.isMinimized {
            steps.append(.restoreWindow)
        }
        steps.append(contentsOf: [
            .makeMain,
            .setFocusedWindow,
            .activateApplication,
            .raiseWindow,
        ])
        return steps
    }

    private static func orderedBefore(
        _ lhs: DockApplicationWindowCandidate,
        _ rhs: DockApplicationWindowCandidate
    ) -> Bool {
        let lhsRank = (
            lhs.isFocused ? 0 : 1,
            lhs.isMain ? 0 : 1,
            lhs.isApplicationActive ? 0 : 1,
            lhs.isMinimized ? 1 : 0,
            lhs.sourceOrder
        )
        let rhsRank = (
            rhs.isFocused ? 0 : 1,
            rhs.isMain ? 0 : 1,
            rhs.isApplicationActive ? 0 : 1,
            rhs.isMinimized ? 1 : 0,
            rhs.sourceOrder
        )
        return lhsRank < rhsRank
    }

    private static func bestCaptureMatch(
        for candidate: DockApplicationWindowCandidate,
        among windows: [DockWindowServerWindow],
        allCandidates: [DockApplicationWindowCandidate]
    ) -> DockWindowServerWindow? {
        guard !windows.isEmpty else { return nil }

        let frameMatches = candidate.frame.map { frame in
            windows.filter {
                frameDistance(frame, $0.frame) <= 12
            }
        } ?? []
        let candidateTitle = normalizedTitle(candidate.title)
        let titleMatches = windows.filter {
            candidateTitle != nil
                && normalizedTitle($0.title) == candidateTitle
        }

        if let match = uniqueIntersection(
            frameMatches,
            titleMatches
        ) {
            return match
        }
        if frameMatches.count == 1 {
            return frameMatches[0]
        }
        if titleMatches.count == 1 {
            let sameTitleCandidateCount = allCandidates.filter {
                $0.processIdentifier == candidate.processIdentifier
                    && normalizedTitle($0.title) == candidateTitle
            }.count
            if sameTitleCandidateCount == 1 {
                return titleMatches[0]
            }
        }

        let sameProcessCandidateCount = allCandidates.filter {
            $0.processIdentifier == candidate.processIdentifier
        }.count
        if windows.count == 1, sameProcessCandidateCount == 1 {
            return windows[0]
        }
        return nil
    }

    private static func uniqueIntersection(
        _ lhs: [DockWindowServerWindow],
        _ rhs: [DockWindowServerWindow]
    ) -> DockWindowServerWindow? {
        let rhsIDs = Set(rhs.map(\.windowID))
        let matches = lhs.filter {
            rhsIDs.contains($0.windowID)
        }
        return matches.count == 1 ? matches[0] : nil
    }

    private static func representationIndex(
        for capture: DockWindowServerWindow,
        in candidates: [DockApplicationWindowCandidate]
    ) -> Int? {
        let sameProcessIndices = candidates.indices.filter {
            candidates[$0].processIdentifier
                == capture.processIdentifier
        }
        if let index = sameProcessIndices.first(where: {
            candidates[$0].frame.map {
                frameDistance($0, capture.frame) <= 12
            } ?? false
        }) {
            return index
        }
        if let index = sameProcessIndices.first(where: {
            let candidateTitle = normalizedTitle(
                candidates[$0].title
            )
            return candidateTitle != nil
                && candidateTitle
                    == normalizedTitle(capture.title)
        }) {
            return index
        }
        return sameProcessIndices.first {
            candidates[$0].frame == nil
                && normalizedTitle(candidates[$0].title) == nil
        }
    }

    private static func frameDistance(
        _ lhs: CGRect,
        _ rhs: CGRect
    ) -> CGFloat {
        abs(lhs.minX - rhs.minX)
            + abs(lhs.minY - rhs.minY)
            + abs(lhs.width - rhs.width)
            + abs(lhs.height - rhs.height)
    }

    private static func normalizedTitle(
        _ title: String?
    ) -> String? {
        title?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            )
            .nilIfEmpty
    }

    private static func resolvedTitle(
        for candidate: DockApplicationWindowCandidate
    ) -> String {
        if let title = candidate.title?.trimmedNonEmpty {
            return title
        }
        if let path = candidate.documentPath?.trimmedNonEmpty {
            let name = URL(fileURLWithPath: path).lastPathComponent
            if let name = name.trimmedNonEmpty {
                return name
            }
        }
        return "Untitled \(candidate.applicationName) Window"
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let value = trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return value.isEmpty ? nil : value
    }

    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
