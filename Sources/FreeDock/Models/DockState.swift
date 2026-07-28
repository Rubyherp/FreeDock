import SwiftUI

@MainActor
class DockState: ObservableObject {
    @Published var iconSize: Double
    @Published var magnification: Double
    @Published var itemSpacing: Double
    @Published var appearance: DockAppearance
    @Published var cornerRadius: Double
    @Published var showRunningIndicators: Bool

    init(config: DockConfig) {
        iconSize = config.iconSize
        magnification = config.magnification
        itemSpacing = config.itemSpacing
        appearance = config.appearance
        cornerRadius = config.cornerRadius
        showRunningIndicators = config.showRunningIndicators
    }

    func apply(_ config: DockConfig) {
        iconSize = config.iconSize
        magnification = config.magnification
        itemSpacing = config.itemSpacing
        appearance = config.appearance
        cornerRadius = config.cornerRadius
        showRunningIndicators = config.showRunningIndicators
    }
}
