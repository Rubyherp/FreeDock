import Foundation

struct DockConfig: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var name: String
    var position: CGPoint
    var orientation: Orientation
    var iconSize: Double
    var items: [DockItem]

    init(id: UUID = UUID(), name: String, position: CGPoint = .zero,
         orientation: Orientation = .horizontal, iconSize: Double = 48,
         items: [DockItem] = []) {
        self.id = id
        self.name = name
        self.position = position
        self.orientation = orientation
        self.iconSize = iconSize
        self.items = items
    }
}
