import SwiftUI

@MainActor
class DockState: ObservableObject {
    @Published var name: String
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
    @Published var showDynamicApplications: Bool
    @Published var dynamicApplicationLimit: Int
    @Published private(set) var isQuickLaunchPresented = false
    @Published private(set) var quickLaunchFocusGeneration = 0

    init(config: DockConfig) {
        name = config.name
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
        showDynamicApplications = config.showDynamicApplications
        dynamicApplicationLimit = config.dynamicApplicationLimit
    }

    func apply(_ config: DockConfig) {
        name = config.name
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
        showDynamicApplications = config.showDynamicApplications
        dynamicApplicationLimit = config.dynamicApplicationLimit
    }

    func presentQuickLaunch() {
        isQuickLaunchPresented = true
        quickLaunchFocusGeneration &+= 1
    }

    func dismissQuickLaunch() {
        isQuickLaunchPresented = false
    }
}
