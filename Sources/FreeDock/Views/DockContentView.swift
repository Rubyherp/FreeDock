import SwiftUI
import UniformTypeIdentifiers

struct DockContentView: View {
    private static let dockItemType = UTType(exportedAs: "com.freedock.dock-item")

    let panel: DockPanel
    @Binding var items: [DockItem]
    let orientation: Orientation
    @ObservedObject var state: DockState
    let onItemsChanged: @MainActor ([DockItem]) -> Void
    let onAppLaunch: @MainActor (DockItem) -> Void

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

    private var currentItems: [DockItem] {
        displayedItems ?? items
    }

    private var surfaceCornerRadius: CGFloat {
        CGFloat(state.cornerRadius)
    }

    private var magnificationHeadroom: CGFloat {
        guard state.magnificationEnabled else { return 10 }
        return max(10, iconSize * (state.magnification - 1 + 0.04))
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
                handleFileDrop(providers)
            }
            .onChange(of: isTargeted) { targeted in updateDropPulse(targeted) }
            .onAppear { displayedItems = items }
            .onChange(of: items) { displayedItems = $0 }
            .contextMenu {
                Button("Add Separator") {
                    var updated = displayedItems ?? items
                    updated.append(.separator())
                    commitItems(updated)
                }
            }
    }

    @ViewBuilder
    private var dockLayout: some View {
        if orientation == .horizontal {
            HStack(spacing: state.itemSpacing) { content }
                .padding(.horizontal, 8)
                .padding(.vertical, 9)
                .background(dockSurface)
                .overlay(dropZoneHighlight)
                .overlay(alignment: .trailing) {
                DockResizeHandleRepresentable(
                    panel: panel,
                    orientation: orientation
                )
                    .frame(width: 18)
                }
                .padding(.top, magnificationHeadroom)
        } else {
            VStack(spacing: state.itemSpacing) { content }
                .padding(.horizontal, 9)
                .padding(.vertical, 8)
                .background(dockSurface)
                .overlay(dropZoneHighlight)
                .overlay(alignment: .bottom) {
                DockResizeHandleRepresentable(
                    panel: panel,
                    orientation: orientation
                )
                    .frame(height: 18)
                }
                .padding(.horizontal, magnificationHeadroom * 0.52)
        }
    }

    @ViewBuilder
    private var content: some View {
        if currentItems.isEmpty {
            Label("Drop apps", systemImage: "plus.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(chromeColor.opacity(0.65))
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
        } else {
            ForEach(Array(currentItems.enumerated()), id: \.element.id) { index, item in
                if item.isSeparator {
                    DockSeparatorView(
                        orientation: orientation,
                        iconSize: iconSize,
                        color: chromeColor
                    )
                        .contentShape(Rectangle())
                        .contextMenu {
                            Button("Remove Separator", role: .destructive) {
                                var updated = displayedItems ?? items
                                updated.removeAll { $0.id == item.id }
                                commitItems(updated)
                            }
                        }
                        .onDrag {
                            dragProvider(for: item)
                        }
                        .onDrop(of: [Self.dockItemType], isTargeted: nil) { providers in
                            handleReorder(providers, targetItem: item)
                        }
                } else {
                    DockItemView(
                        item: item,
                        iconSize: iconSize,
                        scale: scale(for: index, in: currentItems),
                        onLaunch: { onAppLaunch(item) },
                        onRemove: { removeItem(item) },
                        hoveredItem: $hoveredItem,
                        orientation: orientation,
                        showRunningIndicator: state.showRunningIndicators,
                        indicatorColor: chromeColor
                    )
                    .frame(
                        width: iconSize + 9,
                        height: iconSize + 11
                    )
                    .opacity(draggedItem?.id == item.id ? 0.4 : 1.0)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.accentColor.opacity(dropTargetItem == item.id ? 0.9 : 0), lineWidth: 2)
                            .padding(2)
                    )
                    .onDrag {
                        dragProvider(for: item)
                    } preview: {
                        Image(nsImage: AppInfo.resolve(from: item.appPath).icon)
                            .resizable()
                            .frame(width: iconSize, height: iconSize)
                            .opacity(0.85)
                    }
                    .onDrop(of: [Self.dockItemType], isTargeted: Binding(
                        get: { dropTargetItem == item.id },
                        set: { dropTargetItem = $0 ? item.id : nil }
                    )) { providers in
                        handleReorder(providers, targetItem: item)
                    }
                }
            }

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
        guard state.magnificationEnabled,
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
            dropPulse = false
            withAnimation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true)) {
                dropPulse = true
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
        for provider in relevant {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil), url.path.hasSuffix(".app"), FileManager.default.fileExists(atPath: url.path) else { return }
                let info = AppInfo.resolve(from: url.path)
                let newItem = DockItem(appPath: url.path, label: info.displayName)
                DispatchQueue.main.async {
                    var updatedItems = displayedItems ?? items
                    updatedItems.append(newItem)
                    commitItems(updatedItems)
                }
            }
        }
        return true
    }

    private func dragProvider(for item: DockItem) -> NSItemProvider {
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
        onItemsChanged(updatedItems)
    }

    private func commitItems(_ updatedItems: [DockItem]) {
        displayedItems = updatedItems
        items = updatedItems
        onItemsChanged(updatedItems)
    }
}
