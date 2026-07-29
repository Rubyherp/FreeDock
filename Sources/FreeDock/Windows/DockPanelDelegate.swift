import Foundation

@MainActor
protocol DockPanelDelegate: AnyObject {
    var lockPositions: Bool { get }
    func dockPanelDidMove(_ panel: DockPanel)
    func dockPanelMenuDidBeginTracking(_ panel: DockPanel)
    func dockPanelDidResignKey(_ panel: DockPanel)
    func dockPanelDidResize(_ panel: DockPanel, proposedIconSize: Double)
    func dockPanelDidFinishResize(_ panel: DockPanel)
    func currentIconSize(for panel: DockPanel) -> Double
}
