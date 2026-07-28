import SwiftUI

enum DockPreferenceChange: Equatable {
    case orientation(Orientation)
    case iconSize(Double)
    case magnification(Double)
    case itemSpacing(Double)
    case appearance(DockAppearance)
    case cornerRadius(Double)
    case showRunningIndicators(Bool)
    case autoHideWhenDocked(Bool)
    case autoHideDelay(Double)
}

enum DockManagementAction: Equatable {
    case activateProfile(UUID)
    case createProfile
    case renameActiveProfile
    case deleteActiveProfile
    case createDock(Orientation)
    case renameDock(UUID)
    case duplicateDock(UUID)
    case deleteDock(UUID)
    case resetDockSettings(UUID)
    case copyDockSettingsToAll(UUID)
}

extension DockConfig {
    mutating func apply(_ change: DockPreferenceChange) {
        switch change {
        case let .orientation(value):
            orientation = value
        case let .iconSize(value):
            iconSize = Self.clamp(value, to: Self.iconSizeRange)
        case let .magnification(value):
            magnification = Self.clamp(value, to: Self.magnificationRange)
        case let .itemSpacing(value):
            itemSpacing = Self.clamp(value, to: Self.itemSpacingRange)
        case let .appearance(value):
            appearance = value
        case let .cornerRadius(value):
            cornerRadius = Self.clamp(value, to: Self.cornerRadiusRange)
        case let .showRunningIndicators(value):
            showRunningIndicators = value
        case let .autoHideWhenDocked(value):
            autoHideWhenDocked = value
        case let .autoHideDelay(value):
            autoHideDelay = Self.clamp(value, to: Self.autoHideDelayRange)
        }
    }
}

@MainActor
final class DockPreferencesStore: ObservableObject {
    @Published private(set) var profiles: [DockProfile]
    @Published private(set) var activeProfileID: UUID
    @Published private(set) var docks: [DockConfig]
    @Published var selectedDockID: UUID?

    private let onChange: (UUID, DockPreferenceChange) -> Void
    private let onManagementAction: (DockManagementAction) -> Void

    init(
        profiles: [DockProfile],
        activeProfileID: UUID,
        onChange: @escaping (UUID, DockPreferenceChange) -> Void,
        onManagementAction: @escaping (DockManagementAction) -> Void
    ) {
        self.profiles = profiles
        self.activeProfileID = activeProfileID
        let activeDocks = profiles.first(where: { $0.id == activeProfileID })?.docks ?? []
        docks = activeDocks
        selectedDockID = activeDocks.first?.id
        self.onChange = onChange
        self.onManagementAction = onManagementAction
    }

    var activeProfileName: String {
        profiles.first(where: { $0.id == activeProfileID })?.name ?? "Default"
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

    func reload(profiles: [DockProfile], activeProfileID: UUID) {
        let profileChanged = activeProfileID != self.activeProfileID
        self.profiles = profiles
        self.activeProfileID = activeProfileID
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
}
