import SwiftUI

@MainActor
class DockState: ObservableObject {
    @Published var iconSize: Double

    init(iconSize: Double) {
        self.iconSize = iconSize
    }
}
