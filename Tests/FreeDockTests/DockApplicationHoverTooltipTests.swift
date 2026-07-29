import Testing
@testable import FreeDock

@Suite("Dock application hover tooltip")
struct DockApplicationHoverTooltipTests {
    @Test("Enabled window switching uses the normal application name")
    func enabledSwitchingUsesApplicationName() {
        #expect(
            DockApplicationHoverTooltip.text(
                displayName: "Firefox",
                isWindowSwitchingEnabled: true,
                isThumbnailCaptureEnabled: true
            ) == "Firefox"
        )
    }

    @Test("Missing thumbnail permission does not look like a window error")
    func missingThumbnailsStillUseApplicationName() {
        #expect(
            DockApplicationHoverTooltip.text(
                displayName: "Firefox",
                isWindowSwitchingEnabled: true,
                isThumbnailCaptureEnabled: false
            ) == "Firefox"
        )
    }

    @Test("Missing switching permission keeps the setup instruction")
    func missingSwitchingPermissionShowsInstruction() {
        #expect(
            DockApplicationHoverTooltip.text(
                displayName: "Firefox",
                isWindowSwitchingEnabled: false,
                isThumbnailCaptureEnabled: false
            ) == "Right-click to enable window switching"
        )
    }
}
