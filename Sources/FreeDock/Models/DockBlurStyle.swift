import Foundation

enum DockBlurStyle: String, Codable, CaseIterable, Equatable, Sendable {
    case light
    case regular
    case strong

    var displayName: String {
        rawValue.capitalized
    }
}
