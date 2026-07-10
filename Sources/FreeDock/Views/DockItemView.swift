import Cocoa
import SwiftUI

struct DockItemView: View {
    let item: DockItem
    let iconSize: Double
    let scale: CGFloat
    let onLaunch: () -> Void
    let onRemove: () -> Void

    @State private var bundleID: String? = nil
    @State private var appInfo: AppInfo? = nil
    @ObservedObject private var monitor = RunningAppMonitor.shared
    @State private var isHovering = false
    /// @State private var hoverTask: DispatchWorkItem? = nil
    @Binding var hoveredItem: UUID?
    @State private var screenRect: NSRect = .zero

    let orientation: Orientation

    private var isRunning: Bool {
        guard let bid = bundleID else { return false }
        return monitor.runningBundleIDs.contains(bid)
    }

    var body: some View {
        ZStack {
            VStack(spacing: 1) {
                Image(nsImage: (appInfo ?? AppInfo.resolve(from: item.appPath)).icon)
                    .resizable()
                    .frame(width: iconSize, height: iconSize)
                    .shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: 1)

                Circle()
                    .fill(.white)
                    .frame(width: 5, height: 5)
                    .opacity(isRunning ? 1 : 0)
            }
        }
        .background(ScreenRectReader { screenRect = $0 })
        .onHover { hovering in
            if hovering, let label = item.label {
                isHovering = true
                hoveredItem = item.id
                NSCursor.pointingHand.push()
                TooltipManager.shared.show(label, at: screenRect, orientation: orientation)
            } else {
                isHovering = false
                if hoveredItem == item.id {
                    hoveredItem = nil
                }
                NSCursor.pop()
                TooltipManager.shared.hide()
            }
        }

        .animation(.easeOut(duration: 0.15), value: isHovering)
        .padding(4)
        .scaleEffect(scale)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: scale)
        .offset(y: isHovering ? -2 : 0)
        .shadow(radius: isHovering ? 5 : 2)
        .onTapGesture { onLaunch() }
        .contextMenu {
            Button("Show in Finder") { showInFinder() }
            Button("Copy Path") { copyPath() }
            Divider()
            Button("Remove from Dock", role: .destructive) { onRemove() }
        }
        .onAppear {
            if appInfo == nil {
                appInfo = AppInfo.resolve(from: item.appPath)
            }
            if bundleID == nil {
                bundleID = AppInfo.resolveBundleID(from: item.appPath)
            }
        }
    }

    private func showInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.appPath)])
    }

    private func copyPath() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.appPath, forType: .string)
    }
}
