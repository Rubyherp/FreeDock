import Foundation

struct DockTheme: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var name: String
    var appearance: DockAppearance
    var surfaceOpacity: Double
    var blurStyle: DockBlurStyle
    var cornerRadius: Double
    var shadowStrength: Double

    init(
        id: UUID = UUID(),
        name: String,
        appearance: DockAppearance,
        surfaceOpacity: Double,
        blurStyle: DockBlurStyle,
        cornerRadius: Double,
        shadowStrength: Double
    ) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.appearance = appearance
        self.surfaceOpacity = DockConfig.clamp(
            surfaceOpacity,
            to: DockConfig.surfaceOpacityRange
        )
        self.blurStyle = blurStyle
        self.cornerRadius = DockConfig.clamp(
            cornerRadius,
            to: DockConfig.cornerRadiusRange
        )
        self.shadowStrength = DockConfig.clamp(
            shadowStrength,
            to: DockConfig.shadowStrengthRange
        )
    }

    init(id: UUID = UUID(), name: String, dock: DockConfig) {
        self.init(
            id: id,
            name: name,
            appearance: dock.appearance,
            surfaceOpacity: dock.surfaceOpacity,
            blurStyle: dock.blurStyle,
            cornerRadius: dock.cornerRadius,
            shadowStrength: dock.shadowStrength
        )
    }

    func apply(to dock: inout DockConfig) {
        dock.appearance = appearance
        dock.surfaceOpacity = surfaceOpacity
        dock.blurStyle = blurStyle
        dock.cornerRadius = cornerRadius
        dock.shadowStrength = shadowStrength
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case appearance
        case surfaceOpacity
        case blurStyle
        case cornerRadius
        case shadowStrength
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            name: try container.decode(String.self, forKey: .name),
            appearance: (try? container.decode(
                DockAppearance.self,
                forKey: .appearance
            )) ?? .glass,
            surfaceOpacity: try container.decodeIfPresent(
                Double.self,
                forKey: .surfaceOpacity
            ) ?? 1,
            blurStyle: (try? container.decode(
                DockBlurStyle.self,
                forKey: .blurStyle
            )) ?? .regular,
            cornerRadius: try container.decodeIfPresent(
                Double.self,
                forKey: .cornerRadius
            ) ?? 18,
            shadowStrength: try container.decodeIfPresent(
                Double.self,
                forKey: .shadowStrength
            ) ?? 1
        )
    }
}
