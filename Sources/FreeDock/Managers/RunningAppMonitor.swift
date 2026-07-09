import Cocoa
import Combine

@MainActor
class RunningAppMonitor: ObservableObject {
    static let shared = RunningAppMonitor()

    @Published var runningBundleIDs: Set<String> = []

    private init() {
        refresh()
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(self, selector: #selector(refresh),
                       name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        nc.addObserver(self, selector: #selector(refresh),
                       name: NSWorkspace.didTerminateApplicationNotification, object: nil)
    }

    @objc func refresh() {
        runningBundleIDs = Set(
            NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier }
        )
    }
}
