import Cocoa
import Combine

@MainActor
class RunningAppMonitor: ObservableObject {
    static let shared = RunningAppMonitor()

    @Published private(set) var runningBundleIDs: Set<String> = []
    private var runningApplicationsObservation: AnyCancellable?

    private static let applicationChangeNotifications: [Notification.Name] = [
        NSWorkspace.didLaunchApplicationNotification,
        NSWorkspace.didTerminateApplicationNotification,
        NSWorkspace.didHideApplicationNotification,
        NSWorkspace.didUnhideApplicationNotification,
        NSWorkspace.didActivateApplicationNotification,
        NSWorkspace.didDeactivateApplicationNotification,
    ]

    private init() {
        refresh()
        let notificationCenter = NSWorkspace.shared.notificationCenter
        for name in Self.applicationChangeNotifications {
            notificationCenter.addObserver(
                self,
                selector: #selector(applicationDidChange(_:)),
                name: name,
                object: nil
            )
        }
        runningApplicationsObservation = NSWorkspace.shared
            .publisher(for: \.runningApplications)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refresh()
                }
            }
    }

    func refresh() {
        // Assign unconditionally so @Published emits for visibility and focus
        // changes even when the set of running bundle IDs stays the same.
        runningBundleIDs = Set(
            NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy != .prohibited }
                .compactMap(\.bundleIdentifier)
        )
    }

    @objc private func applicationDidChange(_ notification: Notification) {
        refresh()
    }
}
