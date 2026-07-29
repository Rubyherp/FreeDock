import AppKit
import ApplicationServices
import Foundation

@MainActor
final class DockApplicationWindowController {
    private struct ApplicationIdentity: Hashable {
        let processIdentifier: pid_t
        let launchDate: Date?
    }

    private struct ApplicationRecord {
        let id: UUID
        let identity: ApplicationIdentity
        let bundleIdentifier: String
        let application: NSRunningApplication
    }

    private struct CaptureIdentity: Hashable {
        let processIdentifier: pid_t
        let windowID: CGWindowID
    }

    private let nativeStore = DockApplicationWindowNativeStore()
    private let captureController = DockWindowCaptureController()
    private var applications: [UUID: ApplicationRecord] = [:]
    private var windowApplicationIDs: [DockApplicationWindow.ID: UUID] =
        [:]
    private var captureWindowUUIDs: [CaptureIdentity: UUID] = [:]
    private var captureWindowsByItemID:
        [DockApplicationWindow.ID: DockWindowServerWindow] = [:]
    private var captureOnlyWindowIDs =
        Set<DockApplicationWindow.ID>()
    private var queryGeneration = UUID()

    var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    var isScreenCaptureTrusted: Bool {
        captureController.isScreenCaptureTrusted
    }

    /// Requests permission only from an explicit user action.
    ///
    /// A false return commonly means System Settings has opened and the user
    /// has not granted access yet; hover paths must call only the status check.
    @discardableResult
    func requestAccessibilityAccess() -> Bool {
        let options = [
            "AXTrustedCheckOptionPrompt": true,
        ] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    @discardableResult
    func requestScreenCaptureAccess() -> Bool {
        captureController.requestScreenCaptureAccess()
    }

    func loadWindows(
        bundleIdentifier: String,
        applicationName: String
    ) async -> DockApplicationWindowQuery {
        guard isAccessibilityTrusted else {
            clearRetainedState()
            await nativeStore.reset()
            return DockApplicationWindowQuery(
                status: .permissionRequired,
                windows: []
            )
        }
        guard !bundleIdentifier.isEmpty else {
            clearRetainedState()
            await nativeStore.reset()
            return DockApplicationWindowQuery(
                status: .applicationNotRunning,
                windows: []
            )
        }

        let runningApplications = NSRunningApplication
            .runningApplications(
                withBundleIdentifier: bundleIdentifier
            )
            .filter {
                $0.bundleIdentifier == bundleIdentifier
                    && $0.activationPolicy != .prohibited
                    && !$0.isTerminated
            }
        guard !runningApplications.isEmpty else {
            clearRetainedState()
            await nativeStore.reset()
            return DockApplicationWindowQuery(
                status: .applicationNotRunning,
                windows: []
            )
        }

        let previousByIdentity = Dictionary(
            uniqueKeysWithValues: applications.values.map {
                ($0.identity, $0.id)
            }
        )
        var currentApplications: [UUID: ApplicationRecord] = [:]
        let descriptors = runningApplications.map { application in
            let identity = ApplicationIdentity(
                processIdentifier: application.processIdentifier,
                launchDate: application.launchDate
            )
            let instanceID = previousByIdentity[identity] ?? UUID()
            currentApplications[instanceID] = ApplicationRecord(
                id: instanceID,
                identity: identity,
                bundleIdentifier: bundleIdentifier,
                application: application
            )
            return DockApplicationInstanceDescriptor(
                id: instanceID,
                processIdentifier: application.processIdentifier,
                applicationName:
                    application.localizedName ?? applicationName,
                isHidden: application.isHidden,
                isActive: application.isActive
            )
        }
        applications = currentApplications
        let captureWindows = captureController.windows(
            for: Set(
                runningApplications.map(\.processIdentifier)
            )
        )

        let generation = UUID()
        queryGeneration = generation
        let nativeResult = await nativeStore.query(
            applications: descriptors
        )
        guard queryGeneration == generation else {
            return DockApplicationWindowQuery(
                status: .temporarilyUnavailable,
                windows: []
            )
        }

        var windows = DockApplicationWindowPlanner.windows(
            from: nativeResult.candidates,
            captureWindows: captureWindows
        )
        appendCaptureOnlyWindows(
            to: &windows,
            captureWindows: captureWindows,
            candidates: nativeResult.candidates,
            applicationDescriptors: descriptors
        )
        updateCaptureState(
            windows: windows,
            captureWindows: captureWindows
        )
        windowApplicationIDs = Dictionary(
            uniqueKeysWithValues: windows.map {
                ($0.id, $0.applicationInstanceID)
            }
        )
        return DockApplicationWindowQuery(
            status: nativeResult.status,
            windows: windows
        )
    }

    func thumbnail(
        for window: DockApplicationWindow,
        maximumPixelSize: CGSize
    ) async -> NSImage? {
        guard let capture =
                captureWindowsByItemID[window.id],
              capture.windowID == window.captureWindowID
        else {
            return nil
        }
        return await captureController.thumbnail(
            processIdentifier: capture.processIdentifier,
            for: capture.windowID,
            frame: capture.frame,
            maximumPixelSize: maximumPixelSize
        )
    }

    func focusWindow(
        id windowID: DockApplicationWindow.ID
    ) async -> DockApplicationWindowFocusResult {
        guard isAccessibilityTrusted else {
            return .permissionRequired
        }
        guard let instanceID = windowApplicationIDs[windowID],
              let record = applications[instanceID]
        else {
            return .staleWindow
        }
        guard isCurrent(record) else {
            await discard(instanceID: instanceID)
            return .applicationNotRunning
        }

        if captureOnlyWindowIDs.contains(windowID) {
            if record.application.isHidden {
                _ = record.application.unhide()
            }
            let didActivate: Bool
            if #available(macOS 14.0, *) {
                didActivate = record.application.activate(options: [])
            } else {
                didActivate = record.application.activate(
                    options: [.activateIgnoringOtherApps]
                )
            }
            guard didActivate else {
                return .activationRejected
            }

            if let capture = captureWindowsByItemID[windowID] {
                let descriptor = DockApplicationInstanceDescriptor(
                    id: instanceID,
                    processIdentifier:
                        record.identity.processIdentifier,
                    applicationName:
                        record.application.localizedName
                            ?? "Application",
                    isHidden: record.application.isHidden,
                    isActive: record.application.isActive
                )
                let exactFocus =
                    await nativeStore.focusCaptureWindow(
                        application: descriptor,
                        captureWindow: capture
                    )
                if exactFocus == .accepted {
                    return .accepted
                }
            }
            return .accepted
        }

        if record.application.isHidden,
           !record.application.unhide()
        {
            return .activationRejected
        }

        let preparation = await nativeStore.prepareFocus(
            windowID: windowID,
            applicationInstanceID: instanceID
        )
        guard preparation == .accepted else {
            return preparation.focusResult
        }
        guard isCurrent(record) else {
            await discard(instanceID: instanceID)
            return .applicationNotRunning
        }

        let didActivate: Bool
        if #available(macOS 14.0, *) {
            didActivate = record.application.activate(options: [])
        } else {
            didActivate = record.application.activate(
                options: [.activateIgnoringOtherApps]
            )
        }
        guard didActivate else {
            return .activationRejected
        }

        let raiseResult = await nativeStore.raise(
            windowID: windowID,
            applicationInstanceID: instanceID
        )
        return raiseResult.focusResult
    }

    func reset() {
        clearRetainedState()
        captureController.reset()
    }

    func clearThumbnailCache() {
        captureController.clearThumbnailCache()
    }

    private func isCurrent(
        _ record: ApplicationRecord
    ) -> Bool {
        let application = record.application
        return !application.isTerminated
            && application.processIdentifier
                == record.identity.processIdentifier
            && application.launchDate == record.identity.launchDate
            && application.bundleIdentifier == record.bundleIdentifier
    }

    private func discard(instanceID: UUID) async {
        applications.removeValue(forKey: instanceID)
        windowApplicationIDs = windowApplicationIDs.filter {
            $0.value != instanceID
        }
        await nativeStore.discard(
            applicationInstanceID: instanceID
        )
    }

    private func clearRetainedState() {
        queryGeneration = UUID()
        applications.removeAll()
        windowApplicationIDs.removeAll()
        captureWindowUUIDs.removeAll()
        captureWindowsByItemID.removeAll()
        captureOnlyWindowIDs.removeAll()
    }

    private func appendCaptureOnlyWindows(
        to windows: inout [DockApplicationWindow],
        captureWindows: [DockWindowServerWindow],
        candidates: [DockApplicationWindowCandidate],
        applicationDescriptors:
            [DockApplicationInstanceDescriptor]
    ) {
        let descriptorsByPID = Dictionary(
            uniqueKeysWithValues: applicationDescriptors.map {
                ($0.processIdentifier, $0)
            }
        )
        let currentUUIDs = Dictionary(
            uniqueKeysWithValues: captureWindows.map { capture in
                let identity = CaptureIdentity(
                    processIdentifier:
                        capture.processIdentifier,
                    windowID: capture.windowID
                )
                return (
                    identity,
                    captureWindowUUIDs[identity] ?? UUID()
                )
            }
        )
        let captureOnlyWindows =
            DockApplicationWindowPlanner
                .unrepresentedCaptureWindows(
                    candidates: candidates,
                    captureWindows: captureWindows
                )
        for capture in captureOnlyWindows {
            guard let application =
                    descriptorsByPID[capture.processIdentifier]
            else {
                continue
            }
            let identity = CaptureIdentity(
                processIdentifier: capture.processIdentifier,
                windowID: capture.windowID
            )
            guard let id = currentUUIDs[identity] else {
                continue
            }

            windows.append(
                DockApplicationWindow(
                    id: id,
                    applicationInstanceID: application.id,
                    applicationName: application.applicationName,
                    title: capture.title?.trimmedNonEmpty
                        ?? "Untitled \(application.applicationName) Window",
                    captureWindowID: capture.windowID,
                    isMinimized: false,
                    isApplicationHidden: application.isHidden,
                    isOnScreen: capture.isOnScreen,
                    canFocusExactly: false,
                    isMain: false,
                    isFocused: false
                )
            )
        }
        captureWindowUUIDs = currentUUIDs
    }

    private func updateCaptureState(
        windows: [DockApplicationWindow],
        captureWindows: [DockWindowServerWindow]
    ) {
        let captureByID = Dictionary(
            uniqueKeysWithValues: captureWindows.map {
                ($0.windowID, $0)
            }
        )
        captureWindowsByItemID = Dictionary(
            uniqueKeysWithValues: windows.compactMap { window in
                guard let captureID = window.captureWindowID,
                      let capture = captureByID[captureID]
                else {
                    return nil
                }
                return (window.id, capture)
            }
        )
        captureOnlyWindowIDs = Set(
            windows.filter { !$0.canFocusExactly }.map(\.id)
        )
    }
}

private struct DockApplicationInstanceDescriptor: Sendable {
    let id: UUID
    let processIdentifier: pid_t
    let applicationName: String
    let isHidden: Bool
    let isActive: Bool
}

private struct DockNativeWindowQueryResult: Sendable {
    let status: DockApplicationWindowQueryStatus
    let candidates: [DockApplicationWindowCandidate]
}

private enum DockNativeWindowOperationResult: Equatable, Sendable {
    case accepted
    case permissionRequired
    case staleWindow
    case temporarilyUnavailable
    case unsupported

    var focusResult: DockApplicationWindowFocusResult {
        switch self {
        case .accepted: return .accepted
        case .permissionRequired: return .permissionRequired
        case .staleWindow: return .staleWindow
        case .temporarilyUnavailable: return .temporarilyUnavailable
        case .unsupported: return .unsupported
        }
    }
}

private actor DockApplicationWindowNativeStore {
    private struct NativeWindowRecord {
        let id: UUID
        let applicationInstanceID: UUID
        let applicationElement: AXUIElement
        let windowElement: AXUIElement
        let isMinimized: Bool
        let candidate: DockApplicationWindowCandidate
    }

    private var records: [UUID: NativeWindowRecord] = [:]

    func query(
        applications: [DockApplicationInstanceDescriptor],
        replacingOtherApplications: Bool = true
    ) -> DockNativeWindowQueryResult {
        guard AXIsProcessTrusted() else {
            records.removeAll()
            return DockNativeWindowQueryResult(
                status: .permissionRequired,
                candidates: []
            )
        }

        let currentInstanceIDs = Set(applications.map(\.id))
        if replacingOtherApplications {
            records = records.filter {
                currentInstanceIDs.contains(
                    $0.value.applicationInstanceID
                )
            }
        }

        var candidates: [DockApplicationWindowCandidate] = []
        var refreshedRecords: [UUID: NativeWindowRecord] =
            replacingOtherApplications
                ? [:]
                : records.filter {
                    !currentInstanceIDs.contains(
                        $0.value.applicationInstanceID
                    )
                }
        var successfulQueryCount = 0
        var temporaryFailureCount = 0
        var retainedCandidateCount = 0
        var globalSourceOrder = 0

        for application in applications {
            let applicationElement = AXUIElementCreateApplication(
                application.processIdentifier
            )
            AXUIElementSetMessagingTimeout(
                applicationElement,
                0.25
            )

            var rawWindows: CFTypeRef?
            let queryError = AXUIElementCopyAttributeValue(
                applicationElement,
                kAXWindowsAttribute as CFString,
                &rawWindows
            )
            switch queryError {
            case .success:
                successfulQueryCount += 1
            case .apiDisabled:
                records.removeAll()
                return DockNativeWindowQueryResult(
                    status: .permissionRequired,
                    candidates: []
                )
            case .cannotComplete:
                temporaryFailureCount += 1
                let previousRecords = records.values.filter {
                    $0.applicationInstanceID == application.id
                }
                let previousByID = Dictionary(
                    uniqueKeysWithValues: previousRecords.map {
                        ($0.id, $0)
                    }
                )
                let retainedCandidates =
                    DockApplicationWindowPlanner.retainedCandidates(
                        from: previousRecords.map(\.candidate),
                        applicationInstanceID: application.id,
                        applicationName: application.applicationName,
                        isApplicationHidden: application.isHidden,
                        isApplicationActive: application.isActive,
                        startingSourceOrder: globalSourceOrder
                    )
                for candidate in retainedCandidates {
                    guard let record = previousByID[candidate.id] else {
                        continue
                    }
                    refreshedRecords[record.id] = NativeWindowRecord(
                        id: record.id,
                        applicationInstanceID:
                            record.applicationInstanceID,
                        applicationElement:
                            record.applicationElement,
                        windowElement: record.windowElement,
                        isMinimized: record.isMinimized,
                        candidate: candidate
                    )
                    candidates.append(candidate)
                }
                retainedCandidateCount += retainedCandidates.count
                globalSourceOrder += max(
                    1,
                    retainedCandidates.count
                )
                continue
            default:
                continue
            }

            var windows = rawWindows as? [AXUIElement] ?? []
            if windows.isEmpty {
                let children: [AXUIElement] = copyAttribute(
                    applicationElement,
                    kAXChildrenAttribute as CFString
                ) ?? []
                windows = children.filter {
                    copyString(
                        $0,
                        kAXRoleAttribute as CFString
                    ) == (kAXWindowRole as String)
                }
            }
            let focusedWindow: AXUIElement? = copyAttribute(
                applicationElement,
                kAXFocusedWindowAttribute as CFString
            )
            let previous = records.values.filter {
                $0.applicationInstanceID == application.id
            }
            var usedPreviousIDs = Set<UUID>()

            for (sourceOrder, windowElement) in windows.enumerated() {
                AXUIElementSetMessagingTimeout(
                    windowElement,
                    0.25
                )
                guard copyString(
                    windowElement,
                    kAXRoleAttribute as CFString
                ) == (kAXWindowRole as String)
                else {
                    continue
                }

                let id: UUID
                if let match = previous.first(where: {
                    !usedPreviousIDs.contains($0.id)
                        && CFEqual(
                            $0.windowElement,
                            windowElement
                        )
                }) {
                    id = match.id
                    usedPreviousIDs.insert(match.id)
                } else {
                    id = UUID()
                }

                let isMinimized = copyBool(
                    windowElement,
                    kAXMinimizedAttribute as CFString
                ) ?? false
                let isMain = copyBool(
                    windowElement,
                    kAXMainAttribute as CFString
                ) ?? false
                let frame: CGRect?
                if let position = copyPoint(
                    windowElement,
                    kAXPositionAttribute as CFString
                ),
                   let size = copySize(
                    windowElement,
                    kAXSizeAttribute as CFString
                   )
                {
                    frame = CGRect(
                        origin: position,
                        size: size
                    )
                } else {
                    frame = nil
                }
                let candidate = DockApplicationWindowCandidate(
                    id: id,
                    applicationInstanceID: application.id,
                    processIdentifier:
                        application.processIdentifier,
                    applicationName:
                        application.applicationName,
                    title: copyString(
                        windowElement,
                        kAXTitleAttribute as CFString
                    ),
                    documentPath: copyString(
                        windowElement,
                        kAXDocumentAttribute as CFString
                    ),
                    frame: frame,
                    role: role(
                        for: copyString(
                            windowElement,
                            kAXSubroleAttribute as CFString
                        )
                    ),
                    isMinimized: isMinimized,
                    isApplicationHidden:
                        application.isHidden,
                    isApplicationActive:
                        application.isActive,
                    isMain: isMain,
                    isFocused: focusedWindow.map {
                        CFEqual($0, windowElement)
                    } ?? false,
                    sourceOrder:
                        globalSourceOrder + sourceOrder
                )
                let record = NativeWindowRecord(
                    id: id,
                    applicationInstanceID: application.id,
                    applicationElement: applicationElement,
                    windowElement: windowElement,
                    isMinimized: isMinimized,
                    candidate: candidate
                )
                refreshedRecords[id] = record
                candidates.append(candidate)
            }
            globalSourceOrder += max(1, windows.count)
        }

        records = refreshedRecords
        let status =
            DockApplicationWindowPlanner.nativeQueryStatus(
                successfulQueryCount: successfulQueryCount,
                temporaryFailureCount: temporaryFailureCount,
                retainedCandidateCount: retainedCandidateCount
            )
        return DockNativeWindowQueryResult(
            status: status,
            candidates: candidates
        )
    }

    func focusCaptureWindow(
        application: DockApplicationInstanceDescriptor,
        captureWindow: DockWindowServerWindow
    ) -> DockNativeWindowOperationResult {
        let refreshed = query(
            applications: [application],
            replacingOtherApplications: false
        )
        guard refreshed.status == .ready else {
            return refreshed.status == .permissionRequired
                ? .permissionRequired
                : .temporarilyUnavailable
        }
        let match = DockApplicationWindowPlanner
            .captureMatches(
                candidates: DockApplicationWindowPlanner
                    .selectedCandidates(
                        from: refreshed.candidates
                    ),
                captureWindows: [captureWindow]
            )
            .first
        guard let windowID = match?.accessibilityWindowID else {
            return .unsupported
        }
        let preparation = prepareFocus(
            windowID: windowID,
            applicationInstanceID: application.id
        )
        guard preparation == .accepted else {
            return preparation
        }
        return raise(
            windowID: windowID,
            applicationInstanceID: application.id
        )
    }

    func prepareFocus(
        windowID: UUID,
        applicationInstanceID: UUID
    ) -> DockNativeWindowOperationResult {
        guard AXIsProcessTrusted() else {
            return .permissionRequired
        }
        guard let record = records[windowID],
              record.applicationInstanceID
                == applicationInstanceID
        else {
            return .staleWindow
        }

        let isMinimized = copyBool(
            record.windowElement,
            kAXMinimizedAttribute as CFString
        ) ?? record.isMinimized
        if isMinimized {
            let result = AXUIElementSetAttributeValue(
                record.windowElement,
                kAXMinimizedAttribute as CFString,
                kCFBooleanFalse
            )
            guard isAccepted(result, allowingUnsupported: false)
            else {
                return operationResult(for: result)
            }
        }

        let makeMainResult = AXUIElementSetAttributeValue(
            record.windowElement,
            kAXMainAttribute as CFString,
            kCFBooleanTrue
        )
        guard isAccepted(
            makeMainResult,
            allowingUnsupported: true
        ) else {
            return operationResult(for: makeMainResult)
        }

        let focusResult = AXUIElementSetAttributeValue(
            record.applicationElement,
            kAXFocusedWindowAttribute as CFString,
            record.windowElement
        )
        guard isAccepted(
            focusResult,
            allowingUnsupported: true
        ) else {
            return operationResult(for: focusResult)
        }
        return .accepted
    }

    func raise(
        windowID: UUID,
        applicationInstanceID: UUID
    ) -> DockNativeWindowOperationResult {
        guard AXIsProcessTrusted() else {
            return .permissionRequired
        }
        guard let record = records[windowID],
              record.applicationInstanceID
                == applicationInstanceID
        else {
            return .staleWindow
        }
        let result = AXUIElementPerformAction(
            record.windowElement,
            kAXRaiseAction as CFString
        )
        return result == .success
            ? .accepted
            : operationResult(for: result)
    }

    func discard(applicationInstanceID: UUID) {
        records = records.filter {
            $0.value.applicationInstanceID
                != applicationInstanceID
        }
    }

    func reset() {
        records.removeAll()
    }

    private func role(
        for subrole: String?
    ) -> DockApplicationWindowRole {
        switch subrole {
        case kAXStandardWindowSubrole:
            return .standard
        case kAXDialogSubrole:
            return .dialog
        case kAXSystemDialogSubrole:
            return .systemDialog
        default:
            return .other
        }
    }

    private func copyAttribute<Value>(
        _ element: AXUIElement,
        _ attribute: CFString
    ) -> Value? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            attribute,
            &value
        ) == .success else {
            return nil
        }
        return value as? Value
    }

    private func copyString(
        _ element: AXUIElement,
        _ attribute: CFString
    ) -> String? {
        copyAttribute(element, attribute)
    }

    private func copyBool(
        _ element: AXUIElement,
        _ attribute: CFString
    ) -> Bool? {
        if let value: Bool = copyAttribute(
            element,
            attribute
        ) {
            return value
        }
        if let number: NSNumber = copyAttribute(
            element,
            attribute
        ) {
            return number.boolValue
        }
        return nil
    }

    private func copyPoint(
        _ element: AXUIElement,
        _ attribute: CFString
    ) -> CGPoint? {
        guard let value: AXValue = copyAttribute(
            element,
            attribute
        ) else {
            return nil
        }
        var point = CGPoint.zero
        guard AXValueGetValue(value, .cgPoint, &point) else {
            return nil
        }
        return point
    }

    private func copySize(
        _ element: AXUIElement,
        _ attribute: CFString
    ) -> CGSize? {
        guard let value: AXValue = copyAttribute(
            element,
            attribute
        ) else {
            return nil
        }
        var size = CGSize.zero
        guard AXValueGetValue(value, .cgSize, &size) else {
            return nil
        }
        return size
    }

    private func isAccepted(
        _ error: AXError,
        allowingUnsupported: Bool
    ) -> Bool {
        error == .success
            || (
                allowingUnsupported
                    && (
                        error == .attributeUnsupported
                            || error == .notImplemented
                    )
            )
    }

    private func operationResult(
        for error: AXError
    ) -> DockNativeWindowOperationResult {
        switch error {
        case .success:
            return .accepted
        case .apiDisabled:
            return .permissionRequired
        case .invalidUIElement:
            return .staleWindow
        case .actionUnsupported, .attributeUnsupported,
             .notImplemented:
            return .unsupported
        case .cannotComplete:
            return .temporarilyUnavailable
        default:
            return .temporarilyUnavailable
        }
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let value = trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return value.isEmpty ? nil : value
    }
}
