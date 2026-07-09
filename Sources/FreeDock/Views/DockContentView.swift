import SwiftUI
import UniformTypeIdentifiers

struct DockContentView: View {
    @Binding var items: [DockItem]
    let orientation: Orientation
    let iconSize: Double
    let onItemsChanged: @MainActor ([DockItem]) -> Void
    let onAppLaunch: @MainActor (DockItem) -> Void

    @State private var isTargeted = false
    @State private var draggedItem: DockItem?

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
            DockGripView(orientation: orientation)
                .padding(.leading, 8)
            HStack(spacing: 6) { content }
                .padding(8)
        }
        .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial).shadow(color: .black.opacity(0.12), radius: 4, x: 0, y: 2))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(isTargeted ? Color.accentColor : Color.clear, lineWidth: 2))
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in handleFileDrop(providers) }
    } else {
        VStack(spacing: 0) {
            DockGripView(orientation: orientation)
                .padding(.top, 8)
            VStack(spacing: 6) { content }
                .padding(8)
        }
        .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial).shadow(color: .black.opacity(0.12), radius: 4, x: 0, y: 2))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(isTargeted ? Color.accentColor : Color.clear, lineWidth: 2))
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in handleFileDrop(providers) }
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
        if items.isEmpty {
            Text("Drag apps here")
                .foregroundColor(.secondary)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
        } else {
            ForEach(items) { item in
                DockItemView(item: item, iconSize: iconSize, onLaunch: { onAppLaunch(item) }, onRemove: { removeItem(item) })
                    .onDrag { draggedItem = item; return NSItemProvider(object: item.id.uuidString as NSString) }
                    .onDrop(of: [.text], isTargeted: nil) { providers, _ in handleReorder(providers, targetItem: item) }
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
                DispatchQueue.main.async { items.append(newItem); onItemsChanged(items) }
            }
        }
        return true
    }

    private func handleReorder(_ providers: [NSItemProvider], targetItem: DockItem) -> Bool {
        guard let dragged = draggedItem, let fromIdx = items.firstIndex(where: { $0.id == dragged.id }), let toIdx = items.firstIndex(where: { $0.id == targetItem.id }), fromIdx != toIdx else { return false }
        withAnimation { items.move(fromOffsets: IndexSet(integer: fromIdx), toOffset: toIdx > fromIdx ? toIdx + 1 : toIdx) }
        draggedItem = nil
        onItemsChanged(items)
        return true
    }

    private func removeItem(_ item: DockItem) {
        items.removeAll(where: { $0.id == item.id })
        onItemsChanged(items)
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
