import Foundation

struct AppConfig: Codable, Sendable {
    var docks: [DockConfig]

    init(docks: [DockConfig] = []) {
        self.docks = docks
    }
}
