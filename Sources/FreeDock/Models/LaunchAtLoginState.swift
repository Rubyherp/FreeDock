import Foundation

enum LaunchAtLoginStatus: Equatable, Sendable {
    case disabled
    case enabled
    case requiresApproval
    case unavailable
}

struct LaunchAtLoginState: Equatable, Sendable {
    var status: LaunchAtLoginStatus
    var errorMessage: String?

    init(
        status: LaunchAtLoginStatus = .disabled,
        errorMessage: String? = nil
    ) {
        self.status = status
        self.errorMessage = errorMessage
    }

    var isEnabled: Bool {
        status == .enabled || status == .requiresApproval
    }

    var canChange: Bool {
        status != .unavailable
    }

    var needsApproval: Bool {
        status == .requiresApproval
    }

    var statusLabel: String {
        switch status {
        case .disabled:
            return "Off"
        case .enabled:
            return "On"
        case .requiresApproval:
            return "Needs Approval"
        case .unavailable:
            return "Requires macOS 13 or later"
        }
    }
}
