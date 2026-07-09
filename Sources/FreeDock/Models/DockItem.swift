import Foundation

struct DockItem: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var appPath: String
    var label: String?

    init(id: UUID = UUID(), appPath: String, label: String? = nil) {
        self.id = id
        self.appPath = appPath
        self.label = label
    }
}
