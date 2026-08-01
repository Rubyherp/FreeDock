import Cocoa

@MainActor
struct DockItemPresentation {
    let displayName: String
    let icon: NSImage
    let bundleID: String?
    let isAvailable: Bool
    let kindDescription: String
    let badgeSymbolName: String?

    static func resolve(_ item: DockItem) -> DockItemPresentation {
        if item.kind == .trash {
            let isEmpty = TrashMonitor.shared.isEmpty
            let image = NSImage(
                named: isEmpty
                    ? NSImage.trashEmptyName
                    : NSImage.trashFullName
            ) ?? systemIcon(
                preferredName: "trash.fill",
                fallbackName: "trash",
                accessibilityDescription: "Trash"
            )
            image.size = NSSize(width: 64, height: 64)
            return DockItemPresentation(
                displayName: item.label.flatMap(\.nonEmpty) ?? "Trash",
                icon: image,
                bundleID: nil,
                isAvailable: TrashController.trashURL != nil,
                kindDescription: isEmpty ? "empty trash" : "trash containing items",
                badgeSymbolName: nil
            )
        }
        if let source = item.smartStackSource {
            return resolveSmartStack(item, source: source)
        }

        let path = item.path
        let isAvailable = !path.isEmpty
            && FileManager.default.fileExists(atPath: path)
        let fallbackName = URL(fileURLWithPath: path).lastPathComponent
        let resolvedName = item.label.flatMap(\.nonEmpty)
            ?? (path.isEmpty
                ? item.kind.displayName
                : FileManager.default.displayName(atPath: path))
            .nonEmpty
            ?? fallbackName
            .nonEmpty
            ?? item.kind.displayName
        let displayName = item.kind == .application
            ? (resolvedName as NSString).deletingPathExtension
            : resolvedName

        let icon: NSImage
        if isAvailable {
            icon = (NSWorkspace.shared.icon(forFile: path).copy() as? NSImage)
                ?? NSWorkspace.shared.icon(forFile: path)
        } else {
            icon = NSImage(
                systemSymbolName: item.kind.fallbackSymbolName,
                accessibilityDescription: displayName
            ) ?? NSImage()
        }
        icon.size = NSSize(width: 64, height: 64)

        let bundleID = item.kind == .application
            ? AppInfo.resolveBundleID(from: path)
            : nil
        return DockItemPresentation(
            displayName: displayName,
            icon: icon,
            bundleID: bundleID,
            isAvailable: isAvailable,
            kindDescription: item.kind.displayName.lowercased(),
            badgeSymbolName: item.kind == .folder
                ? "square.grid.2x2.fill"
                : nil
        )
    }

    private static func resolveSmartStack(
        _ item: DockItem,
        source: SmartStackSource
    ) -> DockItemPresentation {
        let displayName = item.label.flatMap(\.nonEmpty)
            ?? source.defaultLabel

        switch source {
        case .recentFiles:
            let icon = systemIcon(
                preferredName: "clock.fill",
                fallbackName: "clock",
                accessibilityDescription: displayName
            )
            icon.size = NSSize(width: 64, height: 64)
            return DockItemPresentation(
                displayName: displayName,
                icon: icon,
                bundleID: nil,
                isAvailable: true,
                kindDescription: "recent files stack",
                badgeSymbolName: "clock.fill"
            )

        case .downloads:
            let downloadsURL = FileManager.default.urls(
                for: .downloadsDirectory,
                in: .userDomainMask
            ).first?.standardizedFileURL
            let isAvailable = downloadsURL.map {
                FileManager.default.fileExists(atPath: $0.path)
            } ?? false
            let icon: NSImage
            if let downloadsURL, isAvailable {
                let workspaceIcon = NSWorkspace.shared.icon(
                    forFile: downloadsURL.path
                )
                icon = (workspaceIcon.copy() as? NSImage)
                    ?? workspaceIcon
            } else {
                icon = systemIcon(
                    preferredName: "arrow.down.circle.fill",
                    fallbackName: "folder",
                    accessibilityDescription: displayName
                )
            }
            icon.size = NSSize(width: 64, height: 64)
            return DockItemPresentation(
                displayName: displayName,
                icon: icon,
                bundleID: nil,
                isAvailable: isAvailable,
                kindDescription: "downloads stack",
                badgeSymbolName: "arrow.down"
            )
        }
    }

    private static func systemIcon(
        preferredName: String,
        fallbackName: String,
        accessibilityDescription: String
    ) -> NSImage {
        NSImage(
            systemSymbolName: preferredName,
            accessibilityDescription: accessibilityDescription
        )
            ?? NSImage(
                systemSymbolName: fallbackName,
                accessibilityDescription: accessibilityDescription
            )
            ?? NSImage()
    }
}

private extension String {
    var nonEmpty: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}

extension DockItemKind {
    var displayName: String {
        switch self {
        case .application: return "Application"
        case .document: return "Document"
        case .folder: return "Folder"
        case .separator: return "Separator"
        case .trash: return "Trash"
        }
    }

    var fallbackSymbolName: String {
        switch self {
        case .application: return "app"
        case .document: return "doc"
        case .folder: return "folder"
        case .separator: return "minus"
        case .trash: return "trash"
        }
    }
}
