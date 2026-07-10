import Foundation

struct DockItem: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var appPath: String
    var label: String?
    var isSeparator: Bool

    init(id: UUID = UUID(), appPath: String, label: String? = nil) {
        self.id = id
        self.appPath = appPath
        self.label = label
        isSeparator = false
    }

    static func separator() -> DockItem {
        var item = DockItem(appPath: "")
        item.isSeparator = true
        return item
    }
}
