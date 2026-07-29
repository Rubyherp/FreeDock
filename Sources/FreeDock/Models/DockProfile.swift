import Foundation

struct DockProfile: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var name: String
    var docks: [DockConfig]

    init(id: UUID = UUID(), name: String, docks: [DockConfig] = []) {
        self.id = id
        self.name = name
        self.docks = docks
    }
}
