import Foundation

enum DockAppearance: String, Codable, CaseIterable, Equatable, Sendable {
    case glass
    case light
    case dark

    var displayName: String {
        rawValue.capitalized
    }
}
