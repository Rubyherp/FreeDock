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
    @Binding var hoveredItem: UUID?
    @State private var screenRect: NSRect = .zero
    @State private var bouncing = false

    let orientation: Orientation
    let showRunningIndicator: Bool
    let indicatorColor: Color

    private var isRunning: Bool {
        guard let bid = bundleID else { return false }
        return monitor.runningBundleIDs.contains(bid)
    }

    private var magnificationAnchor: UnitPoint {
        orientation == .horizontal ? .bottom : .center
    }

    private var hoverOffset: CGSize {
        orientation == .horizontal
            ? CGSize(width: 0, height: isHovering ? -2 : 0)
            : .zero
    }

    var body: some View {
        ZStack {
            Image(nsImage: (appInfo ?? AppInfo.resolve(from: item.appPath)).icon)
                .resizable()
                .frame(width: iconSize, height: iconSize)
                .shadow(color: .black.opacity(isHovering ? 0.25 : 0.14), radius: isHovering ? 8 : 3, x: 0, y: 3)
                .overlay(alignment: orientation == .horizontal ? .bottom : .leading) {
                    Circle()
                        .fill(indicatorColor.opacity(0.78))
                        .frame(width: 4, height: 4)
                        .shadow(color: .black.opacity(0.16), radius: 1, y: 1)
                        .offset(orientation == .horizontal ? CGSize(width: 0, height: 7) : CGSize(width: -7, height: 0))
                        .opacity(isRunning && showRunningIndicator ? 1 : 0)
                        .scaleEffect(isRunning && showRunningIndicator ? 1 : 0.35)
                        .animation(
                            .spring(response: 0.35, dampingFraction: 0.65),
                            value: isRunning && showRunningIndicator
                        )
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
        .scaleEffect(scale, anchor: magnificationAnchor)
        .offset(y: bouncing && orientation == .horizontal ? -5 : 0)
        .offset(x: bouncing && orientation == .vertical ? 5 : 0)
        .animation(.interpolatingSpring(stiffness: 300, damping: 4), value: bouncing)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: scale)
        .offset(hoverOffset)
        .onTapGesture {
            bounce()
            onLaunch()
        }
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

    private func bounce() {
        guard !bouncing else { return }
        bouncing = true
        withAnimation(.interpolatingSpring(stiffness: 300, damping: 8)) {
            bouncing = true
        }
        // 3 bounces worth of time then reset
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation(.spring()) {
                bouncing = false
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
