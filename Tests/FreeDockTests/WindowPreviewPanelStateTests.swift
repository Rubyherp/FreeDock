import Foundation
import Testing
@testable import FreeDock

@Suite("Window preview panel state")
struct WindowPreviewPanelStateTests {
    @Test("Permission loss chooses a safe preview fallback")
    func permissionFallbacks() {
        #expect(
            WindowPreviewPermissionPolicy.fallback(
                accessibilityTrusted: false,
                screenCaptureTrusted: false
            ) == .closePreview
        )
        #expect(
            WindowPreviewPermissionPolicy.fallback(
                accessibilityTrusted: false,
                screenCaptureTrusted: true
            ) == .closePreview
        )
        #expect(
            WindowPreviewPermissionPolicy.fallback(
                accessibilityTrusted: true,
                screenCaptureTrusted: false
            ) == .metadataOnly
        )
        #expect(
            WindowPreviewPermissionPolicy.fallback(
                accessibilityTrusted: true,
                screenCaptureTrusted: true
            ) == .fullPreview
        )
    }

    @Test("Ready queries with cards are accepted")
    func readyQueryIsAccepted() {
        #expect(
            WindowPreviewPanelQueryPolicy.decision(
                for: .ready,
                windowCount: 2,
                retryAttempt: 0
            ) == .accept
        )
    }

    @Test("Transient queries retry with bounded backoff")
    func transientQueryRetries() {
        #expect(
            WindowPreviewPanelQueryPolicy.decision(
                for: .temporarilyUnavailable,
                windowCount: 0,
                retryAttempt: 0
            ) == .retry(afterNanoseconds: 250_000_000)
        )
        #expect(
            WindowPreviewPanelQueryPolicy.decision(
                for: .temporarilyUnavailable,
                windowCount: 0,
                retryAttempt: 1
            ) == .retry(afterNanoseconds: 500_000_000)
        )
        #expect(
            WindowPreviewPanelQueryPolicy.decision(
                for: .temporarilyUnavailable,
                windowCount: 0,
                retryAttempt: 2
            ) == .retry(afterNanoseconds: 1_000_000_000)
        )
        #expect(
            WindowPreviewPanelQueryPolicy.decision(
                for: .temporarilyUnavailable,
                windowCount: 0,
                retryAttempt: 20
            ) == .retry(afterNanoseconds: 1_500_000_000)
        )
    }

    @Test("Terminal and empty queries close")
    func terminalQueriesClose() {
        #expect(
            WindowPreviewPanelQueryPolicy.decision(
                for: .ready,
                windowCount: 0,
                retryAttempt: 0
            ) == .close
        )
        #expect(
            WindowPreviewPanelQueryPolicy.decision(
                for: .permissionRequired,
                windowCount: 2,
                retryAttempt: 0
            ) == .close
        )
        #expect(
            WindowPreviewPanelQueryPolicy.decision(
                for: .applicationNotRunning,
                windowCount: 2,
                retryAttempt: 0
            ) == .close
        )
    }

    @Test("A queued global click only closes its original session")
    func globalClickIsSessionSafe() {
        let monitoredSessionID = UUID()

        #expect(
            WindowPreviewPanelEventPolicy
                .shouldCloseForGlobalClick(
                    monitoredSessionID: monitoredSessionID,
                    currentSessionID: monitoredSessionID
                )
        )
        #expect(
            !WindowPreviewPanelEventPolicy
                .shouldCloseForGlobalClick(
                    monitoredSessionID: monitoredSessionID,
                    currentSessionID: UUID()
                )
        )
        #expect(
            !WindowPreviewPanelEventPolicy
                .shouldCloseForGlobalClick(
                    monitoredSessionID: monitoredSessionID,
                    currentSessionID: nil
                )
        )
        #expect(
            !WindowPreviewPanelEventPolicy
                .shouldCloseForGlobalClick(
                    monitoredSessionID: nil,
                    currentSessionID: monitoredSessionID
                )
        )
    }

    @Test("Panel sizing fits card labels and caps visible columns")
    func preferredPanelSizing() {
        let empty = WindowPreviewPanelSizing.preferredSize(
            windowCount: 0
        )
        let single = WindowPreviewPanelSizing.preferredSize(
            windowCount: 1
        )
        let three = WindowPreviewPanelSizing.preferredSize(
            windowCount: 3
        )
        let many = WindowPreviewPanelSizing.preferredSize(
            windowCount: 12
        )

        #expect(empty == single)
        #expect(single == CGSize(width: 202, height: 194))
        #expect(three == CGSize(width: 566, height: 194))
        #expect(many == three)
    }

    @Test("Thumbnail states distinguish permission, progress, and failure")
    func thumbnailStates() {
        #expect(
            thumbnailState(
                hasThumbnail: true,
                isCaptureEnabled: false
            ) == .permissionRequired
        )
        #expect(
            thumbnailState(
                hasThumbnail: true
            ) == .available
        )
        #expect(
            thumbnailState(
                isLoading: true
            ) == .loading
        )
        #expect(
            thumbnailState(
                isUnavailable: true
            ) == .unavailable
        )
        #expect(
            thumbnailState(
                hasCaptureWindow: false
            ) == .unavailable
        )
        #expect(thumbnailState() == .loading)
    }

    private func thumbnailState(
        hasThumbnail: Bool = false,
        isCaptureEnabled: Bool = true,
        isLoading: Bool = false,
        isUnavailable: Bool = false,
        hasCaptureWindow: Bool = true
    ) -> WindowPreviewThumbnailState {
        WindowPreviewThumbnailState.resolve(
            hasThumbnail: hasThumbnail,
            isCaptureEnabled: isCaptureEnabled,
            isLoading: isLoading,
            isUnavailable: isUnavailable,
            hasCaptureWindow: hasCaptureWindow
        )
    }
}
