import Foundation

struct DockSettings: Equatable, Sendable {
    var orientation: Orientation
    var iconSize: Double
    var magnificationEnabled: Bool
    var magnification: Double
    var itemSpacing: Double
    var appearance: DockAppearance
    var surfaceOpacity: Double
    var blurStyle: DockBlurStyle
    var cornerRadius: Double
    var shadowStrength: Double
    var showRunningIndicators: Bool
    var autoHideWhenDocked: Bool
    var autoHideDelay: Double

    init(_ config: DockConfig) {
        orientation = config.orientation
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
        autoHideWhenDocked = config.autoHideWhenDocked
        autoHideDelay = config.autoHideDelay
    }
}

struct DockConfig: Codable, Identifiable, Equatable, Sendable {
    static let iconSizeRange = 16.0 ... 128.0
    static let magnificationRange = 1.0 ... 1.75
    static let itemSpacingRange = 0.0 ... 24.0
    static let surfaceOpacityRange = 0.30 ... 1.0
    static let cornerRadiusRange = 8.0 ... 32.0
    static let shadowStrengthRange = 0.0 ... 2.0
    static let autoHideDelayRange = 0.1 ... 5.0

    var id: UUID
    var name: String
    var position: CGPoint
    var displayPlacement: DockDisplayPlacement?
    var orientation: Orientation
    var iconSize: Double
    var items: [DockItem]
    var autoHideWhenDocked: Bool
    var magnificationEnabled: Bool
    var magnification: Double
    var itemSpacing: Double
    var appearance: DockAppearance
    var surfaceOpacity: Double
    var blurStyle: DockBlurStyle
    var cornerRadius: Double
    var shadowStrength: Double
    var showRunningIndicators: Bool
    var autoHideDelay: Double

    init(id: UUID = UUID(), name: String, position: CGPoint = .zero,
         displayPlacement: DockDisplayPlacement? = nil,
         orientation: Orientation = .horizontal, iconSize: Double = 48,
         items: [DockItem] = [], autoHideWhenDocked: Bool = true,
         magnificationEnabled: Bool = true, magnification: Double = 1.30,
         itemSpacing: Double = 3, appearance: DockAppearance = .glass,
         surfaceOpacity: Double = 1, blurStyle: DockBlurStyle = .regular,
         cornerRadius: Double = 18, shadowStrength: Double = 1,
         showRunningIndicators: Bool = true, autoHideDelay: Double = 1) {
        self.id = id
        self.name = name
        self.position = position
        self.displayPlacement = displayPlacement
        self.orientation = orientation
        self.iconSize = Self.clamp(iconSize, to: Self.iconSizeRange)
        self.items = items
        self.autoHideWhenDocked = autoHideWhenDocked
        self.magnificationEnabled = magnificationEnabled
        self.magnification = Self.clamp(magnification, to: Self.magnificationRange)
        self.itemSpacing = Self.clamp(itemSpacing, to: Self.itemSpacingRange)
        self.appearance = appearance
        self.surfaceOpacity = Self.clamp(surfaceOpacity, to: Self.surfaceOpacityRange)
        self.blurStyle = blurStyle
        self.cornerRadius = Self.clamp(cornerRadius, to: Self.cornerRadiusRange)
        self.shadowStrength = Self.clamp(shadowStrength, to: Self.shadowStrengthRange)
        self.showRunningIndicators = showRunningIndicators
        self.autoHideDelay = Self.clamp(autoHideDelay, to: Self.autoHideDelayRange)
        normalizeDisplayPlacementEdge()
    }

    static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }

    static var defaultSettings: DockSettings {
        DockSettings(DockConfig(name: "Defaults"))
    }

    var settings: DockSettings {
        DockSettings(self)
    }

    mutating func apply(settings: DockSettings) {
        orientation = settings.orientation
        iconSize = Self.clamp(settings.iconSize, to: Self.iconSizeRange)
        magnificationEnabled = settings.magnificationEnabled
        magnification = Self.clamp(settings.magnification, to: Self.magnificationRange)
        itemSpacing = Self.clamp(settings.itemSpacing, to: Self.itemSpacingRange)
        appearance = settings.appearance
        surfaceOpacity = Self.clamp(settings.surfaceOpacity, to: Self.surfaceOpacityRange)
        blurStyle = settings.blurStyle
        cornerRadius = Self.clamp(settings.cornerRadius, to: Self.cornerRadiusRange)
        shadowStrength = Self.clamp(settings.shadowStrength, to: Self.shadowStrengthRange)
        showRunningIndicators = settings.showRunningIndicators
        autoHideWhenDocked = settings.autoHideWhenDocked
        autoHideDelay = Self.clamp(settings.autoHideDelay, to: Self.autoHideDelayRange)
        normalizeDisplayPlacementEdge()
    }

    mutating func normalizeDisplayPlacementEdge() {
        displayPlacement = displayPlacement?.respecting(
            orientation: orientation,
            autoHideWhenDocked: autoHideWhenDocked
        )
    }

    func duplicated(name: String, position: CGPoint) -> DockConfig {
        DockConfig(
            name: name,
            position: position,
            displayPlacement: displayPlacement,
            orientation: orientation,
            iconSize: iconSize,
            items: items.map { item in
                item.isSeparator
                    ? DockItem.separator()
                    : DockItem(appPath: item.appPath, label: item.label)
            },
            autoHideWhenDocked: autoHideWhenDocked,
            magnificationEnabled: magnificationEnabled,
            magnification: magnification,
            itemSpacing: itemSpacing,
            appearance: appearance,
            surfaceOpacity: surfaceOpacity,
            blurStyle: blurStyle,
            cornerRadius: cornerRadius,
            shadowStrength: shadowStrength,
            showRunningIndicators: showRunningIndicators,
            autoHideDelay: autoHideDelay
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case position
        case displayPlacement
        case orientation
        case iconSize
        case items
        case autoHideWhenDocked
        case magnificationEnabled
        case magnification
        case itemSpacing
        case appearance
        case surfaceOpacity
        case blurStyle
        case cornerRadius
        case shadowStrength
        case showRunningIndicators
        case autoHideDelay
    }

    /// Config files created before edge auto-hide existed keep the new default behavior.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        position = try container.decode(CGPoint.self, forKey: .position)
        displayPlacement = try? container.decode(
            DockDisplayPlacement.self,
            forKey: .displayPlacement
        )
        orientation = try container.decode(Orientation.self, forKey: .orientation)
        iconSize = Self.clamp(
            try container.decode(Double.self, forKey: .iconSize),
            to: Self.iconSizeRange
        )
        items = try container.decode([DockItem].self, forKey: .items)
        autoHideWhenDocked = try container.decodeIfPresent(Bool.self, forKey: .autoHideWhenDocked) ?? true
        magnificationEnabled = try container.decodeIfPresent(Bool.self, forKey: .magnificationEnabled) ?? true
        magnification = Self.clamp(
            try container.decodeIfPresent(Double.self, forKey: .magnification) ?? 1.30,
            to: Self.magnificationRange
        )
        itemSpacing = Self.clamp(
            try container.decodeIfPresent(Double.self, forKey: .itemSpacing) ?? 3,
            to: Self.itemSpacingRange
        )
        appearance = (try? container.decode(DockAppearance.self, forKey: .appearance)) ?? .glass
        surfaceOpacity = Self.clamp(
            try container.decodeIfPresent(Double.self, forKey: .surfaceOpacity) ?? 1,
            to: Self.surfaceOpacityRange
        )
        blurStyle = (try? container.decode(DockBlurStyle.self, forKey: .blurStyle)) ?? .regular
        cornerRadius = Self.clamp(
            try container.decodeIfPresent(Double.self, forKey: .cornerRadius) ?? 18,
            to: Self.cornerRadiusRange
        )
        shadowStrength = Self.clamp(
            try container.decodeIfPresent(Double.self, forKey: .shadowStrength) ?? 1,
            to: Self.shadowStrengthRange
        )
        showRunningIndicators = try container.decodeIfPresent(Bool.self, forKey: .showRunningIndicators) ?? true
        autoHideDelay = Self.clamp(
            try container.decodeIfPresent(Double.self, forKey: .autoHideDelay) ?? 1,
            to: Self.autoHideDelayRange
        )
        normalizeDisplayPlacementEdge()
    }
}
