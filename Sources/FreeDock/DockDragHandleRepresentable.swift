import SwiftUI

struct DockDragHandleRepresentable: NSViewRepresentable {
    let panel: DockPanel
    let orientation: Orientation

    func makeNSView(context: Context) -> DockDragHandleView {
        let view = DockDragHandleView(frame: .zero)
        view.dockPanel = panel
        view.orientation = orientation
        return view
    }

    func updateNSView(_ view: DockDragHandleView, context: Context) {
        view.dockPanel = panel
        view.orientation = orientation
    }
}
