import AppKit
import SwiftUI

@MainActor
struct DockResizeHandleRepresentable: NSViewRepresentable {
    let panel: DockPanel
    let orientation: Orientation

    func makeNSView(context _: Context) -> DockResizeHandleView {
        let view = DockResizeHandleView(frame: .zero)
        view.dockPanel = panel
        view.orientation = orientation
        return view
    }

    func updateNSView(_ view: DockResizeHandleView, context _: Context) {
        view.dockPanel = panel
        view.orientation = orientation
    }
}
