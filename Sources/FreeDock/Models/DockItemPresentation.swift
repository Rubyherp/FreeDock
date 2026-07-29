import Cocoa

@MainActor
struct DockItemPresentation {
    let displayName: String
    let icon: NSImage
    let bundleID: String?
    let isAvailable: Bool
    let kindDescription: String

    static func resolve(_ item: DockItem) -> DockItemPresentation {
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
            kindDescription: item.kind.displayName.lowercased()
        )
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
        }
    }

    var fallbackSymbolName: String {
        switch self {
        case .application: return "app"
        case .document: return "doc"
        case .folder: return "folder"
        case .separator: return "minus"
        }
    }
}
