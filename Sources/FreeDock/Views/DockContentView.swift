import SwiftUI
import UniformTypeIdentifiers

struct DockContentView: View {
    private static let dockItemType = UTType(exportedAs: "com.freedock.dock-item")

    let panel: DockPanel
    @Binding var items: [DockItem]
    let orientation: Orientation
    @ObservedObject var state: DockState
    let onItemActivation: @MainActor (DockItem, NSRect) -> Void
    let onQuickLaunchDismiss: @MainActor () -> Void
    let onAddItemsRequested: @MainActor () -> Void
    let onAddSmartStackRequested: @MainActor (SmartStackSource) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var iconSize: Double {
        state.iconSize
    }

    @State private var isTargeted = false
    @State private var dropPulse = false
    @State private var draggedItem: DockItem?
    @State private var displayedItems: [DockItem]?
    @State private var hoveredItem: UUID?
    @State private var dropTargetItem: UUID?
    @State private var trailingTargeted = false
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
            .onChange(of: isTargeted) { targeted in updateDropPulse(targeted) }
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
            .onChange(of: state.quickLaunchFocusGeneration) { _ in
                resetQuickLaunch()
            }
            .onChange(of: quickLaunchQuery) { _ in
                reconcileQuickLaunchSelection()
            }
            .onChange(of: hoveredItem) { itemID in
                updateQuickLaunchSelectionFromHover(itemID)
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
            HStack(spacing: state.itemSpacing) { content }
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
            VStack(spacing: state.itemSpacing) { content }
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
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.accentColor.opacity(trailingTargeted ? 0.5 : 0), lineWidth: 1.5)
                    )
                    .onDrop(of: [Self.dockItemType], isTargeted: $trailingTargeted) { _ in
                        var updatedItems = displayedItems ?? items
                        guard let dragged = draggedItem,
                              let fromIdx = updatedItems.firstIndex(where: { $0.id == dragged.id })
                        else { return false }
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            updatedItems.move(
                                fromOffsets: IndexSet(integer: fromIdx),
                                toOffset: updatedItems.endIndex
                            )
                        }
                        draggedItem = nil
                        commitItems(updatedItems)
                        return true
                    }
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
        .opacity(state.isQuickLaunchPresented ? 0.18 : 1)
        .allowsHitTesting(!state.isQuickLaunchPresented)
        .accessibilityHidden(state.isQuickLaunchPresented)
        .contextMenu {
            Button("Remove Separator", role: .destructive) {
                var updated = displayedItems ?? items
                updated.removeAll { $0.id == item.id }
                commitItems(updated)
            }
        }

        if state.isQuickLaunchPresented {
            separator
        } else {
            separator
                .onDrag {
                    dragProvider(for: item)
                }
                .onDrop(
                    of: [Self.dockItemType],
                    isTargeted: nil
                ) { providers in
                    handleReorder(providers, targetItem: item)
                }
        }
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
        .overlay { dockItemOverlay(for: item) }
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

        if state.isQuickLaunchPresented {
            cell
        } else {
            cell
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
                    isTargeted: Binding(
                        get: { dropTargetItem == item.id },
                        set: {
                            dropTargetItem = $0 ? item.id : nil
                        }
                    )
                ) { providers in
                    handleReorder(providers, targetItem: item)
                }
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
        return draggedItem?.id == item.id ? 0.4 : 1
    }

    @ViewBuilder
    private func dockItemOverlay(for item: DockItem) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        if state.isQuickLaunchPresented,
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
            shape
                .stroke(
                    Color.accentColor.opacity(
                        dropTargetItem == item.id ? 0.9 : 0
                    ),
                    lineWidth: 2
                )
                .padding(2)
        }
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
            .stroke(isTargeted ? Color.accentColor.opacity(dropPulse ? 1.0 : 0.55) : Color.clear, lineWidth: 2)
            .shadow(color: isTargeted ? Color.accentColor.opacity(dropPulse ? 0.35 : 0.12) : Color.clear, radius: dropPulse ? 7 : 2)
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
        let relevant = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !relevant.isEmpty else { return false }

        let accumulator = OrderedFileDropAccumulator(count: relevant.count)
        for (index, provider) in relevant.enumerated() {
            provider.loadDataRepresentation(
                forTypeIdentifier: UTType.fileURL.identifier
            ) { data, _ in
                let url = data.flatMap {
                    URL(dataRepresentation: $0, relativeTo: nil)
                }
                guard let completedURLs = accumulator.store(
                    url,
                    at: index
                ) else {
                    return
                }

                DispatchQueue.main.async {
                    let plan = DockItemPlanner.planAdding(
                        urls: completedURLs,
                        to: displayedItems ?? items
                    )
                    guard plan.addedCount > 0 else { return }
                    commitItems(plan.items)
                }
            }
        }
        return true
    }

    private func dragProvider(for item: DockItem) -> NSItemProvider {
        guard !state.isQuickLaunchPresented else {
            return NSItemProvider()
        }
        draggedItem = item
        let provider = NSItemProvider()
        provider.registerDataRepresentation(
            forTypeIdentifier: Self.dockItemType.identifier,
            visibility: .ownProcess
        ) { completion in
            completion(item.id.uuidString.data(using: .utf8), nil)
            return nil
        }
        return provider
    }

    private func handleReorder(_: [NSItemProvider], targetItem: DockItem) -> Bool {
        guard !state.isQuickLaunchPresented else { return false }
        var updatedItems = displayedItems ?? items
        guard
            let dragged = draggedItem,
            let fromIdx = updatedItems.firstIndex(where: { $0.id == dragged.id }),
            let toIdx = updatedItems.firstIndex(where: { $0.id == targetItem.id }),
            fromIdx != toIdx
        else { return false }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            updatedItems.move(fromOffsets: IndexSet(integer: fromIdx), toOffset: toIdx > fromIdx ? toIdx + 1 : toIdx)
        }
        draggedItem = nil
        commitItems(updatedItems)
        return true
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

private final class OrderedFileDropAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var results: [URL?]
    private var remaining: Int

    init(count: Int) {
        results = Array(repeating: nil, count: count)
        remaining = count
    }

    func store(_ url: URL?, at index: Int) -> [URL]? {
        lock.lock()
        defer { lock.unlock() }

        guard remaining > 0, results.indices.contains(index) else {
            return nil
        }
        results[index] = url
        remaining -= 1
        return remaining == 0 ? results.compactMap { $0 } : nil
    }
}
