import Cocoa
import Combine

@MainActor
class RunningAppMonitor: ObservableObject {
    static let shared = RunningAppMonitor()

    @Published private(set) var runningBundleIDs: Set<String> = []
    @Published private(set) var recentApplications: [RecentApplicationRecord] = []
    private var runningApplicationsObservation: AnyCancellable?
    private var onRecentApplicationsChanged: (([RecentApplicationRecord]) -> Void)?

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

    func configureRecentApplications(
        _ records: [RecentApplicationRecord],
        onChange: @escaping ([RecentApplicationRecord]) -> Void
    ) {
        recentApplications = RecentApplicationHistoryPlanner.normalized(records)
        onRecentApplicationsChanged = onChange
        for application in NSWorkspace.shared.runningApplications
            where application.activationPolicy == .regular
        {
            record(application, usedAt: .distantPast, preservesExistingDate: true)
        }
    }

    @objc private func applicationDidChange(_ notification: Notification) {
        refresh()
        guard notification.name == NSWorkspace.didLaunchApplicationNotification
                || notification.name == NSWorkspace.didActivateApplicationNotification,
              let application = notification.userInfo?[
                NSWorkspace.applicationUserInfoKey
              ] as? NSRunningApplication
        else { return }
        record(application, usedAt: Date(), preservesExistingDate: false)
    }

    private func record(
        _ application: NSRunningApplication,
        usedAt: Date,
        preservesExistingDate: Bool
    ) {
        guard application.activationPolicy == .regular,
              application.processIdentifier
                != ProcessInfo.processInfo.processIdentifier,
              let bundleIdentifier = application.bundleIdentifier,
              let url = application.bundleURL,
              url.isFileURL
        else { return }

        let existing = recentApplications.first(where: {
            $0.bundleIdentifier == bundleIdentifier
        })
        if preservesExistingDate, existing != nil { return }
        let date = preservesExistingDate ? .distantPast : usedAt
        let updated = RecentApplicationHistoryPlanner.recording(
            bundleIdentifier: bundleIdentifier,
            path: url.standardizedFileURL.path,
            displayName: application.localizedName
                ?? url.deletingPathExtension().lastPathComponent,
            usedAt: date,
            in: recentApplications
        )
        guard updated != recentApplications else { return }
        recentApplications = updated
        onRecentApplicationsChanged?(updated)
    }
}
