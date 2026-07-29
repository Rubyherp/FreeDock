import Foundation
import UniformTypeIdentifiers

enum DockItemKind: String, Codable, Equatable, Sendable {
    case application
    case document
    case folder
    case separator
}

struct FolderStackOptions: Codable, Equatable, Hashable, Sendable {
    enum Presentation: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
        case automatic
        case grid
        case list
    }

    enum SortOrder: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
        case name
        case dateModified
        case kind
    }

    var presentation: Presentation
    var sortOrder: SortOrder
    var showHiddenFiles: Bool

    init(
        presentation: Presentation = .automatic,
        sortOrder: SortOrder = .name,
        showHiddenFiles: Bool = false
    ) {
        self.presentation = presentation
        self.sortOrder = sortOrder
        self.showHiddenFiles = showHiddenFiles
    }

    private enum CodingKeys: String, CodingKey {
        case presentation
        case sortOrder
        case showHiddenFiles
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        presentation =
            (try? container.decode(Presentation.self, forKey: .presentation))
            ?? .automatic
        sortOrder =
            (try? container.decode(SortOrder.self, forKey: .sortOrder))
            ?? .name
        showHiddenFiles =
            (try? container.decode(Bool.self, forKey: .showHiddenFiles))
            ?? false
    }
}

struct DockItem: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var path: String
    var label: String?
    var kind: DockItemKind
    var folderOptions: FolderStackOptions?

    /// Source compatibility for code and configs created before typed dock items.
    var appPath: String {
        get { path }
        set { path = newValue }
    }

    /// The legacy value remains encoded so older FreeDock builds can still load a config.
    var isSeparator: Bool {
        kind == .separator
    }

    init(
        id: UUID = UUID(),
        kind: DockItemKind,
        path: String,
        label: String? = nil,
        folderOptions: FolderStackOptions? = nil
    ) {
        self.id = id
        self.kind = kind
        self.path = kind == .separator ? "" : path
        self.label = label
        self.folderOptions = kind == .folder
            ? (folderOptions ?? FolderStackOptions())
            : nil
    }

    /// Legacy initializer retained for application-only call sites.
    init(id: UUID = UUID(), appPath: String, label: String? = nil) {
        self.init(
            id: id,
            kind: .application,
            path: appPath,
            label: label
        )
    }

    static func application(
        at url: URL,
        id: UUID = UUID(),
        label: String? = nil
    ) -> DockItem {
        DockItem(
            id: id,
            kind: .application,
            path: url.standardizedFileURL.path,
            label: label ?? defaultLabel(for: url, kind: .application)
        )
    }

    static func document(
        at url: URL,
        id: UUID = UUID(),
        label: String? = nil
    ) -> DockItem {
        DockItem(
            id: id,
            kind: .document,
            path: url.standardizedFileURL.path,
            label: label ?? defaultLabel(for: url, kind: .document)
        )
    }

    static func folder(
        at url: URL,
        id: UUID = UUID(),
        label: String? = nil,
        options: FolderStackOptions = FolderStackOptions()
    ) -> DockItem {
        DockItem(
            id: id,
            kind: .folder,
            path: url.standardizedFileURL.path,
            label: label ?? defaultLabel(for: url, kind: .folder),
            folderOptions: options
        )
    }

    static func separator(id: UUID = UUID()) -> DockItem {
        DockItem(id: id, kind: .separator, path: "")
    }

    /// Classifies a file-system URL for pinning without throwing for stale or invalid drops.
    static func pinnedItem(at url: URL) -> DockItem? {
        guard url.isFileURL else { return nil }

        let standardizedURL = url.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: standardizedURL.path,
            isDirectory: &isDirectory
        ) else {
            return nil
        }

        let values = try? standardizedURL.resourceValues(
            forKeys: [
                .contentTypeKey,
                .isDirectoryKey,
                .isPackageKey,
                .localizedNameKey,
            ]
        )
        let contentType = values?.contentType
        let directory = values?.isDirectory ?? isDirectory.boolValue
        let isApplication =
            directory
            && (
                standardizedURL.pathExtension.caseInsensitiveCompare("app")
                    == .orderedSame
                || contentType?.conforms(to: .application) == true
            )

        if isApplication {
            return application(at: standardizedURL)
        }

        let package = values?.isPackage ?? false
        if directory, !package {
            return folder(at: standardizedURL)
        }

        return document(at: standardizedURL)
    }

    func duplicated() -> DockItem {
        DockItem(
            kind: kind,
            path: path,
            label: label,
            folderOptions: folderOptions
        )
    }

    var fileURL: URL? {
        guard kind != .separator, !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }

    private static func defaultLabel(for url: URL, kind: DockItemKind) -> String {
        let localizedName = (try? url.resourceValues(forKeys: [.localizedNameKey]))?
            .localizedName
        let fallbackName = url.lastPathComponent
        let name = localizedName.flatMap { $0.isEmpty ? nil : $0 }
            ?? fallbackName

        if kind == .application {
            return (name as NSString).deletingPathExtension
        }
        return name
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case path
        case appPath
        case label
        case kind
        case folderOptions
        case isSeparator
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)

        let legacySeparator =
            (try? container.decode(Bool.self, forKey: .isSeparator))
            ?? false
        let decodedKind = try? container.decode(DockItemKind.self, forKey: .kind)
        kind = legacySeparator ? .separator : (decodedKind ?? .application)

        let decodedPath =
            (try? container.decode(String.self, forKey: .path))
            ?? (try? container.decode(String.self, forKey: .appPath))
            ?? ""
        path = kind == .separator ? "" : decodedPath
        label = try? container.decode(String.self, forKey: .label)

        if kind == .folder {
            folderOptions =
                (try? container.decode(FolderStackOptions.self, forKey: .folderOptions))
                ?? FolderStackOptions()
        } else {
            folderOptions = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(path, forKey: .path)
        try container.encode(path, forKey: .appPath)
        try container.encodeIfPresent(label, forKey: .label)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(folderOptions, forKey: .folderOptions)
        try container.encode(isSeparator, forKey: .isSeparator)
    }
}
