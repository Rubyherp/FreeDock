import AppKit
import ServiceManagement

enum LaunchAtLoginController {
    static var state: LaunchAtLoginState {
        guard #available(macOS 13.0, *) else {
            return LaunchAtLoginState(status: .unavailable)
        }

        switch SMAppService.mainApp.status {
        case .enabled:
            return LaunchAtLoginState(status: .enabled)
        case .requiresApproval:
            return LaunchAtLoginState(status: .requiresApproval)
        case .notRegistered, .notFound:
            return LaunchAtLoginState(status: .disabled)
        @unknown default:
            return LaunchAtLoginState(status: .disabled)
        }
    }

    static func setEnabled(_ enabled: Bool) -> LaunchAtLoginState {
        guard #available(macOS 13.0, *) else {
            return LaunchAtLoginState(status: .unavailable)
        }

        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return state
        } catch {
            var current = state
            current.errorMessage = error.localizedDescription
            return current
        }
    }

    static func openSystemSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}
