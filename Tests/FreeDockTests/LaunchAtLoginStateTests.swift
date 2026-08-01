import Testing
@testable import FreeDock

@Suite("Launch at login preference state")
struct LaunchAtLoginStateTests {
    @Test("Enabled and approval states keep the toggle on")
    func enabledStates() {
        #expect(LaunchAtLoginState(status: .enabled).isEnabled)
        #expect(LaunchAtLoginState(status: .requiresApproval).isEnabled)
        #expect(!LaunchAtLoginState(status: .disabled).isEnabled)
    }

    @Test("Approval and availability produce useful presentation")
    func presentation() {
        let approval = LaunchAtLoginState(status: .requiresApproval)
        #expect(approval.needsApproval)
        #expect(approval.statusLabel == "Needs Approval")

        let unavailable = LaunchAtLoginState(status: .unavailable)
        #expect(!unavailable.canChange)
        #expect(unavailable.statusLabel.contains("macOS 13"))
    }

    @Test("Errors do not discard the actual service status")
    func errorState() {
        let state = LaunchAtLoginState(
            status: .disabled,
            errorMessage: "Registration failed"
        )
        #expect(!state.isEnabled)
        #expect(state.errorMessage == "Registration failed")
    }
}
