import AppKit
import CoreGraphics
import Foundation
@preconcurrency import ScreenCaptureKit

@MainActor
final class DockWindowCaptureController {
    private struct ThumbnailCacheEntry {
        let image: NSImage
        let capturedAt: Date
    }

    private struct ThumbnailCacheKey: Hashable {
        let processIdentifier: pid_t
        let windowID: CGWindowID
        let pixelWidth: Int
        let pixelHeight: Int
    }

    private let cacheLifetime: TimeInterval = 5
    private let shareableContentLifetime: TimeInterval = 1
    private var thumbnailCache: [ThumbnailCacheKey: ThumbnailCacheEntry] = [:]
    private var shareableWindowStore: AnyObject?

    var isScreenCaptureTrusted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Requests permission only after a direct user action.
    @discardableResult
    func requestScreenCaptureAccess() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    func windows(
        for processIdentifiers: Set<pid_t>
    ) -> [DockWindowServerWindow] {
        guard !processIdentifiers.isEmpty,
            let rawWindows = CGWindowListCopyWindowInfo(
                [.excludeDesktopElements],
                kCGNullWindowID
            ) as? [[String: Any]]
        else {
            return []
        }

        return DockWindowServerWindowExtractor.windows(
            from: rawWindows,
            matching: processIdentifiers
        )
    }

    func thumbnail(
        processIdentifier: pid_t,
        for windowID: CGWindowID,
        frame: CGRect,
        maximumPixelSize: CGSize
    ) async -> NSImage? {
        guard !Task.isCancelled else { return nil }
        guard isScreenCaptureTrusted else {
            clearThumbnailCache()
            return nil
        }

        let pixelSize = DockWindowThumbnailGeometry.pixelSize(
            for: frame.size,
            fitting: maximumPixelSize
        )
        guard pixelSize.width > 0, pixelSize.height > 0 else {
            return nil
        }
        let cacheKey = ThumbnailCacheKey(
            processIdentifier: processIdentifier,
            windowID: windowID,
            pixelWidth: Int(pixelSize.width),
            pixelHeight: Int(pixelSize.height)
        )
        if let cached = thumbnailCache[cacheKey],
            Date().timeIntervalSince(cached.capturedAt)
                < cacheLifetime
        {
            return cached.image
        }

        let capturedImage: CGImage?
        if #available(macOS 14.0, *) {
            capturedImage = await modernThumbnail(
                for: windowID,
                pixelSize: pixelSize
            )
        } else {
            capturedImage = legacyThumbnail(
                for: windowID,
                pixelSize: pixelSize
            )
        }
        guard !Task.isCancelled else { return nil }
        guard let capturedImage else {
            thumbnailCache.removeValue(forKey: cacheKey)
            return nil
        }

        let thumbnail = NSImage(
            cgImage: capturedImage,
            size: NSSize(
                width: capturedImage.width,
                height: capturedImage.height
            )
        )
        thumbnailCache[cacheKey] = ThumbnailCacheEntry(
            image: thumbnail,
            capturedAt: Date()
        )
        trimCache()
        return thumbnail
    }

    func clearThumbnailCache() {
        thumbnailCache.removeAll()
    }

    func reset() {
        clearThumbnailCache()
        shareableWindowStore = nil
    }

    private func trimCache() {
        guard thumbnailCache.count > 24 else { return }
        let oldest = thumbnailCache.sorted {
            $0.value.capturedAt < $1.value.capturedAt
        }
        for entry in oldest.prefix(
            thumbnailCache.count - 24
        ) {
            thumbnailCache.removeValue(forKey: entry.key)
        }
    }

    @available(macOS 14.0, *)
    private func modernThumbnail(
        for windowID: CGWindowID,
        pixelSize: CGSize
    ) async -> CGImage? {
        let store: DockShareableWindowStore
        if let existing =
            shareableWindowStore as? DockShareableWindowStore
        {
            store = existing
        } else {
            let created = DockShareableWindowStore(
                cacheLifetime: shareableContentLifetime
            )
            shareableWindowStore = created
            store = created
        }
        guard let window = await store.window(withID: windowID)
        else {
            return nil
        }

        let configuration = SCStreamConfiguration()
        configuration.width = Int(pixelSize.width)
        configuration.height = Int(pixelSize.height)
        configuration.showsCursor = false
        configuration.scalesToFit = true
        configuration.ignoreShadowsSingleWindow = true
        configuration.ignoreGlobalClipSingleWindow = true

        let filter = SCContentFilter(
            desktopIndependentWindow: window
        )
        return try? await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )
    }

    @available(macOS, introduced: 10.15, obsoleted: 14.0)
    private func legacyThumbnail(
        for windowID: CGWindowID,
        pixelSize: CGSize
    ) -> CGImage? {
        guard
            let image = CGWindowListCreateImage(
                .null,
                [.optionIncludingWindow],
                windowID,
                [.boundsIgnoreFraming, .bestResolution]
            )
        else {
            return nil
        }
        return downscaled(image, to: pixelSize)
    }

    private func downscaled(
        _ image: CGImage,
        to pixelSize: CGSize
    ) -> CGImage? {
        let width = max(1, Int(pixelSize.width))
        let height = max(1, Int(pixelSize.height))
        guard
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo:
                    CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            return nil
        }
        context.interpolationQuality = .high
        context.draw(
            image,
            in: CGRect(
                x: 0,
                y: 0,
                width: width,
                height: height
            )
        )
        return context.makeImage()
    }

}

enum DockWindowServerWindowExtractor {
    static func windows(
        from rawWindows: [[String: Any]],
        matching processIdentifiers: Set<pid_t>
    ) -> [DockWindowServerWindow] {
        rawWindows.enumerated().compactMap {
            sourceOrder,
            values in
            guard
                let processNumber =
                    values[kCGWindowOwnerPID as String]
                    as? NSNumber,
                processIdentifiers.contains(
                    pid_t(processNumber.int32Value)
                ),
                let windowNumber =
                    values[kCGWindowNumber as String]
                    as? NSNumber,
                let layerNumber =
                    values[kCGWindowLayer as String]
                    as? NSNumber,
                layerNumber.intValue == 0,
                isShareable(
                    values[kCGWindowSharingState as String]
                ),
                let frame = windowFrame(
                    values[kCGWindowBounds as String]
                ),
                frame.width >= 80,
                frame.height >= 50,
                (values[kCGWindowAlpha as String]
                    as? NSNumber)?.doubleValue ?? 1 > 0.01
            else {
                return nil
            }

            return DockWindowServerWindow(
                windowID: CGWindowID(
                    windowNumber.uint32Value
                ),
                processIdentifier: pid_t(
                    processNumber.int32Value
                ),
                title: values[kCGWindowName as String]
                    as? String,
                frame: frame,
                isOnScreen: (values[kCGWindowIsOnscreen as String]
                    as? NSNumber)?.boolValue ?? false,
                sourceOrder: sourceOrder
            )
        }
    }

    private static func isShareable(_ value: Any?) -> Bool {
        guard let sharingState =
            (value as? NSNumber)?.uint32Value
        else {
            return false
        }
        return sharingState
            != CGWindowSharingType.none.rawValue
    }

    private static func windowFrame(_ value: Any?) -> CGRect? {
        guard let dictionary = value as? NSDictionary else {
            return nil
        }
        var frame = CGRect.zero
        guard
            CGRectMakeWithDictionaryRepresentation(
                dictionary,
                &frame
            )
        else {
            return nil
        }
        return frame
    }
}

@available(macOS 12.3, *)
@MainActor
private final class DockShareableWindowStore {
    private let cacheLifetime: TimeInterval
    private var windows: [CGWindowID: SCWindow] = [:]
    private var loadedAt: Date?

    init(cacheLifetime: TimeInterval) {
        self.cacheLifetime = cacheLifetime
    }

    func window(withID windowID: CGWindowID) async -> SCWindow? {
        guard !Task.isCancelled else { return nil }
        if let loadedAt,
            Date().timeIntervalSince(loadedAt) < cacheLifetime,
            let window = windows[windowID]
        {
            return window
        }

        do {
            let content =
                try await SCShareableContent
                .excludingDesktopWindows(
                    true,
                    onScreenWindowsOnly: false
                )
            guard !Task.isCancelled else { return nil }
            windows = Dictionary(
                uniqueKeysWithValues: content.windows
                    .filter { $0.windowLayer == 0 }
                    .map { ($0.windowID, $0) }
            )
            loadedAt = Date()
            return windows[windowID]
        } catch {
            return nil
        }
    }
}

enum DockWindowThumbnailGeometry {
    static func pixelSize(
        for source: CGSize,
        fitting maximum: CGSize
    ) -> CGSize {
        guard source.width > 0,
            source.height > 0,
            maximum.width > 0,
            maximum.height > 0
        else {
            return .zero
        }
        let scale = min(
            maximum.width / source.width,
            maximum.height / source.height
        )
        return CGSize(
            width: max(1, floor(source.width * scale)),
            height: max(1, floor(source.height * scale))
        )
    }
}
