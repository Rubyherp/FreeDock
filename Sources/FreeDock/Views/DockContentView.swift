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

    // private var startPadding: CGFloat {
    //     orientation == .horizontal ? 24 : 0
    // }
    //
    // private var topPadding: CGFloat {
    //     orientation == .vertical ? 24 : 0
    // }

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
        .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial).shadow(color: .black.opacity(0.12), radius: 4, x: 0, y: 2))
        .overlay(dropZoneHighlight)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in handleFileDrop(providers) }
        .onChange(of: isTargeted) { targeted in updateDropPulse(targeted) }
        .onAppear { displayedItems = items }
        .onChange(of: items) { displayedItems = $0 }
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
        .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial).shadow(color: .black.opacity(0.12), radius: 4, x: 0, y: 2))
        .overlay(dropZoneHighlight)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in handleFileDrop(providers) }
        .onChange(of: isTargeted) { targeted in updateDropPulse(targeted) }
        .onAppear { displayedItems = items }
        .onChange(of: items) { displayedItems = $0 }
    }
}

    // var body: some View {
    //
    //     Group {
    //         if orientation == .horizontal {
    //             HStack(spacing: 6) {
    //                 DockGripView(orientation: orientation)
    //                 content
    //             }
    //         } else {
    //             VStack(spacing: 6) {
    //                 DockGripView(orientation: orientation)
    //                 content
    //             }
    //         }
    //     }
    //     .padding(8)
    //     .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial).shadow(color: .black.opacity(0.12), radius: 4, x: 0, y: 2))
    //     .overlay(RoundedRectangle(cornerRadius: 14).stroke(isTargeted ? Color.accentColor : Color.clear, lineWidth: 2))
    //     .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in handleFileDrop(providers) }
    //     // Group {
    //     //     if orientation == .horizontal { HStack(spacing: 6) { content } }
    //     //     else { VStack(spacing: 6) { content } }
    //     // }
    //     // .padding(.leading, startPadding)
    //     // .padding(.top, topPadding)
    // }

    @ViewBuilder
    private var content: some View {
        let currentItems = displayedItems ?? items
        if currentItems.isEmpty {
            Text("Drag apps here")
                .foregroundColor(.secondary)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
        } else {
            ForEach(currentItems) { item in
                DockItemView(item: item, iconSize: iconSize, onLaunch: { onAppLaunch(item) }, onRemove: { removeItem(item) })
                    .onDrag { draggedItem = item; return NSItemProvider(object: item.id.uuidString as NSString) }
                    .onDrop(of: [.text], isTargeted: nil) { providers, _ in handleReorder(providers, targetItem: item) }
            }
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

    private func handleReorder(_ providers: [NSItemProvider], targetItem: DockItem) -> Bool {
        var updatedItems = displayedItems ?? items
        guard let dragged = draggedItem, let fromIdx = updatedItems.firstIndex(where: { $0.id == dragged.id }), let toIdx = updatedItems.firstIndex(where: { $0.id == targetItem.id }), fromIdx != toIdx else { return false }
        withAnimation { updatedItems.move(fromOffsets: IndexSet(integer: fromIdx), toOffset: toIdx > fromIdx ? toIdx + 1 : toIdx) }
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
