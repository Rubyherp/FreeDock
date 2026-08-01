import SwiftUI

enum DockPreferenceChange: Equatable {
    case orientation(Orientation)
    case iconSize(Double)
    case magnificationEnabled(Bool)
    case magnification(Double)
    case itemSpacing(Double)
    case appearance(DockAppearance)
    case surfaceOpacity(Double)
    case blurStyle(DockBlurStyle)
    case cornerRadius(Double)
    case shadowStrength(Double)
    case showRunningIndicators(Bool)
    case showDynamicApplications(Bool)
    case dynamicApplicationLimit(Int)
    case autoHideWhenDocked(Bool)
    case autoHideDelay(Double)
}

enum DockManagementAction: Equatable {
    case exportConfiguration
    case importConfiguration
    case activateProfile(UUID)
    case addProfileApplicationAutomation(UUID)
    case addProfileDisplayAutomation(profileID: UUID, displayID: UUID)
    case setProfileAutomationEnabled(profileID: UUID, ruleID: UUID, enabled: Bool)
    case deleteProfileAutomation(profileID: UUID, ruleID: UUID)
    case createProfile
    case renameActiveProfile
    case deleteActiveProfile
    case createDock(Orientation)
    case renameDock(UUID)
    case duplicateDock(UUID)
    case deleteDock(UUID)
    case setDockDisplay(UUID, UUID?)
    case addDockItems(UUID)
    case addSmartStack(UUID, SmartStackSource)
    case addTrash(UUID)
    case clearRecentFiles
    case importSystemDockApps(UUID)
    case resetDockSettings(UUID)
    case copyDockSettingsToAll(UUID)
    case saveDockTheme(UUID)
    case applyDockTheme(themeID: UUID, dockID: UUID)
    case deleteDockTheme(UUID)
}

extension DockConfig {
    mutating func apply(_ change: DockPreferenceChange) {
        switch change {
        case let .orientation(value):
            orientation = value
        case let .iconSize(value):
            iconSize = Self.clamp(value, to: Self.iconSizeRange)
        case let .magnificationEnabled(value):
            magnificationEnabled = value
        case let .magnification(value):
            magnification = Self.clamp(value, to: Self.magnificationRange)
        case let .itemSpacing(value):
            itemSpacing = Self.clamp(value, to: Self.itemSpacingRange)
        case let .appearance(value):
            appearance = value
        case let .surfaceOpacity(value):
            surfaceOpacity = Self.clamp(value, to: Self.surfaceOpacityRange)
        case let .blurStyle(value):
            blurStyle = value
        case let .cornerRadius(value):
            cornerRadius = Self.clamp(value, to: Self.cornerRadiusRange)
        case let .shadowStrength(value):
            shadowStrength = Self.clamp(value, to: Self.shadowStrengthRange)
        case let .showRunningIndicators(value):
            showRunningIndicators = value
        case let .showDynamicApplications(value):
            showDynamicApplications = value
        case let .dynamicApplicationLimit(value):
            dynamicApplicationLimit = min(max(value, 1), 10)
        case let .autoHideWhenDocked(value):
            autoHideWhenDocked = value
        case let .autoHideDelay(value):
            autoHideDelay = Self.clamp(value, to: Self.autoHideDelayRange)
        }
        normalizeDisplayPlacementEdge()
    }
}

@MainActor
final class DockPreferencesStore: ObservableObject {
    @Published private(set) var profiles: [DockProfile]
    @Published private(set) var activeProfileID: UUID
    @Published private(set) var docks: [DockConfig]
    @Published private(set) var displays: [DockDisplayDescriptor]
    @Published private(set) var permissionState: PreferencesPermissionState
    @Published private(set) var launchAtLoginState: LaunchAtLoginState
    @Published private(set) var globalShortcuts: GlobalShortcutSettings
    @Published private(set) var themes: [DockTheme]
    @Published private(set) var shortcutError: String?
    @Published var selectedDockID: UUID?

    private let onChange: (UUID, DockPreferenceChange) -> Void
    private let onManagementAction: (DockManagementAction) -> Void
    private let permissionSnapshot: () -> PreferencesPermissionSnapshot
    private let onPermissionAction: (PreferencesPermissionKind) -> Void
    private let onOpenPermissionSettings: (PreferencesPermissionKind) -> Void
    private let launchAtLoginSnapshot: () -> LaunchAtLoginState
    private let onLaunchAtLoginChange: (Bool) -> LaunchAtLoginState
    private let onOpenLoginItemsSettings: () -> Void
    private let onGlobalShortcutsChange: (GlobalShortcutSettings) -> String?

    init(
        profiles: [DockProfile],
        activeProfileID: UUID,
        displays: [DockDisplayDescriptor] = [],
        permissionState: PreferencesPermissionState = PreferencesPermissionState(),
        launchAtLoginState: LaunchAtLoginState = LaunchAtLoginState(),
        globalShortcuts: GlobalShortcutSettings = GlobalShortcutSettings(),
        themes: [DockTheme] = [],
        onChange: @escaping (UUID, DockPreferenceChange) -> Void,
        onManagementAction: @escaping (DockManagementAction) -> Void,
        permissionSnapshot: @escaping () -> PreferencesPermissionSnapshot = {
            .checking
        },
        onPermissionAction: @escaping (PreferencesPermissionKind) -> Void = {
            _ in
        },
        onOpenPermissionSettings: @escaping (PreferencesPermissionKind) -> Void = {
            _ in
        },
        launchAtLoginSnapshot: @escaping () -> LaunchAtLoginState = {
            LaunchAtLoginState()
        },
        onLaunchAtLoginChange: @escaping (Bool) -> LaunchAtLoginState = {
            enabled in LaunchAtLoginState(status: enabled ? .enabled : .disabled)
        },
        onOpenLoginItemsSettings: @escaping () -> Void = {
        },
        onGlobalShortcutsChange: @escaping (
            GlobalShortcutSettings
        ) -> String? = { _ in
            nil
        }
    ) {
        self.profiles = profiles
        self.activeProfileID = activeProfileID
        let activeDocks = profiles.first(where: { $0.id == activeProfileID })?.docks ?? []
        docks = activeDocks
        self.displays = displays
        self.permissionState = permissionState
        self.launchAtLoginState = launchAtLoginState
        self.globalShortcuts = globalShortcuts
        self.themes = themes
        shortcutError = nil
        selectedDockID = activeDocks.first?.id
        self.onChange = onChange
        self.onManagementAction = onManagementAction
        self.permissionSnapshot = permissionSnapshot
        self.onPermissionAction = onPermissionAction
        self.onOpenPermissionSettings = onOpenPermissionSettings
        self.launchAtLoginSnapshot = launchAtLoginSnapshot
        self.onLaunchAtLoginChange = onLaunchAtLoginChange
        self.onOpenLoginItemsSettings = onOpenLoginItemsSettings
        self.onGlobalShortcutsChange = onGlobalShortcutsChange
    }

    var activeProfileName: String {
        profiles.first(where: { $0.id == activeProfileID })?.name ?? "Default"
    }

    var activeProfileAutomationRules: [ProfileAutomationRule] {
        profiles.first(where: { $0.id == activeProfileID })?
            .automationRules ?? []
    }

    var canDeleteActiveProfile: Bool {
        profiles.count > 1
    }

    var selectedDock: DockConfig? {
        guard let selectedDockID else { return nil }
        return docks.first(where: { $0.id == selectedDockID })
    }

    var canCopySelectedDockSettings: Bool {
        selectedDockID != nil && docks.count > 1
    }

    func reload(
        profiles: [DockProfile],
        activeProfileID: UUID,
        displays: [DockDisplayDescriptor]? = nil,
        globalShortcuts: GlobalShortcutSettings? = nil,
        themes: [DockTheme]? = nil
    ) {
        let profileChanged = activeProfileID != self.activeProfileID
        self.profiles = profiles
        self.activeProfileID = activeProfileID
        if let displays {
            self.displays = displays
        }
        if let globalShortcuts {
            self.globalShortcuts = globalShortcuts
        }
        if let themes {
            self.themes = themes
        }
        let activeDocks = profiles.first(where: { $0.id == activeProfileID })?.docks ?? []
        docks = activeDocks

        if profileChanged || !activeDocks.contains(where: { $0.id == selectedDockID }) {
            selectedDockID = activeDocks.first?.id
        }
    }

    func replaceDock(_ dock: DockConfig) {
        guard let index = docks.firstIndex(where: { $0.id == dock.id }) else { return }
        docks[index] = dock
    }

    func updateSelected(_ change: DockPreferenceChange) {
        guard let selectedDockID,
              let index = docks.firstIndex(where: { $0.id == selectedDockID })
        else { return }

        docks[index].apply(change)
        onChange(selectedDockID, change)
    }

    func perform(_ action: DockManagementAction) {
        onManagementAction(action)
    }

    func refreshPermissions() {
        var updatedState = permissionState
        guard updatedState.refresh(with: permissionSnapshot()) != .unchanged else {
            return
        }
        permissionState = updatedState
    }

    func refreshLaunchAtLogin() {
        let snapshot = launchAtLoginSnapshot()
        guard snapshot != launchAtLoginState else { return }
        launchAtLoginState = snapshot
    }

    func setLaunchAtLoginEnabled(_ enabled: Bool) {
        launchAtLoginState = onLaunchAtLoginChange(enabled)
    }

    func openLoginItemsSettings() {
        onOpenLoginItemsSettings()
    }

    func updateGlobalShortcut(
        _ shortcut: GlobalShortcut,
        for action: GlobalShortcutAction
    ) {
        var candidate = globalShortcuts
        candidate.set(shortcut, for: action)
        if let error = candidate.validationError() {
            shortcutError = error
            return
        }
        if let error = onGlobalShortcutsChange(candidate) {
            shortcutError = error
            return
        }
        globalShortcuts = candidate
        shortcutError = nil
    }

    func updateProfileShortcut(
        _ shortcut: GlobalShortcut?,
        for profileID: UUID
    ) {
        var candidate = globalShortcuts
        candidate.setProfileShortcut(shortcut, for: profileID)
        if let error = candidate.validationError() {
            shortcutError = error
            return
        }
        if let error = onGlobalShortcutsChange(candidate) {
            shortcutError = error
            return
        }
        globalShortcuts = candidate
        shortcutError = nil
    }

    func resetGlobalShortcuts() {
        var defaults = GlobalShortcutSettings()
        defaults.reconcileProfiles(profiles)
        if let error = onGlobalShortcutsChange(defaults) {
            shortcutError = error
            return
        }
        globalShortcuts = defaults
        shortcutError = nil
    }

    func performPermissionAction(_ permission: PreferencesPermissionKind) {
        onPermissionAction(permission)
        refreshPermissions()
    }

    func openPermissionSettings(_ permission: PreferencesPermissionKind) {
        onOpenPermissionSettings(permission)
    }

    func isDisplayConnected(_ id: UUID) -> Bool {
        displays.contains { $0.id == id }
    }

    func displayLabel(for dock: DockConfig) -> String {
        guard let placement = dock.displayPlacement else { return "Automatic" }
        if let display = displays.first(where: { $0.id == placement.displayID }) {
            return displayLabel(for: display)
        }
        return "\(placement.displayName ?? "Display") — Not Connected"
    }

    func displayLabel(for display: DockDisplayDescriptor) -> String {
        display.isPrimary ? "\(display.label) (Main)" : display.label
    }
}
