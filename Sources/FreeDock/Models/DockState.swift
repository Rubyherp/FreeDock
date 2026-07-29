import SwiftUI

@MainActor
class DockState: ObservableObject {
    @Published var iconSize: Double
    @Published var magnificationEnabled: Bool
    @Published var magnification: Double
    @Published var itemSpacing: Double
    @Published var appearance: DockAppearance
    @Published var surfaceOpacity: Double
    @Published var blurStyle: DockBlurStyle
    @Published var cornerRadius: Double
    @Published var shadowStrength: Double
    @Published var showRunningIndicators: Bool

    init(config: DockConfig) {
        iconSize = config.iconSize
        magnificationEnabled = config.magnificationEnabled
        magnification = config.magnification
        itemSpacing = config.itemSpacing
        appearance = config.appearance
        surfaceOpacity = config.surfaceOpacity
        blurStyle = config.blurStyle
        cornerRadius = config.cornerRadius
        shadowStrength = config.shadowStrength
        showRunningIndicators = config.showRunningIndicators
    }

    func apply(_ config: DockConfig) {
        iconSize = config.iconSize
        magnificationEnabled = config.magnificationEnabled
        magnification = config.magnification
        itemSpacing = config.itemSpacing
        appearance = config.appearance
        surfaceOpacity = config.surfaceOpacity
        blurStyle = config.blurStyle
        cornerRadius = config.cornerRadius
        shadowStrength = config.shadowStrength
        showRunningIndicators = config.showRunningIndicators
    }
}
