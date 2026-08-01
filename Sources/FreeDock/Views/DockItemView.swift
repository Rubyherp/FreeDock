import Cocoa
import SwiftUI

enum DockApplicationHoverTooltip {
    static func text(
        displayName: String,
        isWindowSwitchingEnabled: Bool,
        isThumbnailCaptureEnabled _: Bool
    ) -> String {
        guard isWindowSwitchingEnabled else {
            return "Right-click to enable window switching"
        }
        // Thumbnail permission affects only card artwork. Once switching is
        // enabled, use the normal Dock-style app label and let the preview
        // panel explain its own thumbnail state.
        return displayName
    }
}

struct DockItemView: View {
    let item: DockItem
    let iconSize: Double
    let scale: CGFloat
    let onActivate: (NSRect) -> Void
    let onRemove: () -> Void
    let isTransientApplication: Bool
    let onKeepInDock: () -> Void
    let onFolderOptionsChanged: (FolderStackOptions) -> Void
    let hasRecentFiles: () -> Bool
    let onClearRecentFilesRequested: () -> Void
    let onOpenDocumentWithApplication: (URL) -> Void
    let onChooseFilesForApplication: () -> Void
    let onApplicationHoverChanged: (Bool, NSRect) -> Void
    let onShowApplicationWindows: (NSRect) -> Void
    let onEnableWindowThumbnails: () -> Void
    let isWindowPreviewAccessibilityTrusted: () -> Bool
    let isWindowPreviewScreenCaptureTrusted: () -> Bool

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
        // Hover belongs to this fixed cell, not the magnified icon. Otherwise
        // the icon can move out from under the pointer and cancel its own
        // preview timer while it animates.
        .frame(
            width: iconSize + 9,
            height: iconSize + 11
        )
        .contentShape(Rectangle())
        .background(ScreenRectReader { updatedScreenRect in
            guard screenRect != updatedScreenRect else { return }
            screenRect = updatedScreenRect
            if isHovering,
               item.kind == .application,
               isRunning
            {
                onApplicationHoverChanged(true, updatedScreenRect)
            }
        })
        .onHover(perform: updateHover)
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.15),
            value: isHovering
        )
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
            recentFilesMenu
        } else if item.smartStackSource == .downloads {
            downloadsMenu
        } else if item.kind == .folder {
            folderMenu
        } else if item.kind == .application {
            applicationMenu
        } else {
            documentMenu
        }

        if item.fileURL != nil, item.kind != .folder {
            Divider()
            Button("Show in Finder") { showInFinder() }
                .disabled(!resolvedPresentation.isAvailable)
            Button("Copy Path") { copyPath() }
        }
        Divider()
        if isTransientApplication {
            Button("Keep in Dock", action: onKeepInDock)
        } else {
            Button("Remove from Dock", role: .destructive) { onRemove() }
        }
    }

    @ViewBuilder
    private var applicationMenu: some View {
        if let bundleID = resolvedPresentation.bundleID {
            let state = DockApplicationActionController()
                .state(forBundleIdentifier: bundleID)
            if state.isRunning {
                if state.isHidden {
                    Button("Show \(resolvedPresentation.displayName)") {
                        performApplicationAction(.show, bundleID: bundleID)
                    }
                } else {
                    Button("Bring \(resolvedPresentation.displayName) to Front") {
                        performApplicationAction(.activate, bundleID: bundleID)
                    }
                }

                if state.visibleInstanceCount > 0 {
                    Button(
                        state.instanceCount > 1
                            ? "Hide All Instances"
                            : "Hide \(resolvedPresentation.displayName)"
                    ) {
                        performApplicationAction(.hide, bundleID: bundleID)
                    }
                }

                Button(
                    state.instanceCount > 1
                        ? "Quit All Instances"
                        : "Quit \(resolvedPresentation.displayName)"
                ) {
                    performApplicationAction(.quit, bundleID: bundleID)
                }
            } else {
                Button("Open") { activate() }
                    .disabled(!resolvedPresentation.isAvailable)
            }
        } else {
            Button("Open") { activate() }
                .disabled(!resolvedPresentation.isAvailable)
        }

        let hasWindowPreviewAccess =
            isWindowPreviewAccessibilityTrusted()
        if hasWindowPreviewAccess {
            Button("Show Windows…") {
                onShowApplicationWindows(screenRect)
            }
            .disabled(
                !resolvedPresentation.isAvailable
                    || !isRunning
            )

            if !isWindowPreviewScreenCaptureTrusted() {
                Button("Enable Window Thumbnails…") {
                    onEnableWindowThumbnails()
                }
                .disabled(!resolvedPresentation.isAvailable)
            }
        } else {
            Button("Enable Window Switching…") {
                onShowApplicationWindows(screenRect)
            }
            .disabled(!resolvedPresentation.isAvailable)
        }

        Divider()
        Button(
            "Open Files with \(resolvedPresentation.displayName)…",
            action: onChooseFilesForApplication
        )
        .disabled(!resolvedPresentation.isAvailable)
    }

    @ViewBuilder
    private var documentMenu: some View {
        Button("Open") { activate() }
            .disabled(!resolvedPresentation.isAvailable)

        let applications = openWithApplications
        Menu("Open With") {
            ForEach(applications, id: \.url) { application in
                Button {
                    onOpenDocumentWithApplication(application.url)
                } label: {
                    Label {
                        Text(application.name)
                    } icon: {
                        Image(nsImage: application.icon)
                    }
                }
            }
        }
        .disabled(applications.isEmpty)
    }

    @ViewBuilder
    private var folderMenu: some View {
        Button("Show Contents") { activate() }
            .disabled(!resolvedPresentation.isAvailable)
        Button("Open in Finder") {
            NSWorkspace.shared.open(URL(fileURLWithPath: item.path))
        }
        .disabled(!resolvedPresentation.isAvailable)

        stackOptionsMenu

        Divider()
        Button("Copy Path") { copyPath() }
    }

    @ViewBuilder
    private var downloadsMenu: some View {
        Button("Show Downloads") { activate() }
            .disabled(downloadsURL == nil)
        Button("Open Downloads in Finder") {
            guard let downloadsURL else { return }
            NSWorkspace.shared.open(downloadsURL)
        }
        .disabled(downloadsURL == nil)

        stackOptionsMenu
    }

    @ViewBuilder
    private var recentFilesMenu: some View {
        Button("Show Recent Files") { activate() }
        stackOptionsMenu
        Divider()
        Button(
            "Clear Recent Files…",
            role: .destructive,
            action: onClearRecentFilesRequested
        )
        .disabled(!hasRecentFiles())
    }

    @ViewBuilder
    private var stackOptionsMenu: some View {
        Menu("View As") {
            presentationToggle("Automatic", value: .automatic)
            presentationToggle("Grid", value: .grid)
            presentationToggle("List", value: .list)
        }

        Menu("Sort By") {
            if item.smartStackSource == .recentFiles {
                sortOrderToggle("Recently Opened", value: .recentlyOpened)
            }
            sortOrderToggle("Name", value: .name)
            sortOrderToggle("Date Modified", value: .dateModified)
            sortOrderToggle("Kind", value: .kind)
        }

        if item.smartStackSource != .recentFiles {
            Toggle("Show Hidden Files", isOn: showHiddenFilesBinding)
        }
    }

    private func presentationToggle(
        _ title: String,
        value: FolderStackOptions.Presentation
    ) -> some View {
        Toggle(
            title,
            isOn: Binding(
                get: { resolvedFolderOptions.presentation == value },
                set: { selected in
                    guard selected else { return }
                    updateFolderPresentation(value)
                }
            )
        )
    }

    private func sortOrderToggle(
        _ title: String,
        value: FolderStackOptions.SortOrder
    ) -> some View {
        Toggle(
            title,
            isOn: Binding(
                get: { resolvedFolderOptions.sortOrder == value },
                set: { selected in
                    guard selected else { return }
                    updateFolderSortOrder(value)
                }
            )
        )
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

    private var resolvedFolderOptions: FolderStackOptions {
        var options = item.folderOptions
            ?? item.smartStackSource?.defaultOptions
            ?? FolderStackOptions()
        if item.smartStackSource == .recentFiles {
            options.showHiddenFiles = false
        } else if options.sortOrder == .recentlyOpened {
            options.sortOrder = item.smartStackSource?.defaultOptions.sortOrder
                ?? .name
        }
        return options
    }

    private var showHiddenFilesBinding: Binding<Bool> {
        Binding(
            get: { resolvedFolderOptions.showHiddenFiles },
            set: { showHiddenFiles in
                var options = resolvedFolderOptions
                options.showHiddenFiles = showHiddenFiles
                onFolderOptionsChanged(options)
            }
        )
    }

    private var openWithApplications: [OpenWithApplication] {
        guard item.kind == .document,
              resolvedPresentation.isAvailable,
              let documentURL = item.fileURL
        else {
            return []
        }

        let defaultApplicationKey = NSWorkspace.shared
            .urlForApplication(toOpen: documentURL)?
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
        var seenPaths = Set<String>()
        var applications = NSWorkspace.shared
            .urlsForApplications(toOpen: documentURL)
            .compactMap { url -> OpenWithApplication? in
                let standardizedURL = url.standardizedFileURL
                let key = standardizedURL
                    .resolvingSymlinksInPath()
                    .path
                guard seenPaths.insert(key).inserted else { return nil }
                let displayName = FileManager.default.displayName(
                    atPath: standardizedURL.path
                )
                let menuName = displayName.hasSuffix(".app")
                    ? (displayName as NSString).deletingPathExtension
                    : displayName
                return OpenWithApplication(
                    url: standardizedURL,
                    name: menuName,
                    icon: NSWorkspace.shared.icon(forFile: standardizedURL.path),
                    isDefault: key == defaultApplicationKey
                )
            }
        applications.sort {
            if $0.isDefault != $1.isDefault {
                return $0.isDefault
            }
            return $0.name.localizedStandardCompare($1.name)
                == .orderedAscending
        }
        return applications
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
            return "Opens the application. Use the context menu to show open windows or choose files, or drop compatible files onto it."
        case .document:
            return "Opens the document in its default application."
        case .separator:
            return ""
        }
    }

    private func activate() {
        TooltipManager.shared.hide()
        if item.kind == .application {
            onApplicationHoverChanged(false, screenRect)
        }
        bounce()
        onActivate(screenRect)
    }

    private func updateHover(_ hovering: Bool) {
        if hovering {
            isHovering = true
            hoveredItem = item.id
            NSCursor.pointingHand.push()
            TooltipManager.shared.show(
                windowPreviewTooltipText,
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

        if item.kind == .application {
            onApplicationHoverChanged(
                hovering && isRunning,
                screenRect
            )
        }
    }

    private var windowPreviewTooltipText: String {
        guard item.kind == .application,
              isRunning
        else {
            return resolvedPresentation.displayName
        }
        if !isWindowPreviewAccessibilityTrusted() {
            return DockApplicationHoverTooltip.text(
                displayName: resolvedPresentation.displayName,
                isWindowSwitchingEnabled: false,
                isThumbnailCaptureEnabled: false
            )
        }
        return DockApplicationHoverTooltip.text(
            displayName: resolvedPresentation.displayName,
            isWindowSwitchingEnabled: true,
            isThumbnailCaptureEnabled:
                isWindowPreviewScreenCaptureTrusted()
        )
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

    private func performApplicationAction(
        _ action: DockApplicationAction,
        bundleID: String
    ) {
        let result = DockApplicationActionController().perform(
            action,
            forBundleIdentifier: bundleID
        )
        if !result.sentRequest || !result.allRequestsAccepted {
            NSSound.beep()
        }
    }

    private func updateFolderPresentation(
        _ presentation: FolderStackOptions.Presentation
    ) {
        var options = resolvedFolderOptions
        options.presentation = presentation
        onFolderOptionsChanged(options)
    }

    private func updateFolderSortOrder(
        _ sortOrder: FolderStackOptions.SortOrder
    ) {
        var options = resolvedFolderOptions
        options.sortOrder = sortOrder
        onFolderOptionsChanged(options)
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

private struct OpenWithApplication {
    let url: URL
    let name: String
    let icon: NSImage
    let isDefault: Bool
}
