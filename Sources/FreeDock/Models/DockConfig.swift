import Foundation

struct DockConfig: Codable, Identifiable, Equatable, Sendable {
    static let iconSizeRange = 16.0 ... 128.0
    static let magnificationRange = 1.0 ... 1.75
    static let itemSpacingRange = 0.0 ... 24.0
    static let cornerRadiusRange = 8.0 ... 32.0
    static let autoHideDelayRange = 0.1 ... 5.0

    var id: UUID
    var name: String
    var position: CGPoint
    var orientation: Orientation
    var iconSize: Double
    var items: [DockItem]
    var autoHideWhenDocked: Bool
    var magnification: Double
    var itemSpacing: Double
    var appearance: DockAppearance
    var cornerRadius: Double
    var showRunningIndicators: Bool
    var autoHideDelay: Double

    init(id: UUID = UUID(), name: String, position: CGPoint = .zero,
         orientation: Orientation = .horizontal, iconSize: Double = 48,
         items: [DockItem] = [], autoHideWhenDocked: Bool = true,
         magnification: Double = 1.30, itemSpacing: Double = 3,
         appearance: DockAppearance = .glass, cornerRadius: Double = 18,
         showRunningIndicators: Bool = true, autoHideDelay: Double = 1) {
        self.id = id
        self.name = name
        self.position = position
        self.orientation = orientation
        self.iconSize = Self.clamp(iconSize, to: Self.iconSizeRange)
        self.items = items
        self.autoHideWhenDocked = autoHideWhenDocked
        self.magnification = Self.clamp(magnification, to: Self.magnificationRange)
        self.itemSpacing = Self.clamp(itemSpacing, to: Self.itemSpacingRange)
        self.appearance = appearance
        self.cornerRadius = Self.clamp(cornerRadius, to: Self.cornerRadiusRange)
        self.showRunningIndicators = showRunningIndicators
        self.autoHideDelay = Self.clamp(autoHideDelay, to: Self.autoHideDelayRange)
    }

    static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }

    func duplicated(name: String, position: CGPoint) -> DockConfig {
        DockConfig(
            name: name,
            position: position,
            orientation: orientation,
            iconSize: iconSize,
            items: items.map { item in
                item.isSeparator
                    ? DockItem.separator()
                    : DockItem(appPath: item.appPath, label: item.label)
            },
            autoHideWhenDocked: autoHideWhenDocked,
            magnification: magnification,
            itemSpacing: itemSpacing,
            appearance: appearance,
            cornerRadius: cornerRadius,
            showRunningIndicators: showRunningIndicators,
            autoHideDelay: autoHideDelay
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case position
        case orientation
        case iconSize
        case items
        case autoHideWhenDocked
        case magnification
        case itemSpacing
        case appearance
        case cornerRadius
        case showRunningIndicators
        case autoHideDelay
    }

    /// Config files created before edge auto-hide existed keep the new default behavior.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        position = try container.decode(CGPoint.self, forKey: .position)
        orientation = try container.decode(Orientation.self, forKey: .orientation)
        iconSize = Self.clamp(
            try container.decode(Double.self, forKey: .iconSize),
            to: Self.iconSizeRange
        )
        items = try container.decode([DockItem].self, forKey: .items)
        autoHideWhenDocked = try container.decodeIfPresent(Bool.self, forKey: .autoHideWhenDocked) ?? true
        magnification = Self.clamp(
            try container.decodeIfPresent(Double.self, forKey: .magnification) ?? 1.30,
            to: Self.magnificationRange
        )
        itemSpacing = Self.clamp(
            try container.decodeIfPresent(Double.self, forKey: .itemSpacing) ?? 3,
            to: Self.itemSpacingRange
        )
        appearance = (try? container.decode(DockAppearance.self, forKey: .appearance)) ?? .glass
        cornerRadius = Self.clamp(
            try container.decodeIfPresent(Double.self, forKey: .cornerRadius) ?? 18,
            to: Self.cornerRadiusRange
        )
        showRunningIndicators = try container.decodeIfPresent(Bool.self, forKey: .showRunningIndicators) ?? true
        autoHideDelay = Self.clamp(
            try container.decodeIfPresent(Double.self, forKey: .autoHideDelay) ?? 1,
            to: Self.autoHideDelayRange
        )
    }
}
