import SwiftUI
import UniformTypeIdentifiers

struct DockContentView: View {
    private static let dockItemType = UTType.freeDockItem

    let panel: DockPanel
    let profileID: UUID
    @Binding var items: [DockItem]
    let orientation: Orientation
    @ObservedObject var state: DockState
    @ObservedObject var itemDragCoordinator: DockItemDragCoordinator
    let onItemActivation: @MainActor (DockItem, NSRect) -> Void
    let onItemTransfer: @MainActor (
        DockItemDragSession,
        DockItemTransferDestination,
        DockItemTransferOperation
    ) -> Bool
    let onQuickLaunchDismiss: @MainActor () -> Void
    let onAddItemsRequested: @MainActor () -> Void
    let onAddSmartStackRequested: @MainActor (SmartStackSource) -> Void
    let onFolderOptionsChanged: @MainActor (
        DockItem.ID,
        FolderStackOptions
    ) -> Void
    let hasRecentFiles: @MainActor () -> Bool
    let onClearRecentFilesRequested: @MainActor () -> Void
    let onOpenDocumentWithApplication: @MainActor (
        DockItem,
        URL
    ) -> Void
    let onOpenFilesWithApplication: @MainActor (
        DockItem,
        [URL]
    ) -> Bool
    let onCanOpenFilesWithApplication: @MainActor (
        DockItem,
        [URL]
    ) -> Bool
    let onChooseFilesForApplication: @MainActor (DockItem) -> Void
    let onApplicationHoverChanged: @MainActor (
        DockItem,
        NSRect,
        Bool
    ) -> Void
    let onShowApplicationWindows: @MainActor (
        DockItem,
        NSRect
    ) -> Void
    let onEnableWindowThumbnails: @MainActor () -> Void
    let isWindowPreviewAccessibilityTrusted:
        @MainActor () -> Bool
    let isWindowPreviewScreenCaptureTrusted:
        @MainActor () -> Bool
    let onDismissWindowPreview: @MainActor () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var iconSize: Double {
        state.iconSize
    }

    @State private var isTargeted = false
    @State private var dropPulse = false
    @State private var displayedItems: [DockItem]?
    @State private var hoveredItem: UUID?
    @State private var dropTargetItem: UUID?
    @State private var applicationFileDropTargetItem: UUID?
    @State private var applicationFileDropPresentation:
        ApplicationFileDropPresentation?
    @State private var applicationFileDropURLs: [URL]?
    @State private var applicationFileDropPreflightID: UUID?
    @State private var trailingTargeted = false
    @State private var externalFileDropClaimState =
        DockExternalFileDropClaimState()
    @State private var externalFileDropInteractionToken: UUID?
    @State private var externalFileDropExpiryWorkItem: DispatchWorkItem?
    @State private var quickLaunchQuery = ""
    @State private var quickLaunchSelection = QuickLaunchSelection()

    private var currentItems: [DockItem] {
        displayedItems ?? items
    }

    private var resizableItemCount: Int {
        DockResizeGestureMath.resizableItemCount(in: currentItems)
    }

    private var quickLaunchResults: [QuickLaunchSearchResult] {
        QuickLaunchSearch.results(
            in: currentItems,
            matching: quickLaunchQuery
        )
    }

    private var quickLaunchResultsInDockOrder: [QuickLaunchSearchResult] {
        quickLaunchResults.sorted { $0.dockIndex < $1.dockIndex }
    }

    private var matchingItemIDs: Set<DockItem.ID> {
        Set(quickLaunchResults.map(\.id))
    }

    private var selectedQuickLaunchItemID: DockItem.ID? {
        quickLaunchSelection.selectedItemID
    }

    private var selectedQuickLaunchResult: QuickLaunchSearchResult? {
        quickLaunchSelection.selectedResult(in: quickLaunchResults)
    }

    private var surfaceCornerRadius: CGFloat {
        CGFloat(state.cornerRadius)
    }

    private var configuredMagnificationHeadroom: CGFloat {
        guard state.magnificationEnabled else { return 10 }
        return max(10, iconSize * (state.magnification - 1 + 0.04))
    }

    private var magnificationHeadroom: CGFloat {
        state.isQuickLaunchPresented
            ? 10
            : configuredMagnificationHeadroom
    }

    private var chromeColor: Color {
        switch state.appearance {
        case .glass:
            return .primary
        case .light:
            return .black
        case .dark:
            return .white
        }
    }

    var body: some View {
        dockLayout
            .contentShape(Rectangle())
            .onHover { hovering in
                if !hovering { hoveredItem = nil }
            }
            .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                guard !state.isQuickLaunchPresented else { return false }
                return handleFileDrop(providers)
            }
            .onChange(of: isTargeted) { targeted in
                updateDropPulse(targeted)
                updateExternalFileDropTargeting(targeted)
            }
            .onAppear {
                displayedItems = items
                if state.isQuickLaunchPresented {
                    resetQuickLaunch()
                }
            }
            .onChange(of: items) {
                displayedItems = $0
                reconcileQuickLaunchSelection()
            }
            .onChange(of: itemDragCoordinator.contentRevision) { _ in
                withAnimation(.spring(
                    response: 0.3,
                    dampingFraction: 0.74
                )) {
                    displayedItems = items
                }
                reconcileQuickLaunchSelection()
            }
            .onChange(of: state.quickLaunchFocusGeneration) { _ in
                resetQuickLaunch()
            }
            .onChange(of: quickLaunchQuery) { _ in
                reconcileQuickLaunchSelection()
            }
            .onChange(of: hoveredItem) { itemID in
                updateQuickLaunchSelectionFromHover(itemID)
            }
            .onDisappear {
                onDismissWindowPreview()
                tearDownExternalFileDropInteraction()
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(state.name) dock")
            .contextMenu {
                Button("Add Files or Folders…") {
                    onAddItemsRequested()
                }
                Menu("Add Stack") {
                    Button("Recent Files") {
                        onAddSmartStackRequested(.recentFiles)
                    }
                    .disabled(!canAddSmartStack(.recentFiles))

                    Button("Downloads") {
                        onAddSmartStackRequested(.downloads)
                    }
                    .disabled(!canAddSmartStack(.downloads))
                }
                Divider()
                Button("Add Separator") {
                    var updated = displayedItems ?? items
                    updated.append(.separator())
                    commitItems(updated)
                }
            }
    }

    @ViewBuilder
    private var dockLayout: some View {
        if state.isQuickLaunchPresented {
            quickLaunchDockLayout
        } else if orientation == .horizontal {
            HStack(spacing: state.itemSpacing) {
                dockMoveHandle
                content
            }
                .padding(.horizontal, 8)
                .padding(.vertical, 9)
                .background(dockSurface)
                .overlay(dropZoneHighlight)
                .overlay(alignment: .trailing) {
                    if resizableItemCount > 0 {
                        DockResizeHandleRepresentable(
                            panel: panel,
                            orientation: orientation,
                            resizableItemCount: resizableItemCount
                        )
                        .frame(width: 18)
                    }
                }
                .padding(.top, magnificationHeadroom)
        } else {
            VStack(spacing: state.itemSpacing) {
                dockMoveHandle
                content
            }
                .padding(.horizontal, 9)
                .padding(.vertical, 8)
                .background(dockSurface)
                .overlay(dropZoneHighlight)
                .overlay(alignment: .bottom) {
                    if resizableItemCount > 0 {
                        DockResizeHandleRepresentable(
                            panel: panel,
                            orientation: orientation,
                            resizableItemCount: resizableItemCount
                        )
                        .frame(height: 18)
                    }
                }
                .padding(.horizontal, magnificationHeadroom * 0.52)
        }
    }

    @ViewBuilder
    private var dockMoveHandle: some View {
        if orientation == .horizontal {
            DockDragHandleRepresentable(
                panel: panel,
                orientation: orientation
            )
            .frame(width: 16, height: iconSize + 11)
            .help("Drag to move this dock")
            .accessibilityLabel("Move \(state.name) dock")
        } else {
            DockDragHandleRepresentable(
                panel: panel,
                orientation: orientation
            )
            .frame(width: iconSize + 11, height: 16)
            .help("Drag to move this dock")
            .accessibilityLabel("Move \(state.name) dock")
        }
    }

    @ViewBuilder
    private var quickLaunchDockLayout: some View {
        if orientation == .horizontal {
            if panel.dockedEdgeForLayout == .top {
                VStack(alignment: .leading, spacing: 7) {
                    quickLaunchItemsSurface
                    quickLaunchSearchPanel
                }
                .padding(.top, configuredMagnificationHeadroom)
                .padding(.bottom, 10)
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    quickLaunchSearchPanel
                    quickLaunchItemsSurface
                }
                .padding(.top, 10)
            }
        } else if panel.dockedEdgeForLayout == .right {
            HStack(alignment: .top, spacing: 7) {
                quickLaunchSearchPanel
                quickLaunchItemsSurface
            }
            .padding(
                .horizontal,
                configuredMagnificationHeadroom * 0.52
            )
        } else {
            HStack(alignment: .top, spacing: 7) {
                quickLaunchItemsSurface
                quickLaunchSearchPanel
            }
            .padding(
                .horizontal,
                configuredMagnificationHeadroom * 0.52
            )
        }
    }

    private var quickLaunchSearchPanel: some View {
        quickLaunchSearchBar
            .padding(6)
            .background(dockSurface)
    }

    @ViewBuilder
    private var quickLaunchItemsSurface: some View {
        if orientation == .horizontal {
            quickLaunchItems
                .padding(.horizontal, 8)
                .padding(.vertical, 9)
                .background(dockSurface)
        } else {
            quickLaunchItems
                .padding(.horizontal, 9)
                .padding(.vertical, 8)
                .background(dockSurface)
        }
    }

    private var quickLaunchItems: some View {
        ZStack {
            if orientation == .horizontal {
                HStack(spacing: state.itemSpacing) { content }
            } else {
                VStack(spacing: state.itemSpacing) { content }
            }

            if quickLaunchResults.isEmpty, !currentItems.isEmpty {
                Text(
                    quickLaunchQuery.isEmpty
                        ? "No launchable items"
                        : "No matching items"
                )
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(chromeColor.opacity(0.76))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(chromeColor.opacity(0.10))
                )
                .accessibilityHidden(true)
            }
        }
    }

    private var quickLaunchSearchBar: some View {
        VStack(spacing: 3) {
            HStack(spacing: 7) {
                QuickLaunchSearchField(
                    text: $quickLaunchQuery,
                    focusGeneration: state.quickLaunchFocusGeneration,
                    placeholder: "Search this dock",
                    accessibilityLabel: "Search \(state.name)",
                    accessibilityHelp: "Type to filter. Use arrow keys to choose, Return to open, and Escape to close.",
                    accessibilityStatus: quickLaunchAccessibilityValue,
                    onCommand: handleQuickLaunchCommand
                )
                .frame(height: 22)

                Text("\(quickLaunchResults.count)")
                    .font(.system(
                        size: 10,
                        weight: .semibold,
                        design: .rounded
                    ))
                    .foregroundStyle(chromeColor.opacity(0.55))
                    .lineLimit(1)
            }

            HStack(spacing: 6) {
                Text(quickLaunchSelectionLabel)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 6)
                if selectedQuickLaunchResult != nil {
                    Text("\(quickLaunchSelectionPositionText)  ↩ Open")
                        .lineLimit(1)
                }
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(chromeColor.opacity(0.58))
            .accessibilityHidden(true)
        }
        .frame(
            width: 228,
            height: 43
        )
        .padding(.horizontal, 9)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(chromeColor.opacity(0.075))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(chromeColor.opacity(0.13), lineWidth: 0.75)
                .allowsHitTesting(false)
        }
    }

    private var quickLaunchSelectionLabel: String {
        if let selectedQuickLaunchResult {
            return selectedQuickLaunchResult.displayLabel
        }
        return quickLaunchQuery.isEmpty
            ? "No launchable items"
            : "No matching items"
    }

    private var quickLaunchSelectionPositionText: String {
        guard let selectedQuickLaunchResult,
              let position = quickLaunchResultPosition(
                  for: selectedQuickLaunchResult.id
              )
        else {
            return ""
        }
        return "\(position)/\(quickLaunchResults.count)"
    }

    @ViewBuilder
    private var content: some View {
        if currentItems.isEmpty {
            Label("Drop apps, files, or folders", systemImage: "plus.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(chromeColor.opacity(0.65))
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
                .background {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(
                            Color.accentColor.opacity(
                                trailingTargeted ? 0.12 : 0
                            )
                        )
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(
                            Color.accentColor.opacity(
                                trailingTargeted ? 0.7 : 0
                            ),
                            lineWidth: 1
                        )
                }
                .contentShape(Rectangle())
                .onDrop(
                    of: [Self.dockItemType],
                    delegate: itemDropDelegate(
                        destination: .trailing,
                        isTargeted: $trailingTargeted
                    )
                )
        } else {
            ForEach(Array(currentItems.enumerated()), id: \.element.id) { index, item in
                if item.isSeparator {
                    separatorCell(item)
                } else {
                    dockItemCell(item, at: index)
                }
            }

            if !state.isQuickLaunchPresented {
                Color.clear
                    .frame(
                        width: orientation == .horizontal ? 8 : iconSize + 6,
                        height: orientation == .horizontal ? iconSize + 6 : 8
                    )
                    .padding(orientation == .horizontal ? .leading : .top, 4)
                    .contentShape(Rectangle())
                    .overlay {
                        trailingDropIndicator
                            .allowsHitTesting(false)
                    }
                    .onDrop(
                        of: [Self.dockItemType],
                        delegate: itemDropDelegate(
                            destination: .trailing,
                            isTargeted: $trailingTargeted
                        )
                    )
            }
        }
    }

    @ViewBuilder
    private func separatorCell(_ item: DockItem) -> some View {
        let separator = DockSeparatorView(
            orientation: orientation,
            iconSize: iconSize,
            color: chromeColor
        )
        .contentShape(Rectangle())
        .opacity(
            state.isQuickLaunchPresented ? 0.18 : opacity(for: item)
        )
        .allowsHitTesting(!state.isQuickLaunchPresented)
        .accessibilityHidden(state.isQuickLaunchPresented)
        .overlay {
            dockItemDropIndicator(for: item)
                .allowsHitTesting(false)
        }
        .contextMenu {
            Button("Remove Separator", role: .destructive) {
                var updated = displayedItems ?? items
                updated.removeAll { $0.id == item.id }
                commitItems(updated)
            }
        }

        separator
            .onDrag {
                dragProvider(for: item)
            }
            .onDrop(
                of: [Self.dockItemType],
                delegate: itemDropDelegate(
                    destination: .item(item.id),
                    isTargeted: dropTargetBinding(for: item.id)
                )
            )
    }

    @ViewBuilder
    private func dockItemCell(
        _ item: DockItem,
        at index: Int
    ) -> some View {
        let cell = DockItemView(
            item: item,
            iconSize: iconSize,
            scale: scale(for: index, in: currentItems),
            onActivate: { screenRect in
                onItemActivation(item, screenRect)
            },
            onRemove: { removeItem(item) },
            onFolderOptionsChanged: { options in
                onFolderOptionsChanged(item.id, options)
            },
            hasRecentFiles: hasRecentFiles,
            onClearRecentFilesRequested: onClearRecentFilesRequested,
            onOpenDocumentWithApplication: { applicationURL in
                onOpenDocumentWithApplication(item, applicationURL)
            },
            onChooseFilesForApplication: {
                onChooseFilesForApplication(item)
            },
            onApplicationHoverChanged: { hovering, screenRect in
                onApplicationHoverChanged(
                    item,
                    screenRect,
                    hovering
                )
            },
            onShowApplicationWindows: { screenRect in
                onShowApplicationWindows(item, screenRect)
            },
            onEnableWindowThumbnails:
                onEnableWindowThumbnails,
            isWindowPreviewAccessibilityTrusted:
                isWindowPreviewAccessibilityTrusted,
            isWindowPreviewScreenCaptureTrusted:
                isWindowPreviewScreenCaptureTrusted,
            hoveredItem: $hoveredItem,
            orientation: orientation,
            showRunningIndicator: state.showRunningIndicators,
            indicatorColor: chromeColor,
            isQuickLaunchSelected: state.isQuickLaunchPresented
                && selectedQuickLaunchItemID == item.id,
            quickLaunchResultPosition: quickLaunchResultPosition(
                for: item.id
            ),
            quickLaunchResultCount: quickLaunchResults.count
        )
        .frame(
            width: iconSize + 9,
            height: iconSize + 11
        )
        .opacity(opacity(for: item))
        .allowsHitTesting(
            !state.isQuickLaunchPresented
                || matchingItemIDs.contains(item.id)
        )
        .accessibilityHidden(
            state.isQuickLaunchPresented
                && !matchingItemIDs.contains(item.id)
        )
        .overlay {
            dockItemOverlay(for: item)
                .allowsHitTesting(false)
        }
        .scaleEffect(
            selectedQuickLaunchItemID == item.id
                && state.isQuickLaunchPresented
                && !reduceMotion
                ? 1.03
                : 1
        )
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.12),
            value: selectedQuickLaunchItemID
        )

        let interactiveCell = cell
            .onDrag {
                dragProvider(for: item)
            } preview: {
                Image(
                    nsImage: DockItemPresentation.resolve(item).icon
                )
                .resizable()
                .frame(width: iconSize, height: iconSize)
                .opacity(0.85)
            }
            .onDrop(
                of: [Self.dockItemType],
                delegate: itemDropDelegate(
                    destination: .item(item.id),
                    isTargeted: dropTargetBinding(for: item.id)
                )
            )

        applicationFileDropTarget(interactiveCell, for: item)
    }

    @ViewBuilder
    private func applicationFileDropTarget<Content: View>(
        _ content: Content,
        for item: DockItem
    ) -> some View {
        if canTargetApplicationFileDrop(item) {
            content.onDrop(
                of: [.fileURL],
                delegate: DockApplicationFileDropDelegate(
                    isEnabled: itemDragCoordinator.activeSession == nil
                        && !externalFileDropClaimState
                            .isOperationInProgress,
                    isRejected: applicationFileDropTargetItem == item.id
                        && applicationFileDropPresentation == .rejected,
                    onEntered: { providers in
                        beginApplicationFileDropPreflight(
                            providers,
                            onto: item
                        )
                    },
                    onExited: {
                        endApplicationFileDropPreflight(
                            itemID: item.id
                        )
                    },
                    onClaim: {
                        claimApplicationFileDrop(itemID: item.id)
                    },
                    onPerform: { providers, operationID in
                        handleApplicationFileDrop(
                            providers,
                            onto: item,
                            operationID: operationID
                        )
                    }
                )
            )
        } else {
            content
        }
    }

    struct DockSeparatorView: View {
        let orientation: Orientation
        let iconSize: Double
        let color: Color

        var body: some View {
            ZStack {
                Capsule()
                    .fill(color.opacity(0.16))
                    .frame(
                        width: orientation == .horizontal ? 1 : iconSize * 0.54,
                        height: orientation == .horizontal ? iconSize * 0.54 : 1
                    )
            }
            .frame(
                width: orientation == .horizontal ? 8 : iconSize + 4,
                height: orientation == .horizontal ? iconSize + 4 : 8
            )
        }
    }

    private func scale(for index: Int, in items: [DockItem]) -> CGFloat {
        guard !state.isQuickLaunchPresented,
              state.magnificationEnabled,
              let hoveredItem,
              let hoveredIndex = items.firstIndex(where: { $0.id == hoveredItem })
        else {
            return 1.0
        }

        let peak = CGFloat(state.magnification)
        let delta = peak - 1

        switch abs(index - hoveredIndex) {
        case 0: return peak
        case 1: return 1 + delta * 0.5
        case 2: return 1 + delta * 0.2
        default: return 1.0
        }
    }

    private func opacity(for item: DockItem) -> Double {
        if state.isQuickLaunchPresented {
            return matchingItemIDs.contains(item.id) ? 1 : 0.27
        }
        return itemDragCoordinator.isDragging(
            itemID: item.id,
            from: panel.dockID
        ) ? 0.4 : 1
    }

    @ViewBuilder
    private func dockItemOverlay(for item: DockItem) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        if applicationFileDropTargetItem == item.id,
           applicationFileDropPresentation != .pin
        {
            let isRejected = applicationFileDropPresentation == .rejected
            let isChecking = applicationFileDropPresentation == .checking
            let highlightColor: Color = isRejected
                ? .red
                : (isChecking ? .gray : .accentColor)
            let badgeSymbol = isRejected
                ? "xmark"
                : (isChecking ? "ellipsis" : "arrow.up.forward")

            shape
                .fill(highlightColor.opacity(0.18))
                .padding(1)
            shape
                .strokeBorder(highlightColor, lineWidth: 2)
                .padding(1.5)
                .shadow(
                    color: highlightColor.opacity(0.32),
                    radius: 6
                )
            Image(systemName: badgeSymbol)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 16, height: 16)
                .background(highlightColor, in: Circle())
                .overlay {
                    Circle()
                        .strokeBorder(.white.opacity(0.55), lineWidth: 0.75)
                }
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .bottomTrailing
                )
                .padding(2)
                .accessibilityHidden(true)
        } else if state.isQuickLaunchPresented,
           selectedQuickLaunchItemID == item.id
        {
            shape
                .fill(Color.accentColor.opacity(0.16))
                .padding(1)
            shape
                .strokeBorder(Color.white.opacity(0.24), lineWidth: 0.75)
                .padding(1.5)
            shape
                .strokeBorder(Color.accentColor.opacity(0.68), lineWidth: 1)
                .padding(2.5)
                .shadow(
                    color: Color.accentColor.opacity(0.18),
                    radius: 5
                )
        } else {
            dockItemDropIndicator(for: item)
        }
    }

    @ViewBuilder
    private func dockItemDropIndicator(for item: DockItem) -> some View {
        if dropTargetItem == item.id {
            if orientation == .horizontal {
                Capsule()
                    .fill(Color.accentColor)
                    .frame(
                        width: 3,
                        height: max(22, iconSize * 0.64)
                    )
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: dropsAfter(item) ? .trailing : .leading
                    )
                    .shadow(
                        color: Color.accentColor.opacity(0.35),
                        radius: 3
                    )
            } else {
                Capsule()
                    .fill(Color.accentColor)
                    .frame(
                        width: max(22, iconSize * 0.64),
                        height: 3
                    )
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: dropsAfter(item) ? .bottom : .top
                    )
                    .shadow(
                        color: Color.accentColor.opacity(0.35),
                        radius: 3
                    )
            }
        }
    }

    @ViewBuilder
    private var trailingDropIndicator: some View {
        if trailingTargeted {
            if orientation == .horizontal {
                Capsule()
                    .fill(Color.accentColor)
                    .frame(
                        width: 3,
                        height: max(22, iconSize * 0.64)
                    )
            } else {
                Capsule()
                    .fill(Color.accentColor)
                    .frame(
                        width: max(22, iconSize * 0.64),
                        height: 3
                    )
            }
        }
    }

    private func dropsAfter(_ targetItem: DockItem) -> Bool {
        guard let session = itemDragCoordinator.activeSession,
              session.sourceDockID == panel.dockID,
              let sourceIndex = currentItems.firstIndex(where: {
                  $0.id == session.itemID
              }),
              let targetIndex = currentItems.firstIndex(where: {
                  $0.id == targetItem.id
              })
        else {
            return false
        }
        return sourceIndex < targetIndex
    }

    private func quickLaunchResultPosition(
        for itemID: DockItem.ID
    ) -> Int? {
        quickLaunchResultsInDockOrder.firstIndex {
            $0.id == itemID
        }.map { $0 + 1 }
    }

    private var quickLaunchAccessibilityValue: String {
        let queryDescription = quickLaunchQuery.isEmpty
            ? "All dock items"
            : "Query \(quickLaunchQuery)"
        guard let selectedResult = quickLaunchSelection.selectedResult(
            in: quickLaunchResults
        ), let position = quickLaunchResultPosition(for: selectedResult.id)
        else {
            return "\(queryDescription). No matches."
        }
        return "\(queryDescription). \(selectedResult.displayLabel), selected, \(position) of \(quickLaunchResults.count)."
    }

    private func resetQuickLaunch() {
        quickLaunchQuery = ""
        hoveredItem = nil
        var selection = QuickLaunchSelection()
        selection.reconcile(with: QuickLaunchSearch.results(
            in: currentItems,
            matching: ""
        ))
        quickLaunchSelection = selection
    }

    private func reconcileQuickLaunchSelection() {
        guard state.isQuickLaunchPresented else { return }
        var selection = quickLaunchSelection
        selection.reconcile(with: quickLaunchResults)
        quickLaunchSelection = selection
    }

    private func updateQuickLaunchSelectionFromHover(
        _ itemID: DockItem.ID?
    ) {
        guard state.isQuickLaunchPresented,
              let itemID,
              matchingItemIDs.contains(itemID)
        else {
            return
        }
        quickLaunchSelection = QuickLaunchSelection(
            selectedItemID: itemID
        )
    }

    private func handleQuickLaunchCommand(
        _ command: QuickLaunchSearchField.Command
    ) {
        guard state.isQuickLaunchPresented else { return }

        switch command {
        case .moveLeft, .moveUp, .previous:
            moveQuickLaunchSelection(.previous)
        case .moveRight, .moveDown, .next:
            moveQuickLaunchSelection(.next)
        case .activate:
            activateQuickLaunchSelection()
        case .dismiss:
            onQuickLaunchDismiss()
        }
    }

    private func moveQuickLaunchSelection(
        _ direction: QuickLaunchNavigationDirection
    ) {
        var selection = quickLaunchSelection
        selection.move(direction, in: quickLaunchResultsInDockOrder)
        quickLaunchSelection = selection
    }

    private func activateQuickLaunchSelection() {
        guard let result = quickLaunchSelection.selectedResult(
            in: quickLaunchResults
        ) else {
            NSSound.beep()
            return
        }
        onItemActivation(
            result.item,
            .zero
        )
    }

    private var dropZoneHighlight: some View {
        RoundedRectangle(cornerRadius: surfaceCornerRadius)
            .stroke(
                showsDockWideFileDropHighlight
                    ? Color.accentColor.opacity(dropPulse ? 1.0 : 0.55)
                    : Color.clear,
                lineWidth: 2
            )
            .shadow(
                color: showsDockWideFileDropHighlight
                    ? Color.accentColor.opacity(dropPulse ? 0.35 : 0.12)
                    : Color.clear,
                radius: dropPulse ? 7 : 2
            )
            .allowsHitTesting(false)
    }

    private var showsDockWideFileDropHighlight: Bool {
        guard !externalFileDropClaimState.isOperationInProgress
        else {
            return false
        }
        if applicationFileDropTargetItem != nil {
            return applicationFileDropPresentation == .pin
        }
        return isTargeted
    }

    private var dockSurface: some View {
        let shape = RoundedRectangle(cornerRadius: surfaceCornerRadius, style: .continuous)
        return ZStack {
            glassMaterial(for: shape)
                .opacity(state.appearance == .glass ? state.surfaceOpacity : 0)

            shape
                .fill(Color(red: 0.96, green: 0.96, blue: 0.97).opacity(0.94))
                .opacity(state.appearance == .light ? state.surfaceOpacity : 0)

            shape
                .fill(Color(red: 0.075, green: 0.078, blue: 0.09).opacity(0.92))
                .opacity(state.appearance == .dark ? state.surfaceOpacity : 0)

            shape.fill(
                LinearGradient(
                    colors: [.white.opacity(0.18), .white.opacity(0.045), .black.opacity(0.035)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .opacity(state.appearance == .glass ? state.surfaceOpacity : 0)
        }
        .overlay {
            shape.strokeBorder(
                LinearGradient(
                    colors: surfaceBorderColors,
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 0.75
            )
            .opacity(state.surfaceOpacity)
        }
        .shadow(
            color: .black.opacity(
                (state.appearance == .dark ? 0.32 : 0.22) * state.shadowStrength
            ),
            radius: 16,
            x: 0,
            y: 8
        )
        .shadow(
            color: .black.opacity(0.10 * state.shadowStrength),
            radius: 2,
            x: 0,
            y: 1
        )
    }

    @ViewBuilder
    private func glassMaterial(for shape: RoundedRectangle) -> some View {
        switch state.blurStyle {
        case .light:
            shape.fill(.ultraThinMaterial)
        case .regular:
            shape.fill(.regularMaterial)
        case .strong:
            shape.fill(.thickMaterial)
        }
    }

    private var surfaceBorderColors: [Color] {
        switch state.appearance {
        case .glass:
            return [.white.opacity(0.30), .white.opacity(0.10), .black.opacity(0.08)]
        case .light:
            return [.white.opacity(0.90), .white.opacity(0.42), .black.opacity(0.16)]
        case .dark:
            return [.white.opacity(0.25), .white.opacity(0.10), .black.opacity(0.28)]
        }
    }

    private func updateDropPulse(_ targeted: Bool) {
        if targeted {
            if reduceMotion {
                dropPulse = true
            } else {
                dropPulse = false
                withAnimation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true)) {
                    dropPulse = true
                }
            }
        } else {
            withAnimation(.easeOut(duration: 0.12)) {
                dropPulse = false
            }
        }
    }

    private func handleFileDrop(_ providers: [NSItemProvider]) -> Bool {
        if externalFileDropClaimState.shouldSuppressParentPinDrop {
            return true
        }
        guard !externalFileDropClaimState.isOperationInProgress else {
            NSSound.beep()
            return false
        }

        let relevant = providers.filter {
            $0.hasItemConformingToTypeIdentifier(
                UTType.fileURL.identifier
            )
        }
        guard !relevant.isEmpty else { return false }

        let operationID = beginExternalFileDropOperation()
        loadFileDropProviders(relevant) { result in
            guard externalFileDropClaimState.activeOperationID
                    == operationID
            else {
                return
            }
            if result.failedInputIndices.isEmpty {
                addDroppedItems(result.urls)
            } else {
                NSSound.beep()
            }
            finishExternalFileDropOperation(operationID)
        }
        return true
    }

    private func handleApplicationFileDrop(
        _ providers: [NSItemProvider],
        onto item: DockItem,
        operationID: UUID
    ) -> Bool {
        let relevant = providers.filter {
            $0.hasItemConformingToTypeIdentifier(
                UTType.fileURL.identifier
            )
        }
        guard !relevant.isEmpty else {
            NSSound.beep()
            finishExternalFileDropOperation(operationID)
            return true
        }

        guard applicationFileDropPresentation != .rejected else {
            NSSound.beep()
            finishExternalFileDropOperation(operationID)
            return true
        }

        if let applicationFileDropURLs {
            performApplicationFileDrop(
                applicationFileDropURLs,
                onto: item
            )
            finishExternalFileDropOperation(operationID)
            return true
        }

        loadFileDropProviders(relevant) { result in
            guard externalFileDropClaimState.activeOperationID
                    == operationID
            else {
                return
            }
            if result.failedInputIndices.isEmpty {
                performApplicationFileDrop(
                    result.urls,
                    onto: item
                )
            } else {
                NSSound.beep()
            }
            finishExternalFileDropOperation(operationID)
        }
        return true
    }

    private func performApplicationFileDrop(
        _ urls: [URL],
        onto item: DockItem
    ) {
        if urls.contains(where: shouldPinAsDockItem) {
            addDroppedItems(urls)
            return
        }

        guard onCanOpenFilesWithApplication(item, urls) else {
            NSSound.beep()
            return
        }
        _ = onOpenFilesWithApplication(item, urls)
    }

    private func shouldPinAsDockItem(_ url: URL) -> Bool {
        url.pathExtension.caseInsensitiveCompare("app")
            == .orderedSame
            || DockItem.pinnedItem(at: url)?.kind == .application
    }

    private func loadFileDropProviders(
        _ providers: [NSItemProvider],
        completion: @escaping @MainActor (
            OrderedFileDropLoadResult
        ) -> Void
    ) {
        let accumulator = OrderedFileDropAccumulator(
            count: providers.count
        )
        for (index, provider) in providers.enumerated() {
            provider.loadDataRepresentation(
                forTypeIdentifier: UTType.fileURL.identifier
            ) { data, _ in
                let url = data.flatMap {
                    URL(dataRepresentation: $0, relativeTo: nil)
                }
                guard let result = accumulator.store(
                    url,
                    at: index
                ) else {
                    return
                }
                DispatchQueue.main.async {
                    completion(result)
                }
            }
        }
    }

    private func addDroppedItems(_ urls: [URL]) {
        let plan = DockItemPlanner.planAdding(
            urls: urls,
            to: displayedItems ?? items
        )
        guard plan.addedCount > 0 else { return }
        commitItems(plan.items)
    }

    private func canTargetApplicationFileDrop(
        _ item: DockItem
    ) -> Bool {
        !state.isQuickLaunchPresented
            && item.kind == .application
            && item.fileURL != nil
    }

    private func beginApplicationFileDropPreflight(
        _ providers: [NSItemProvider],
        onto item: DockItem
    ) {
        onDismissWindowPreview()
        guard !externalFileDropClaimState.isOperationInProgress
        else {
            return
        }

        let preflightID = UUID()
        applicationFileDropTargetItem = item.id
        applicationFileDropPresentation = .checking
        applicationFileDropURLs = nil
        applicationFileDropPreflightID = preflightID
        externalFileDropClaimState.applicationTargetEntered(
            itemID: item.id
        )
        TooltipManager.shared.hide()
        beginExternalFileDropInteraction()

        let relevant = providers.filter {
            $0.hasItemConformingToTypeIdentifier(
                UTType.fileURL.identifier
            )
        }
        guard !relevant.isEmpty else {
            setApplicationFileDropPresentation(
                .rejected,
                for: item,
                itemCount: providers.count
            )
            return
        }

        loadFileDropProviders(relevant) { result in
            guard applicationFileDropPreflightID == preflightID,
                  applicationFileDropTargetItem == item.id,
                  !externalFileDropClaimState.isOperationInProgress
            else {
                return
            }

            guard result.failedInputIndices.isEmpty,
                  !result.urls.isEmpty
            else {
                applicationFileDropURLs = nil
                setApplicationFileDropPresentation(
                    .rejected,
                    for: item,
                    itemCount: relevant.count
                )
                return
            }

            applicationFileDropURLs = result.urls
            if result.urls.contains(where: shouldPinAsDockItem) {
                let plan = DockItemPlanner.planAdding(
                    urls: result.urls,
                    to: displayedItems ?? items
                )
                setApplicationFileDropPresentation(
                    plan.addedCount > 0 ? .pin : .rejected,
                    for: item,
                    itemCount: result.urls.count
                )
            } else {
                setApplicationFileDropPresentation(
                    onCanOpenFilesWithApplication(item, result.urls)
                        ? .open
                        : .rejected,
                    for: item,
                    itemCount: result.urls.count
                )
            }
        }
    }

    private func setApplicationFileDropPresentation(
        _ presentation: ApplicationFileDropPresentation,
        for item: DockItem,
        itemCount: Int
    ) {
        applicationFileDropPresentation = presentation
        guard presentation != .checking else { return }

        let applicationName = item.label
            ?? item.fileURL.map {
                FileManager.default.displayName(atPath: $0.path)
            }
            ?? "this application"
        let count = max(1, itemCount)
        let noun = count == 1 ? "item" : "items"
        let announcement: String
        switch presentation {
        case .checking:
            return
        case .open:
            announcement =
                "\(applicationName) can open \(count) \(noun)."
        case .pin:
            announcement =
                "Add \(count) \(noun) to \(state.name)."
        case .rejected:
            announcement =
                "Drop unavailable for \(applicationName)."
        }

        NSAccessibility.post(
            element: panel,
            notification: .announcementRequested,
            userInfo: [
                .announcement: announcement,
                .priority:
                    NSAccessibilityPriorityLevel.medium.rawValue,
            ]
        )
    }

    private func endApplicationFileDropPreflight(
        itemID: DockItem.ID
    ) {
        externalFileDropClaimState.applicationTargetExited(
            itemID: itemID
        )
        guard applicationFileDropTargetItem == itemID,
              !externalFileDropClaimState.isOperationInProgress
        else {
            return
        }

        clearApplicationFileDropPresentation()
        endExternalFileDropInteractionIfPossible()
    }

    private func clearApplicationFileDropPresentation() {
        applicationFileDropTargetItem = nil
        applicationFileDropPresentation = nil
        applicationFileDropURLs = nil
        applicationFileDropPreflightID = nil
    }

    private func claimApplicationFileDrop(
        itemID: DockItem.ID
    ) -> UUID {
        applicationFileDropTargetItem = itemID
        applicationFileDropPreflightID = nil
        return beginExternalFileDropOperation(
            claimingApplicationItemID: itemID
        )
    }

    private func updateExternalFileDropTargeting(_ targeted: Bool) {
        if targeted {
            onDismissWindowPreview()
            beginExternalFileDropInteraction()
        } else {
            endExternalFileDropInteractionIfPossible()
        }
    }

    private func beginExternalFileDropOperation(
        claimingApplicationItemID: DockItem.ID? = nil
    ) -> UUID {
        let operationID = UUID()
        if let claimingApplicationItemID {
            externalFileDropClaimState.claimApplicationDrop(
                itemID: claimingApplicationItemID,
                operationID: operationID
            )
            externalFileDropClaimState.applicationTargetExited(
                itemID: claimingApplicationItemID
            )
            DispatchQueue.main.async {
                _ = externalFileDropClaimState
                    .releaseDispatchSuppression(for: operationID)
                endExternalFileDropInteractionIfPossible()
            }
        } else {
            externalFileDropClaimState.beginOperation(
                operationID: operationID
            )
        }
        beginExternalFileDropInteraction()
        externalFileDropExpiryWorkItem?.cancel()
        let work = DispatchWorkItem {
            guard externalFileDropClaimState.activeOperationID
                    == operationID
            else {
                return
            }
            NSSound.beep()
            finishExternalFileDropOperation(operationID)
        }
        externalFileDropExpiryWorkItem = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + 30,
            execute: work
        )
        return operationID
    }

    private func finishExternalFileDropOperation(
        _ operationID: UUID
    ) {
        guard externalFileDropClaimState.finishOperation(
            operationID
        ) else {
            return
        }
        externalFileDropExpiryWorkItem?.cancel()
        externalFileDropExpiryWorkItem = nil
        clearApplicationFileDropPresentation()
        endExternalFileDropInteractionIfPossible()
    }

    private func beginExternalFileDropInteraction() {
        guard externalFileDropInteractionToken == nil else { return }
        externalFileDropInteractionToken =
            panel.beginTransientInteraction()
    }

    private func endExternalFileDropInteractionIfPossible() {
        guard !isTargeted,
              applicationFileDropTargetItem == nil,
              !externalFileDropClaimState.isOperationInProgress,
              !externalFileDropClaimState
                  .shouldSuppressParentPinDrop,
              let token = externalFileDropInteractionToken
        else {
            return
        }
        externalFileDropInteractionToken = nil
        panel.endTransientInteraction(token)
    }

    private func tearDownExternalFileDropInteraction() {
        externalFileDropExpiryWorkItem?.cancel()
        externalFileDropExpiryWorkItem = nil
        externalFileDropClaimState.reset()
        clearApplicationFileDropPresentation()
        guard let token = externalFileDropInteractionToken else {
            return
        }
        externalFileDropInteractionToken = nil
        panel.endTransientInteraction(token)
    }

    private func dragProvider(for item: DockItem) -> NSItemProvider {
        guard !state.isQuickLaunchPresented else {
            return NSItemProvider()
        }
        onDismissWindowPreview()
        TooltipManager.shared.hide()
        return itemDragCoordinator.beginDrag(
            profileID: profileID,
            sourceDockID: panel.dockID,
            itemID: item.id
        )
    }

    private func itemDropDelegate(
        destination: DockItemTransferDestination,
        isTargeted: Binding<Bool>
    ) -> DockItemDropDelegate {
        DockItemDropDelegate(
            profileID: profileID,
            targetDockID: panel.dockID,
            destination: destination,
            coordinator: itemDragCoordinator,
            isEnabled: !state.isQuickLaunchPresented,
            isTargeted: isTargeted,
            onTransfer: onItemTransfer
        )
    }

    private func dropTargetBinding(
        for itemID: DockItem.ID
    ) -> Binding<Bool> {
        Binding(
            get: { dropTargetItem == itemID },
            set: { targeted in
                if targeted {
                    dropTargetItem = itemID
                } else if dropTargetItem == itemID {
                    dropTargetItem = nil
                }
            }
        )
    }

    private func removeItem(_ item: DockItem) {
        var updatedItems = displayedItems ?? items
        updatedItems.removeAll(where: { $0.id == item.id })
        withAnimation { displayedItems = updatedItems }
        items = updatedItems
    }

    private func commitItems(_ updatedItems: [DockItem]) {
        displayedItems = updatedItems
        items = updatedItems
    }

    private func canAddSmartStack(_ source: SmartStackSource) -> Bool {
        DockItemPlanner.planAdding(
            smartStack: source,
            to: currentItems
        ).addedCount > 0
    }
}

@MainActor
private struct DockItemDropDelegate: DropDelegate {
    let profileID: UUID
    let targetDockID: UUID
    let destination: DockItemTransferDestination
    let coordinator: DockItemDragCoordinator
    let isEnabled: Bool
    @Binding var isTargeted: Bool
    let onTransfer: @MainActor (
        DockItemDragSession,
        DockItemTransferDestination,
        DockItemTransferOperation
    ) -> Bool

    func validateDrop(info: DropInfo) -> Bool {
        canAccept(info)
    }

    func dropEntered(info: DropInfo) {
        isTargeted = canAccept(info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard canAccept(info),
              let session = coordinator.activeSession
        else {
            return DropProposal(operation: .forbidden)
        }
        return DropProposal(
            operation: transferOperation(for: session) == .copy
                ? .copy
                : .move
        )
    }

    func dropExited(info _: DropInfo) {
        isTargeted = false
    }

    func performDrop(info: DropInfo) -> Bool {
        guard canAccept(info),
              let expectedSession = coordinator.activeSession,
              let provider = info.itemProviders(
                  for: [UTType.freeDockItem]
              ).first
        else {
            isTargeted = false
            return false
        }

        let operation = transferOperation(for: expectedSession)
        isTargeted = false
        coordinator.loadSession(from: provider) { payload in
            guard let payload,
                  payload == expectedSession,
                  coordinator.activeSession == expectedSession
            else {
                coordinator.cancel()
                return
            }
            _ = onTransfer(payload, destination, operation)
        }
        return true
    }

    private func canAccept(_ info: DropInfo) -> Bool {
        isEnabled
            && info.hasItemsConforming(to: [UTType.freeDockItem])
            && coordinator.activeSession?.profileID == profileID
    }

    private func transferOperation(
        for session: DockItemDragSession
    ) -> DockItemTransferOperation {
        guard session.sourceDockID != targetDockID else {
            return .move
        }
        return NSEvent.modifierFlags.contains(.option) ? .copy : .move
    }
}

private struct DockApplicationFileDropDelegate: DropDelegate {
    let isEnabled: Bool
    let isRejected: Bool
    let onEntered: @MainActor ([NSItemProvider]) -> Void
    let onExited: @MainActor () -> Void
    let onClaim: @MainActor () -> UUID
    let onPerform: @MainActor ([NSItemProvider], UUID) -> Bool

    func validateDrop(info: DropInfo) -> Bool {
        canAccept(info)
    }

    func dropEntered(info: DropInfo) {
        guard canAccept(info) else { return }
        onEntered(info.itemProviders(for: [.fileURL]))
    }

    func dropExited(info _: DropInfo) {
        onExited()
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard canAccept(info), !isRejected else {
            return DropProposal(operation: .forbidden)
        }
        return DropProposal(operation: .copy)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard canAccept(info) else {
            onExited()
            return false
        }

        let providers = info.itemProviders(for: [.fileURL])
        guard !providers.isEmpty else {
            onExited()
            return false
        }

        let operationID = onClaim()
        return onPerform(providers, operationID)
    }

    private func canAccept(_ info: DropInfo) -> Bool {
        isEnabled
            && info.hasItemsConforming(to: [.fileURL])
    }
}

private enum ApplicationFileDropPresentation: Equatable {
    case checking
    case open
    case pin
    case rejected
}

private struct OrderedFileDropLoadResult: Sendable {
    let urls: [URL]
    let failedInputIndices: [Int]
}

private final class OrderedFileDropAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var results: [URL?]
    private var completedIndices = Set<Int>()
    private var remaining: Int

    init(count: Int) {
        results = Array(repeating: nil, count: count)
        remaining = count
    }

    func store(
        _ url: URL?,
        at index: Int
    ) -> OrderedFileDropLoadResult? {
        lock.lock()
        defer { lock.unlock() }

        guard remaining > 0,
              results.indices.contains(index),
              completedIndices.insert(index).inserted
        else {
            return nil
        }
        results[index] = url
        remaining -= 1
        guard remaining == 0 else { return nil }

        return OrderedFileDropLoadResult(
            urls: results.compactMap { $0 },
            failedInputIndices: results.indices.filter {
                results[$0] == nil
            }
        )
    }
}
