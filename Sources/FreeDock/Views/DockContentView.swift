import SwiftUI
import UniformTypeIdentifiers

struct DockContentView: View {
    let panel: DockPanel
    @Binding var items: [DockItem]
    let orientation: Orientation
    let iconSize: Double
    let onItemsChanged: @MainActor ([DockItem]) -> Void
    let onAppLaunch: @MainActor (DockItem) -> Void

    @State private var isTargeted = false
    @State private var dropPulse = false
    @State private var draggedItem: DockItem?
    @State private var displayedItems: [DockItem]?
    @State private var hoveredItem: UUID?
    @State private var dropTargetItem: UUID?

    private var currentItems: [DockItem] {
        displayedItems ?? items
    }

    var body: some View {
        if orientation == .horizontal {
            HStack(spacing: 0) {
                DockDragHandleRepresentable(
                    panel: panel,
                    orientation: orientation
                )
                .frame(width: 32)
                // .padding(.leading, 8)
                HStack(spacing: 0) { content } // changed to 0
                    .padding(8)
            }
            .contentShape(Rectangle())
            .onHover { hovering in
                if !hovering {
                    hoveredItem = nil
                }
            }
            .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial).shadow(color: .black.opacity(0.12), radius: 4, x: 0, y: 2))
            .overlay(dropZoneHighlight)
            .onDrop(of: [.fileURL, .plainText], isTargeted: $isTargeted) { providers in
                if providers.first?.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) == true {
                    return handleFileDrop(providers)
                }
                return false
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
        } else {
            VStack(spacing: 0) {
                DockDragHandleRepresentable(
                    panel: panel,
                    orientation: orientation
                )
                .frame(height: 32)
                .padding(.top, 8)
                VStack(spacing: 0) { content } // changed to 0
                    .padding(8)
            }
            .contentShape(Rectangle())
            .onHover { hovering in
                if !hovering {
                    hoveredItem = nil
                }
            }
            .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial).shadow(color: .black.opacity(0.12), radius: 4, x: 0, y: 2))
            .overlay(dropZoneHighlight)
            .onDrop(of: [.fileURL, .plainText], isTargeted: $isTargeted) { providers in
                if providers.first?.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) == true {
                    return handleFileDrop(providers)
                }
                return false
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
    }

    @ViewBuilder
    private var content: some View {
        if currentItems.isEmpty {
            Text("Drag apps here")
                .foregroundColor(.secondary)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
        } else {
            ForEach(Array(currentItems.enumerated()), id: \.element.id) { index, item in
                if item.isSeparator {
                    DockSeparatorView(orientation: orientation)
                        .frame(
                            width: orientation == .horizontal ? 16 : iconSize + 20,
                            height: orientation == .horizontal ? iconSize + 20 : 16
                        )
                        .onDrop(of: [.plainText], isTargeted: nil) { providers in
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
                        orientation: orientation
                    )
                    .frame(
                        width: iconSize + 20,
                        height: iconSize + 20
                    )
                    .opacity(draggedItem?.id == item.id ? 0.4 : 1.0)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.accentColor.opacity(dropTargetItem == item.id ? 0.8 : 0), lineWidth: 2)
                    )
                    .onDrag {
                        draggedItem = item
                        return NSItemProvider(object: item.id.uuidString as NSString)
                    } preview: {
                        Image(nsImage: AppInfo.resolve(from: item.appPath).icon)
                            .resizable()
                            .frame(width: iconSize, height: iconSize)
                            .opacity(0.85)
                    }
                    .onDrop(of: [.plainText], isTargeted: Binding(
                        get: { dropTargetItem == item.id },
                        set: { dropTargetItem = $0 ? item.id : nil }
                    )) { providers in
                        handleReorder(providers, targetItem: item)
                    }
                }
            }
        }
    }

    struct DockSeparatorView: View {
        let orientation: Orientation
        var body: some View {
            Rectangle()
                .fill(Color.white.opacity(0.15))
                .frame(
                    width: orientation == .horizontal ? 1 : 28,
                    height: orientation == .horizontal ? 28 : 1
                )
        }
    }

    private func scale(for index: Int, in items: [DockItem]) -> CGFloat {
        guard let hoveredItem,
              let hoveredIndex = items.firstIndex(where: { $0.id == hoveredItem })
        else {
            return 1.0
        }

        switch abs(index - hoveredIndex) {
        case 0: return 1.40
        case 1: return 1.20
        case 2: return 1.05
        default: return 1.0
        }
    }

    private var dropZoneHighlight: some View {
        RoundedRectangle(cornerRadius: 14)
            .stroke(isTargeted ? Color.accentColor.opacity(dropPulse ? 1.0 : 0.55) : Color.clear, lineWidth: 3)
            .shadow(color: isTargeted ? Color.accentColor.opacity(dropPulse ? 0.35 : 0.12) : Color.clear, radius: dropPulse ? 7 : 2)
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

struct DockGripView: View {
    let orientation: Orientation
    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color(nsColor: .separatorColor).opacity(0.3))
            .frame(
                width: orientation == .horizontal ? 3 : 36,
                height: orientation == .horizontal ? 36 : 3
            )
    }
}
