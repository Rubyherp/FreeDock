import SwiftUI
import Cocoa

struct DockItemView: View {
    let item: DockItem
    let iconSize: Double
    let onLaunch: () -> Void
    let onRemove: () -> Void

    @State private var isHovering = false
    @State private var bundleID: String? = nil
    @State private var appInfo: AppInfo? = nil
    @ObservedObject private var monitor = RunningAppMonitor.shared

    private var isRunning: Bool {
        guard let bid = bundleID else { return false }
        return monitor.runningBundleIDs.contains(bid)
    }

    var body: some View {
        VStack(spacing: 2) {
            ZStack(alignment: .bottomTrailing) {
                Image(nsImage: (appInfo ?? AppInfo.resolve(from: item.appPath)).icon)
                    .resizable()
                    .frame(width: iconSize, height: iconSize)
                    .shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: 1)

                if isRunning {
                    Circle().fill(.green).frame(width: 7, height: 7).shadow(color: .green.opacity(0.6), radius: 2).offset(x: -1, y: -1)
                }
            }

            if let label = item.label {
                Text(label).font(.caption2).foregroundColor(.secondary).lineLimit(1).truncationMode(.tail).frame(maxWidth: iconSize + 12)
            }
        }
        .padding(4)
        .scaleEffect(isHovering ? 1.08 : 1.0)
        .animation(.easeInOut(duration: 0.12), value: isHovering)
        .onHover { h in
            isHovering = h
            if h { NSCursor.pointingHand.push() }
            else { NSCursor.pop() }
        }
        .onTapGesture { onLaunch() }
        .contextMenu {
            Button("Show in Finder") { showInFinder() }
            Button("Copy Path") { copyPath() }
            Divider()
            Button("Remove from Dock", role: .destructive) { onRemove() }
        }
        .onAppear {
            if appInfo == nil { appInfo = AppInfo.resolve(from: item.appPath) }
            if bundleID == nil { bundleID = AppInfo.resolveBundleID(from: item.appPath) }
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
