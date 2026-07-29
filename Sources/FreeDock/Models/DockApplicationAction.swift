import AppKit
import Foundation

/// Safe requests FreeDock can send to an already-running application.
///
/// Force Quit is intentionally absent. A normal quit request gives the
/// application an opportunity to ask about unsaved work.
enum DockApplicationAction: Equatable, Sendable {
    case activate
    case show
    case hide
    case quit
}

/// The aggregate state of every regular application instance with a bundle ID.
struct DockApplicationActionState: Equatable, Sendable {
    let isRunning: Bool
    let isHidden: Bool
    let isFrontmost: Bool
    let instanceCount: Int
    let hiddenInstanceCount: Int

    var visibleInstanceCount: Int {
        instanceCount - hiddenInstanceCount
    }

    fileprivate init(instances: [DockApplicationInstanceState]) {
        instanceCount = instances.count
        hiddenInstanceCount = instances.count(where: \.isHidden)
        isRunning = !instances.isEmpty
        isHidden = !instances.isEmpty
            && hiddenInstanceCount == instances.count
        isFrontmost = instances.contains(where: \.isFrontmost)
    }
}

/// A summary of the native requests accepted by AppKit.
///
/// AppKit accepting a request does not guarantee the target application has
/// already completed it. The running-application state updates on a later main
/// run-loop turn.
struct DockApplicationActionResult: Equatable, Sendable {
    let action: DockApplicationAction
    let stateBeforeAction: DockApplicationActionState
    let attemptedRequestCount: Int
    let acceptedRequestCount: Int

    var foundRunningApplication: Bool {
        stateBeforeAction.isRunning
    }

    var sentRequest: Bool {
        attemptedRequestCount > 0
    }

    var allRequestsAccepted: Bool {
        attemptedRequestCount == acceptedRequestCount
    }
}

struct DockApplicationInstanceState: Equatable, Sendable {
    let isHidden: Bool
    let isFrontmost: Bool
}

enum DockApplicationActionRequest: Equatable, Sendable {
    case activate(instanceIndex: Int)
    case show(instanceIndex: Int)
    case hide(instanceIndex: Int)
    case quit(instanceIndex: Int)
}

/// Pure aggregate-state and request planning for application actions.
enum DockApplicationActionPlanner {
    static func state(
        for instances: [DockApplicationInstanceState]
    ) -> DockApplicationActionState {
        DockApplicationActionState(instances: instances)
    }

    static func requests(
        for action: DockApplicationAction,
        instances: [DockApplicationInstanceState]
    ) -> [DockApplicationActionRequest] {
        guard !instances.isEmpty else { return [] }

        switch action {
        case .activate:
            return [
                .activate(
                    instanceIndex: preferredActivationIndex(in: instances)
                ),
            ]

        case .show:
            var requests: [DockApplicationActionRequest] =
                instances.indices.compactMap { index in
                    instances[index].isHidden
                        ? .show(instanceIndex: index)
                        : nil
                }
            requests.append(
                .activate(
                    instanceIndex: preferredActivationIndex(in: instances)
                )
            )
            return requests

        case .hide:
            return instances.indices.compactMap { index in
                instances[index].isHidden
                    ? nil
                    : .hide(instanceIndex: index)
            }

        case .quit:
            return instances.indices.map {
                .quit(instanceIndex: $0)
            }
        }
    }

    private static func preferredActivationIndex(
        in instances: [DockApplicationInstanceState]
    ) -> Int {
        instances.firstIndex(where: \.isFrontmost)
            ?? instances.firstIndex(where: { !$0.isHidden })
            ?? instances.startIndex
    }
}

/// The small native surface used by `DockApplicationActionController`.
///
/// Keeping this protocol separate from `NSRunningApplication` makes the
/// controller safe to test without manipulating applications on the system.
@MainActor
protocol DockRunningApplicationInstance: AnyObject {
    var bundleIdentifier: String? { get }
    var activationPolicy: NSApplication.ActivationPolicy { get }
    var isTerminated: Bool { get }
    var isHidden: Bool { get }
    var isActive: Bool { get }

    @discardableResult
    func requestDockActivation() -> Bool

    @discardableResult
    func requestDockShow() -> Bool

    @discardableResult
    func requestDockHide() -> Bool

    @discardableResult
    func requestDockQuit() -> Bool
}

extension NSRunningApplication: DockRunningApplicationInstance {
    func requestDockActivation() -> Bool {
        if #available(macOS 14.0, *) {
            activate(options: [.activateAllWindows])
        } else {
            activate(
                options: [
                    .activateAllWindows,
                    .activateIgnoringOtherApps,
                ]
            )
        }
    }

    func requestDockShow() -> Bool {
        unhide()
    }

    func requestDockHide() -> Bool {
        hide()
    }

    func requestDockQuit() -> Bool {
        terminate()
    }
}

/// Resolves and controls every regular running instance of an application.
@MainActor
final class DockApplicationActionController {
    typealias RunningApplicationProvider = @MainActor (
        _ bundleIdentifier: String
    ) -> [any DockRunningApplicationInstance]

    private let runningApplications: RunningApplicationProvider

    convenience init() {
        self.init { bundleIdentifier in
            NSRunningApplication.runningApplications(
                withBundleIdentifier: bundleIdentifier
            )
            .map { $0 as any DockRunningApplicationInstance }
        }
    }

    init(
        runningApplications: @escaping RunningApplicationProvider
    ) {
        self.runningApplications = runningApplications
    }

    func state(
        forBundleIdentifier bundleIdentifier: String
    ) -> DockApplicationActionState {
        let targets = matchingApplications(
            bundleIdentifier: bundleIdentifier
        )
        return DockApplicationActionPlanner.state(
            for: targets.map(Self.snapshot)
        )
    }

    @discardableResult
    func perform(
        _ action: DockApplicationAction,
        forBundleIdentifier bundleIdentifier: String
    ) -> DockApplicationActionResult {
        let targets = matchingApplications(
            bundleIdentifier: bundleIdentifier
        )
        let instanceStates = targets.map(Self.snapshot)
        let state = DockApplicationActionPlanner.state(
            for: instanceStates
        )
        let requests = DockApplicationActionPlanner.requests(
            for: action,
            instances: instanceStates
        )
        let acceptedCount = requests.count { request in
            execute(request, on: targets)
        }

        return DockApplicationActionResult(
            action: action,
            stateBeforeAction: state,
            attemptedRequestCount: requests.count,
            acceptedRequestCount: acceptedCount
        )
    }

    private func matchingApplications(
        bundleIdentifier: String
    ) -> [any DockRunningApplicationInstance] {
        guard !bundleIdentifier.isEmpty else { return [] }

        return runningApplications(bundleIdentifier).filter {
            $0.bundleIdentifier == bundleIdentifier
                && $0.activationPolicy != .prohibited
                && !$0.isTerminated
        }
    }

    private static func snapshot(
        _ application: any DockRunningApplicationInstance
    ) -> DockApplicationInstanceState {
        DockApplicationInstanceState(
            isHidden: application.isHidden,
            isFrontmost: application.isActive
        )
    }

    private func execute(
        _ request: DockApplicationActionRequest,
        on applications: [any DockRunningApplicationInstance]
    ) -> Bool {
        switch request {
        case let .activate(index):
            return applications[index].requestDockActivation()
        case let .show(index):
            return applications[index].requestDockShow()
        case let .hide(index):
            return applications[index].requestDockHide()
        case let .quit(index):
            return applications[index].requestDockQuit()
        }
    }
}
