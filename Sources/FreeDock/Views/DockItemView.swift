import Cocoa
import SwiftUI

struct DockItemView: View {
    let item: DockItem
    let iconSize: Double
    let scale: CGFloat
    let onActivate: (NSRect) -> Void
    let onRemove: () -> Void

    @ObservedObject private var monitor = RunningAppMonitor.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var presentation: DockItemPresentation?
    @State private var isHovering = false
    @Binding var hoveredItem: UUID?
    @State private var screenRect: NSRect = .zero
    @State private var bouncing = false

    let orientation: Orientation
    let showRunningIndicator: Bool
    let indicatorColor: Color
    let isQuickLaunchSelected: Bool
    let quickLaunchResultPosition: Int?
    let quickLaunchResultCount: Int

    private var resolvedPresentation: DockItemPresentation {
        presentation ?? DockItemPresentation.resolve(item)
    }

    private var isRunning: Bool {
        guard item.kind == .application,
              let bundleID = resolvedPresentation.bundleID
        else {
            return false
        }
        return monitor.runningBundleIDs.contains(bundleID)
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
        Button(action: activate) {
            ZStack {
                Image(nsImage: resolvedPresentation.icon)
                    .resizable()
                    .frame(width: iconSize, height: iconSize)
                    .saturation(resolvedPresentation.isAvailable ? 1 : 0.15)
                    .opacity(resolvedPresentation.isAvailable ? 1 : 0.58)
                    .shadow(
                        color: .black.opacity(isHovering ? 0.25 : 0.14),
                        radius: isHovering ? 8 : 3,
                        x: 0,
                        y: 3
                    )
                    .overlay(alignment: orientation == .horizontal ? .bottom : .leading) {
                        runningIndicator
                    }
                    .overlay(alignment: .bottomTrailing) {
                        itemBadge
                    }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .background(ScreenRectReader { screenRect = $0 })
        .onHover(perform: updateHover)
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.15),
            value: isHovering
        )
        .padding(4)
        .scaleEffect(scale, anchor: magnificationAnchor)
        .offset(y: bouncing && orientation == .horizontal ? -5 : 0)
        .offset(x: bouncing && orientation == .vertical ? 5 : 0)
        .animation(
            reduceMotion
                ? nil
                : .interpolatingSpring(stiffness: 300, damping: 4),
            value: bouncing
        )
        .animation(
            reduceMotion
                ? nil
                : .spring(response: 0.25, dampingFraction: 0.7),
            value: scale
        )
        .offset(hoverOffset)
        .contextMenu { itemContextMenu }
        .accessibilityLabel(resolvedPresentation.displayName)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(accessibilityHint)
        .accessibilityAddTraits(
            isQuickLaunchSelected ? .isSelected : []
        )
        .onAppear(perform: refreshPresentation)
        .onChange(of: item) { _ in refreshPresentation() }
    }

    @ViewBuilder
    private var runningIndicator: some View {
        Circle()
            .fill(indicatorColor.opacity(0.78))
            .frame(width: 4, height: 4)
            .shadow(color: .black.opacity(0.16), radius: 1, y: 1)
            .offset(
                orientation == .horizontal
                    ? CGSize(width: 0, height: 7)
                    : CGSize(width: -7, height: 0)
            )
            .opacity(isRunning && showRunningIndicator ? 1 : 0)
            .scaleEffect(isRunning && showRunningIndicator ? 1 : 0.35)
            .animation(
                reduceMotion
                    ? nil
                    : .spring(response: 0.35, dampingFraction: 0.65),
                value: isRunning && showRunningIndicator
            )
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var itemBadge: some View {
        if !resolvedPresentation.isAvailable {
            Image(systemName: "questionmark")
                .font(.system(size: max(9, iconSize * 0.2), weight: .bold))
                .foregroundStyle(.white)
                .padding(max(3, iconSize * 0.055))
                .background(.secondary.opacity(0.78), in: Circle())
                .offset(x: 2, y: 2)
                .accessibilityHidden(true)
        } else if let badgeSymbolName = resolvedPresentation.badgeSymbolName {
            Image(systemName: badgeSymbolName)
                .font(.system(size: max(8, iconSize * 0.18), weight: .bold))
                .foregroundStyle(.white)
                .padding(max(3, iconSize * 0.06))
                .background(.black.opacity(0.62), in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.32), lineWidth: 0.5))
                .offset(x: 2, y: 2)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var itemContextMenu: some View {
        if item.smartStackSource == .recentFiles {
            Button("Show Recent Files") { activate() }
        } else if item.smartStackSource == .downloads {
            Button("Show Downloads") { activate() }
            if let downloadsURL {
                Button("Open Downloads in Finder") {
                    NSWorkspace.shared.open(downloadsURL)
                }
            }
        } else if item.kind == .folder {
            Button("Show Contents") { activate() }
            Button("Open in Finder") {
                NSWorkspace.shared.open(URL(fileURLWithPath: item.path))
            }
        } else {
            Button("Open") { activate() }
        }

        if item.fileURL != nil {
            Button("Show in Finder") { showInFinder() }
            Button("Copy Path") { copyPath() }
        }
        Divider()
        Button("Remove from Dock", role: .destructive) { onRemove() }
    }

    private var downloadsURL: URL? {
        guard item.smartStackSource == .downloads,
              let url = FileManager.default.urls(
                  for: .downloadsDirectory,
                  in: .userDomainMask
              ).first?.standardizedFileURL,
              FileManager.default.fileExists(atPath: url.path)
        else {
            return nil
        }
        return url
    }

    private var accessibilityValue: String {
        var parts = [resolvedPresentation.kindDescription]
        if isRunning {
            parts.append("running")
        }
        if !resolvedPresentation.isAvailable {
            parts.append("not available")
        }
        if isQuickLaunchSelected,
           let quickLaunchResultPosition,
           quickLaunchResultCount > 0
        {
            parts.append("selected")
            parts.append(
                "\(quickLaunchResultPosition) of \(quickLaunchResultCount)"
            )
        }
        return parts.joined(separator: ", ")
    }

    private var accessibilityHint: String {
        if item.smartStackSource == .recentFiles {
            return "Shows documents opened through FreeDock."
        }
        if item.smartStackSource == .downloads {
            return "Shows items in the Downloads folder."
        }

        switch item.kind {
        case .folder:
            return "Shows this folder’s contents."
        case .application:
            return "Opens the application."
        case .document:
            return "Opens the document in its default application."
        case .separator:
            return ""
        }
    }

    private func activate() {
        TooltipManager.shared.hide()
        bounce()
        onActivate(screenRect)
    }

    private func updateHover(_ hovering: Bool) {
        if hovering {
            isHovering = true
            hoveredItem = item.id
            NSCursor.pointingHand.push()
            TooltipManager.shared.show(
                resolvedPresentation.displayName,
                at: screenRect,
                orientation: orientation
            )
        } else {
            isHovering = false
            if hoveredItem == item.id {
                hoveredItem = nil
            }
            NSCursor.pop()
            TooltipManager.shared.hide()
        }
    }

    private func refreshPresentation() {
        presentation = DockItemPresentation.resolve(item)
    }

    private func bounce() {
        guard !reduceMotion, !bouncing else { return }
        bouncing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation(.spring()) {
                bouncing = false
            }
        }
    }

    private func showInFinder() {
        guard let fileURL = item.fileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([
            fileURL,
        ])
    }

    private func copyPath() {
        guard let fileURL = item.fileURL else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(fileURL.path, forType: .string)
    }
}
