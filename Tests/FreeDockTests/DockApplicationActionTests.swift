import AppKit
import Testing
@testable import FreeDock

@Suite("Dock application actions")
struct DockApplicationActionPlannerTests {
    @Test("Empty instance state is not running")
    func emptyState() {
        let state = DockApplicationActionPlanner.state(for: [])

        #expect(!state.isRunning)
        #expect(!state.isHidden)
        #expect(!state.isFrontmost)
        #expect(state.instanceCount == 0)
        #expect(state.hiddenInstanceCount == 0)
        #expect(state.visibleInstanceCount == 0)
    }

    @Test("Aggregate state covers every matching instance")
    func aggregateState() {
        let state = DockApplicationActionPlanner.state(
            for: [
                instance(hidden: true),
                instance(hidden: true, frontmost: true),
            ]
        )

        #expect(state.isRunning)
        #expect(state.isHidden)
        #expect(state.isFrontmost)
        #expect(state.instanceCount == 2)
        #expect(state.hiddenInstanceCount == 2)
        #expect(state.visibleInstanceCount == 0)
    }

    @Test("Mixed visibility is not reported as fully hidden")
    func mixedVisibilityState() {
        let state = DockApplicationActionPlanner.state(
            for: [
                instance(hidden: true),
                instance(hidden: false),
                instance(hidden: false),
            ]
        )

        #expect(state.isRunning)
        #expect(!state.isHidden)
        #expect(state.instanceCount == 3)
        #expect(state.hiddenInstanceCount == 1)
        #expect(state.visibleInstanceCount == 2)
    }

    @Test("Activate prefers the frontmost instance")
    func activateFrontmost() {
        let requests = DockApplicationActionPlanner.requests(
            for: .activate,
            instances: [
                instance(hidden: false),
                instance(hidden: false, frontmost: true),
                instance(hidden: false),
            ]
        )

        #expect(requests == [.activate(instanceIndex: 1)])
    }

    @Test("Activate prefers a visible instance then stable input order")
    func activateVisibleFallback() {
        let visibleRequests = DockApplicationActionPlanner.requests(
            for: .activate,
            instances: [
                instance(hidden: true),
                instance(hidden: false),
                instance(hidden: false),
            ]
        )
        let hiddenRequests = DockApplicationActionPlanner.requests(
            for: .activate,
            instances: [
                instance(hidden: true),
                instance(hidden: true),
            ]
        )

        #expect(visibleRequests == [.activate(instanceIndex: 1)])
        #expect(hiddenRequests == [.activate(instanceIndex: 0)])
    }

    @Test("Show unhides every hidden instance then activates one")
    func showAllHiddenInstances() {
        let requests = DockApplicationActionPlanner.requests(
            for: .show,
            instances: [
                instance(hidden: true),
                instance(hidden: false),
                instance(hidden: true),
            ]
        )

        #expect(
            requests == [
                .show(instanceIndex: 0),
                .show(instanceIndex: 2),
                .activate(instanceIndex: 1),
            ]
        )
    }

    @Test("Hide skips instances that are already hidden")
    func hideVisibleInstances() {
        let requests = DockApplicationActionPlanner.requests(
            for: .hide,
            instances: [
                instance(hidden: true),
                instance(hidden: false),
                instance(hidden: false),
            ]
        )

        #expect(
            requests == [
                .hide(instanceIndex: 1),
                .hide(instanceIndex: 2),
            ]
        )
    }

    @Test("Quit requests normal termination for every instance")
    func quitAllInstances() {
        let requests = DockApplicationActionPlanner.requests(
            for: .quit,
            instances: [
                instance(hidden: true),
                instance(hidden: false),
                instance(hidden: false),
            ]
        )

        #expect(
            requests == [
                .quit(instanceIndex: 0),
                .quit(instanceIndex: 1),
                .quit(instanceIndex: 2),
            ]
        )
    }

    private func instance(
        hidden: Bool,
        frontmost: Bool = false
    ) -> DockApplicationInstanceState {
        DockApplicationInstanceState(
            isHidden: hidden,
            isFrontmost: frontmost
        )
    }
}

@Suite("Dock application action controller")
@MainActor
struct DockApplicationActionControllerTests {
    @Test("Resolution keeps live user-facing exact bundle matches")
    func filtersApplications() {
        let firstMatch = FakeRunningApplication(
            bundleIdentifier: "com.example.Editor"
        )
        let secondMatch = FakeRunningApplication(
            bundleIdentifier: "com.example.Editor",
            isHidden: true
        )
        let wrongBundle = FakeRunningApplication(
            bundleIdentifier: "com.example.Other"
        )
        let accessory = FakeRunningApplication(
            bundleIdentifier: "com.example.Editor",
            activationPolicy: .accessory
        )
        let prohibited = FakeRunningApplication(
            bundleIdentifier: "com.example.Editor",
            activationPolicy: .prohibited
        )
        let terminated = FakeRunningApplication(
            bundleIdentifier: "com.example.Editor",
            isTerminated: true
        )
        var requestedBundleIdentifier: String?
        let controller = DockApplicationActionController {
            requestedBundleIdentifier = $0
            return [
                firstMatch,
                wrongBundle,
                accessory,
                secondMatch,
                prohibited,
                terminated,
            ]
        }

        let state = controller.state(
            forBundleIdentifier: "com.example.Editor"
        )

        #expect(requestedBundleIdentifier == "com.example.Editor")
        #expect(state.isRunning)
        #expect(!state.isHidden)
        #expect(state.instanceCount == 3)
        #expect(state.hiddenInstanceCount == 1)
    }

    @Test("Empty bundle identifier does not query the provider")
    func emptyBundleIdentifier() {
        var providerCallCount = 0
        let controller = DockApplicationActionController { _ in
            providerCallCount += 1
            return []
        }

        let state = controller.state(forBundleIdentifier: "")
        let result = controller.perform(
            .quit,
            forBundleIdentifier: ""
        )

        #expect(providerCallCount == 0)
        #expect(!state.isRunning)
        #expect(!result.foundRunningApplication)
        #expect(!result.sentRequest)
        #expect(result.allRequestsAccepted)
    }

    @Test("Show unhides all hidden matches and activates one")
    func showAction() {
        let first = FakeRunningApplication(
            bundleIdentifier: "com.example.Editor",
            isHidden: true
        )
        let second = FakeRunningApplication(
            bundleIdentifier: "com.example.Editor",
            isHidden: false
        )
        let third = FakeRunningApplication(
            bundleIdentifier: "com.example.Editor",
            isHidden: true
        )
        let controller = controller(applications: [first, second, third])

        let result = controller.perform(
            .show,
            forBundleIdentifier: "com.example.Editor"
        )

        #expect(first.requests == [.show])
        #expect(second.requests == [.activate])
        #expect(third.requests == [.show])
        #expect(result.attemptedRequestCount == 3)
        #expect(result.acceptedRequestCount == 3)
        #expect(result.allRequestsAccepted)
    }

    @Test("Hide and quit affect all applicable matching instances")
    func hideAndQuitActions() {
        let first = FakeRunningApplication(
            bundleIdentifier: "com.example.Editor"
        )
        let second = FakeRunningApplication(
            bundleIdentifier: "com.example.Editor",
            isHidden: true
        )
        let controller = controller(applications: [first, second])

        let hideResult = controller.perform(
            .hide,
            forBundleIdentifier: "com.example.Editor"
        )
        let quitResult = controller.perform(
            .quit,
            forBundleIdentifier: "com.example.Editor"
        )

        #expect(first.requests == [.hide, .quit])
        #expect(second.requests == [.quit])
        #expect(hideResult.attemptedRequestCount == 1)
        #expect(quitResult.attemptedRequestCount == 2)
        #expect(quitResult.acceptedRequestCount == 2)
    }

    @Test("Rejected native requests are represented in the result")
    func rejectedRequest() {
        let application = FakeRunningApplication(
            bundleIdentifier: "com.example.Editor",
            acceptedRequests: []
        )
        let controller = controller(applications: [application])

        let result = controller.perform(
            .activate,
            forBundleIdentifier: "com.example.Editor"
        )

        #expect(result.foundRunningApplication)
        #expect(result.sentRequest)
        #expect(result.attemptedRequestCount == 1)
        #expect(result.acceptedRequestCount == 0)
        #expect(!result.allRequestsAccepted)
        #expect(application.requests == [.activate])
    }

    private func controller(
        applications: [FakeRunningApplication]
    ) -> DockApplicationActionController {
        DockApplicationActionController { _ in applications }
    }
}

@MainActor
private final class FakeRunningApplication:
    DockRunningApplicationInstance
{
    enum Request: Equatable, Hashable {
        case activate
        case show
        case hide
        case quit
    }

    let bundleIdentifier: String?
    let activationPolicy: NSApplication.ActivationPolicy
    let isTerminated: Bool
    let isHidden: Bool
    let isActive: Bool
    let acceptedRequests: Set<Request>
    private(set) var requests: [Request] = []

    init(
        bundleIdentifier: String?,
        activationPolicy: NSApplication.ActivationPolicy = .regular,
        isTerminated: Bool = false,
        isHidden: Bool = false,
        isActive: Bool = false,
        acceptedRequests: Set<Request> = [
            .activate,
            .show,
            .hide,
            .quit,
        ]
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.activationPolicy = activationPolicy
        self.isTerminated = isTerminated
        self.isHidden = isHidden
        self.isActive = isActive
        self.acceptedRequests = acceptedRequests
    }

    func requestDockActivation() -> Bool {
        record(.activate)
    }

    func requestDockShow() -> Bool {
        record(.show)
    }

    func requestDockHide() -> Bool {
        record(.hide)
    }

    func requestDockQuit() -> Bool {
        record(.quit)
    }

    private func record(_ request: Request) -> Bool {
        requests.append(request)
        return acceptedRequests.contains(request)
    }
}
