import Cocoa
import SwiftUI

struct FolderStackView: View {
    let item: DockItem
    let presentation: DockItemPresentation
    let recentFiles: [RecentFileRecord]
    let onOpenURL: (URL) -> Void
    let onOpenContainer: (() -> Void)?
    let onClearRecentFiles: (() -> Void)?
    let onOptionsChanged: (FolderStackOptions) -> Void
    let onClose: () -> Void

    @Environment(\.accessibilityReduceTransparency)
    private var reduceTransparency
    @State private var options: FolderStackOptions
    @State private var snapshot: FolderStackSnapshot?
    @State private var errorMessage: String?
    @State private var isLoading = true
    @State private var reloadID = UUID()

    init(
        item: DockItem,
        presentation: DockItemPresentation,
        recentFiles: [RecentFileRecord],
        onOpenURL: @escaping (URL) -> Void,
        onOpenContainer: (() -> Void)?,
        onClearRecentFiles: (() -> Void)?,
        onOptionsChanged: @escaping (FolderStackOptions) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.item = item
        self.presentation = presentation
        self.recentFiles = recentFiles
        self.onOpenURL = onOpenURL
        self.onOpenContainer = onOpenContainer
        self.onClearRecentFiles = onClearRecentFiles
        self.onOptionsChanged = onOptionsChanged
        self.onClose = onClose
        _options = State(initialValue: Self.normalizedOptions(for: item))
    }

    private var loadKey: LoadKey {
        LoadKey(
            itemID: item.id,
            path: item.path,
            source: item.smartStackSource,
            recentFiles: recentFiles,
            options: options,
            reloadID: reloadID
        )
    }

    private var resolvedPresentation: FolderStackOptions.Presentation {
        guard options.presentation == .automatic else {
            return options.presentation
        }
        return (snapshot?.totalCount ?? 0) <= 24 ? .grid : .list
    }

    var body: some View {
        GeometryReader { geometry in
            let layout = LayoutMetrics(availableSize: geometry.size)

            VStack(spacing: 0) {
                header(layout: layout)
                Divider().opacity(0.55)
                content(layout: layout)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if showsFooter {
                    Divider().opacity(0.55)
                    footer(layout: layout)
                }
            }
            .background(stackBackground)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: layout.cornerRadius,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: layout.cornerRadius,
                    style: .continuous
                )
                .strokeBorder(.white.opacity(0.18), lineWidth: 0.75)
            }
            .shadow(color: .black.opacity(0.26), radius: 22, y: 10)
            .padding(layout.outerPadding)
            .frame(
                width: geometry.size.width,
                height: geometry.size.height
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: loadKey) {
            await loadContents()
        }
        .onChange(of: options) { updated in
            onOptionsChanged(updated)
        }
        .onAppear {
            if item.folderOptions != options {
                onOptionsChanged(options)
            }
        }
        .onExitCommand(perform: onClose)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "\(presentation.displayName), \(presentation.kindDescription)"
        )
    }

    private var displayName: String {
        presentation.displayName
    }

    private func header(layout: LayoutMetrics) -> some View {
        HStack(spacing: layout.headerSpacing) {
            if !layout.isVeryNarrow {
                Image(nsImage: presentation.icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(
                        width: layout.headerIconSize,
                        height: layout.headerIconSize
                    )
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(displayName)

                Text(headerDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            if !layout.isNarrow {
                Button {
                    reloadID = UUID()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh \(displayName)")
                .accessibilityLabel("Refresh \(displayName)")
            }

            optionsMenu(includesRefresh: layout.isNarrow)

            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.borderless)
            .help("Close")
            .accessibilityLabel("Close \(displayName)")
        }
        .padding(.horizontal, layout.horizontalChromePadding)
        .padding(.vertical, layout.headerVerticalPadding)
    }

    private var headerDetail: String {
        if isLoading {
            return "Loading…"
        }
        guard let snapshot else {
            return errorMessage == nil ? chrome.idleDetail : "Unavailable"
        }
        let count = snapshot.totalCount
        return "\(count) item\(count == 1 ? "" : "s")"
    }

    private func optionsMenu(includesRefresh: Bool) -> some View {
        Menu {
            if includesRefresh {
                Button {
                    reloadID = UUID()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                Divider()
            }

            Section("View") {
                optionButton(
                    "Automatic",
                    selected: options.presentation == .automatic
                ) {
                    options.presentation = .automatic
                }
                optionButton(
                    "Grid",
                    selected: options.presentation == .grid
                ) {
                    options.presentation = .grid
                }
                optionButton(
                    "List",
                    selected: options.presentation == .list
                ) {
                    options.presentation = .list
                }
            }

            Section("Sort By") {
                if item.smartStackSource == .recentFiles {
                    optionButton(
                        "Recently Opened",
                        selected: options.sortOrder == .recentlyOpened
                    ) {
                        options.sortOrder = .recentlyOpened
                    }
                }
                optionButton(
                    "Name",
                    selected: options.sortOrder == .name
                ) {
                    options.sortOrder = .name
                }
                optionButton(
                    "Date Modified",
                    selected: options.sortOrder == .dateModified
                ) {
                    options.sortOrder = .dateModified
                }
                optionButton(
                    "Kind",
                    selected: options.sortOrder == .kind
                ) {
                    options.sortOrder = .kind
                }
            }

            if item.smartStackSource != .recentFiles {
                Divider()

                Toggle(
                    "Show Hidden Files",
                    isOn: Binding(
                        get: { options.showHiddenFiles },
                        set: { options.showHiddenFiles = $0 }
                    )
                )
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Stack options")
        .accessibilityLabel("\(displayName) stack options")
    }

    private func optionButton(
        _ title: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            if selected {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    @ViewBuilder
    private func content(layout: LayoutMetrics) -> some View {
        if isLoading {
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading \(displayName)…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .combine)
        } else if let errorMessage {
            VStack(spacing: 12) {
                Image(systemName: chrome.errorSymbolName)
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
                Text(chrome.errorTitle)
                    .font(.headline)
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
                Button("Try Again") {
                    reloadID = UUID()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let snapshot, snapshot.entries.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: chrome.emptySymbolName)
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
                Text(chrome.emptyTitle)
                    .font(.headline)
                Text(chrome.emptyMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let snapshot {
            switch resolvedPresentation {
            case .automatic, .grid:
                grid(entries: snapshot.entries, layout: layout)
            case .list:
                list(entries: snapshot.entries, layout: layout)
            }
        }
    }

    private func grid(
        entries: [FolderStackEntry],
        layout: LayoutMetrics
    ) -> some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(
                        .adaptive(
                            minimum: layout.gridMinimumWidth,
                            maximum: layout.gridMaximumWidth
                        ),
                        spacing: layout.gridColumnSpacing
                    ),
                ],
                spacing: layout.gridRowSpacing
            ) {
                ForEach(entries, id: \.url) { entry in
                    Button {
                        onOpenURL(entry.url)
                    } label: {
                        VStack(spacing: 6) {
                            FolderStackFileIcon(
                                url: entry.url,
                                size: layout.gridIconSize
                            )
                            Text(entry.name)
                                .font(.system(size: 11))
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .truncationMode(.middle)
                                .frame(maxWidth: layout.gridLabelWidth)
                        }
                        .frame(
                            maxWidth: .infinity,
                            minHeight: layout.gridItemHeight
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(FolderStackItemButtonStyle())
                    .help(entry.name)
                    .accessibilityLabel(entry.name)
                    .accessibilityValue(entry.kindDescription)
                    .accessibilityHint(
                        entry.isFolder
                            ? "Opens this folder in Finder."
                            : "Opens this item."
                    )
                }
            }
            .padding(layout.contentPadding)
        }
    }

    private func list(
        entries: [FolderStackEntry],
        layout: LayoutMetrics
    ) -> some View {
        ScrollView {
            LazyVStack(spacing: 3) {
                ForEach(entries, id: \.url) { entry in
                    Button {
                        onOpenURL(entry.url)
                    } label: {
                        HStack(spacing: 11) {
                            FolderStackFileIcon(url: entry.url, size: 30)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.name)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Text(entry.kindDescription)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if entry.isFolder {
                                Image(systemName: "arrow.up.forward.app")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(FolderStackItemButtonStyle())
                    .accessibilityLabel(entry.name)
                    .accessibilityValue(entry.kindDescription)
                }
            }
            .padding(layout.listPadding)
        }
    }

    private func footer(layout: LayoutMetrics) -> some View {
        HStack {
            if snapshot?.isTruncated == true {
                if layout.isVeryNarrow {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(.secondary)
                        .help(truncatedItemsDescription)
                        .accessibilityLabel(truncatedItemsDescription)
                } else {
                    Label(
                        truncatedItemsDescription,
                        systemImage: "ellipsis.circle"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
            }

            Spacer()

            if let onOpenContainer {
                Button(action: onOpenContainer) {
                    if layout.isVeryNarrow {
                        Image(systemName: "folder")
                    } else {
                        Text("Open in Finder")
                    }
                }
                .buttonStyle(.borderless)
                .font(.callout.weight(.medium))
                .help("Open in Finder")
                .accessibilityLabel("Open in Finder")
            } else if let onClearRecentFiles {
                Button(action: onClearRecentFiles) {
                    if layout.isVeryNarrow {
                        Image(systemName: "trash")
                    } else {
                        Text("Clear History")
                    }
                }
                .buttonStyle(.borderless)
                .font(.callout.weight(.medium))
                .help("Clear Recent Files history")
                .accessibilityLabel("Clear Recent Files history")
                .disabled(recentFiles.isEmpty)
            }
        }
        .padding(.horizontal, layout.horizontalChromePadding)
        .padding(.vertical, layout.footerVerticalPadding)
    }

    private var truncatedItemsDescription: String {
        "Showing the first \(snapshot?.entries.count ?? 0) items"
    }

    private var showsFooter: Bool {
        snapshot?.isTruncated == true
            || onOpenContainer != nil
            || onClearRecentFiles != nil
    }

    private var chrome: StackChrome {
        switch item.smartStackSource {
        case .recentFiles:
            return StackChrome(
                idleDetail: "Recent Files",
                errorTitle: "Recent Files Unavailable",
                errorSymbolName: "clock",
                emptyTitle: "No Recent Files Yet",
                emptyMessage:
                    "Documents you open through FreeDock will appear here.",
                emptySymbolName: "clock"
            )

        case .downloads:
            return StackChrome(
                idleDetail: "Downloads",
                errorTitle: "Downloads Unavailable",
                errorSymbolName: "arrow.down.circle",
                emptyTitle: "No Downloads",
                emptyMessage: "Files you download will appear here.",
                emptySymbolName: "arrow.down.circle"
            )

        case nil:
            return StackChrome(
                idleDetail: "Folder",
                errorTitle: "Folder Unavailable",
                errorSymbolName: "folder.badge.questionmark",
                emptyTitle: "Folder Is Empty",
                emptyMessage:
                    "Items added to this folder will appear here.",
                emptySymbolName: "folder"
            )
        }
    }

    @ViewBuilder
    private var stackBackground: some View {
        if reduceTransparency {
            Color(nsColor: .windowBackgroundColor)
        } else {
            Rectangle().fill(.regularMaterial)
        }
    }

    private func loadContents() async {
        isLoading = true
        errorMessage = nil

        var configuredItem = item
        configuredItem.folderOptions = options
        let loadItem = configuredItem
        let recentFiles = recentFiles
        let outcome = await Task.detached(priority: .userInitiated) {
            do {
                return FolderStackLoadOutcome.loaded(
                    try FolderStackLoader.load(
                        item: loadItem,
                        recentFiles: recentFiles,
                        limit: 200
                    )
                )
            } catch {
                return FolderStackLoadOutcome.failed(
                    error.localizedDescription
                )
            }
        }.value

        guard !Task.isCancelled else { return }
        switch outcome {
        case let .loaded(snapshot):
            self.snapshot = snapshot
            errorMessage = nil
        case let .failed(message):
            snapshot = nil
            errorMessage = message
        }
        isLoading = false
    }

    private static func normalizedOptions(
        for item: DockItem
    ) -> FolderStackOptions {
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

    private struct LoadKey: Hashable {
        let itemID: UUID
        let path: String
        let source: SmartStackSource?
        let recentFiles: [RecentFileRecord]
        let options: FolderStackOptions
        let reloadID: UUID
    }

    private struct StackChrome {
        let idleDetail: String
        let errorTitle: String
        let errorSymbolName: String
        let emptyTitle: String
        let emptyMessage: String
        let emptySymbolName: String
    }

    private struct LayoutMetrics {
        let isNarrow: Bool
        let isVeryNarrow: Bool
        let isShort: Bool

        init(availableSize: CGSize) {
            isNarrow = availableSize.width < 400
            isVeryNarrow = availableSize.width < 280
            isShort = availableSize.height < 340
        }

        var outerPadding: CGFloat {
            isNarrow || isShort ? 8 : 16
        }

        var cornerRadius: CGFloat {
            isNarrow || isShort ? 14 : 18
        }

        var horizontalChromePadding: CGFloat {
            isNarrow ? 10 : 18
        }

        var headerVerticalPadding: CGFloat {
            isShort ? 8 : 14
        }

        var footerVerticalPadding: CGFloat {
            isShort ? 7 : 11
        }

        var headerSpacing: CGFloat {
            isNarrow ? 8 : 12
        }

        var headerIconSize: CGFloat {
            isNarrow ? 30 : 36
        }

        var gridMinimumWidth: CGFloat {
            isNarrow ? 58 : 72
        }

        var gridMaximumWidth: CGFloat {
            isNarrow ? 72 : 88
        }

        var gridColumnSpacing: CGFloat {
            isNarrow ? 7 : 10
        }

        var gridRowSpacing: CGFloat {
            isShort ? 8 : 13
        }

        var gridIconSize: CGFloat {
            isNarrow || isShort ? 40 : 48
        }

        var gridLabelWidth: CGFloat {
            isNarrow ? 66 : 82
        }

        var gridItemHeight: CGFloat {
            isNarrow || isShort ? 68 : 78
        }

        var contentPadding: CGFloat {
            isNarrow || isShort ? 8 : 16
        }

        var listPadding: CGFloat {
            isNarrow || isShort ? 6 : 10
        }
    }
}

private enum FolderStackLoadOutcome: Sendable {
    case loaded(FolderStackSnapshot)
    case failed(String)
}

private struct FolderStackFileIcon: View {
    let url: URL
    let size: CGFloat
    @State private var icon: NSImage?

    var body: some View {
        Image(nsImage: icon ?? placeholder)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .onAppear {
                guard icon == nil else { return }
                let workspaceIcon = NSWorkspace.shared.icon(forFile: url.path)
                let resolved = (workspaceIcon.copy() as? NSImage)
                    ?? workspaceIcon
                resolved.size = NSSize(width: size, height: size)
                icon = resolved
            }
            .accessibilityHidden(true)
    }

    private var placeholder: NSImage {
        NSImage(
            systemSymbolName: "doc",
            accessibilityDescription: nil
        ) ?? NSImage()
    }
}

private struct FolderStackItemButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        configuration.isPressed
                            ? Color.accentColor.opacity(0.16)
                            : Color.clear
                    )
            )
    }
}
