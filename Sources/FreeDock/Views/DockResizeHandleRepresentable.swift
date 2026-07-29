import AppKit
import SwiftUI

@MainActor
struct DockResizeHandleRepresentable: NSViewRepresentable {
    let panel: DockPanel
    let orientation: Orientation
    let resizableItemCount: Int

    func makeNSView(context _: Context) -> DockResizeHandleView {
        let view = DockResizeHandleView(frame: .zero)
        view.dockPanel = panel
        view.orientation = orientation
        view.resizableItemCount = resizableItemCount
        return view
    }

    func updateNSView(_ view: DockResizeHandleView, context _: Context) {
        view.dockPanel = panel
        view.orientation = orientation
        view.resizableItemCount = resizableItemCount
    }
}
