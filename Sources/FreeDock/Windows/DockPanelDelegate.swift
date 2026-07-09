import Foundation

@MainActor
protocol DockPanelDelegate: AnyObject {
    var lockPositions: Bool { get }
    func dockPanelDidMove(_ panel: DockPanel)
}
