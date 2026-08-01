import AppKit
import Combine

@MainActor
final class TrashMonitor: ObservableObject {
    static let shared = TrashMonitor()

    @Published private(set) var isEmpty = true
    private var timer: Timer?

    private init() {
        refresh()
        timer = Timer.scheduledTimer(
            withTimeInterval: 2,
            repeats: true
        ) { _ in
            Task { @MainActor in
                TrashMonitor.shared.refresh()
            }
        }
    }

    func refresh() {
        guard let url = TrashController.trashURL,
              let contents = try? FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: nil,
                options: []
              )
        else {
            isEmpty = true
            return
        }
        isEmpty = contents.isEmpty
    }
}

enum TrashController {
    static var trashURL: URL? {
        FileManager.default.urls(
            for: .trashDirectory,
            in: .userDomainMask
        ).first?.standardizedFileURL
    }

    static func canRecycle(_ urls: [URL]) -> Bool {
        guard !urls.isEmpty else { return false }
        let trashPath = trashURL?.path
        return urls.allSatisfy {
            let path = $0.standardizedFileURL.path
            return $0.isFileURL
                && FileManager.default.fileExists(atPath: path)
                && path != trashPath
                && !(trashPath.map { path.hasPrefix($0 + "/") } ?? false)
        }
    }

    @MainActor
    static func recycle(
        _ urls: [URL],
        completion: @escaping @MainActor @Sendable (String?) -> Void
    ) -> Bool {
        guard canRecycle(urls) else { return false }
        NSWorkspace.shared.recycle(urls) { _, error in
            let errorMessage = error?.localizedDescription
            Task { @MainActor in
                TrashMonitor.shared.refresh()
                completion(errorMessage)
            }
        }
        return true
    }

    static func emptyTrash() -> [Error] {
        guard let trashURL,
              let contents = try? FileManager.default.contentsOfDirectory(
                at: trashURL,
                includingPropertiesForKeys: nil,
                options: []
              )
        else { return [] }
        var errors: [Error] = []
        for url in contents {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                errors.append(error)
            }
        }
        return errors
    }
}
