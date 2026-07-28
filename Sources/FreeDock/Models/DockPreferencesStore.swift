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
    @Published private(set) var profileName: String
    @Published private(set) var docks: [DockConfig]
    @Published var selectedDockID: UUID?

    private var profileID: UUID
    private let onChange: (UUID, DockPreferenceChange) -> Void

    init(
        profileID: UUID,
        profileName: String,
        docks: [DockConfig],
        onChange: @escaping (UUID, DockPreferenceChange) -> Void
    ) {
        self.profileID = profileID
        self.profileName = profileName
        self.docks = docks
        selectedDockID = docks.first?.id
        self.onChange = onChange
    }

    var selectedDock: DockConfig? {
        guard let selectedDockID else { return nil }
        return docks.first(where: { $0.id == selectedDockID })
    }

    func reload(profileID: UUID, profileName: String, docks: [DockConfig]) {
        let profileChanged = profileID != self.profileID
        self.profileID = profileID
        self.profileName = profileName
        self.docks = docks

        if profileChanged || !docks.contains(where: { $0.id == selectedDockID }) {
            selectedDockID = docks.first?.id
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
}
