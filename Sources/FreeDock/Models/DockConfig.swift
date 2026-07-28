import Foundation

struct DockConfig: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var name: String
    var position: CGPoint
    var orientation: Orientation
    var iconSize: Double
    var items: [DockItem]
    var autoHideWhenDocked: Bool

    init(id: UUID = UUID(), name: String, position: CGPoint = .zero,
         orientation: Orientation = .horizontal, iconSize: Double = 48,
         items: [DockItem] = [], autoHideWhenDocked: Bool = true) {
        self.id = id
        self.name = name
        self.position = position
        self.orientation = orientation
        self.iconSize = iconSize
        self.items = items
        self.autoHideWhenDocked = autoHideWhenDocked
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case position
        case orientation
        case iconSize
        case items
        case autoHideWhenDocked
    }

    /// Config files created before edge auto-hide existed keep the new default behavior.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        position = try container.decode(CGPoint.self, forKey: .position)
        orientation = try container.decode(Orientation.self, forKey: .orientation)
        iconSize = try container.decode(Double.self, forKey: .iconSize)
        items = try container.decode([DockItem].self, forKey: .items)
        autoHideWhenDocked = try container.decodeIfPresent(Bool.self, forKey: .autoHideWhenDocked) ?? true
    }
}
