import AppKit

@MainActor
enum DockItemIconEncoder {
    static let pixelSize = 256
    static let maximumInputByteCount = 10 * 1_024 * 1_024

    static func encodeImage(at url: URL) -> Data? {
        guard url.isFileURL,
              let fileSize = try? url.resourceValues(
                forKeys: [.fileSizeKey]
              ).fileSize,
              fileSize <= maximumInputByteCount,
              let source = NSImage(contentsOf: url),
              source.size.width > 0,
              source.size.height > 0,
              let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: pixelSize,
                pixelsHigh: pixelSize,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
              )
        else { return nil }

        let canvas = NSSize(width: pixelSize, height: pixelSize)
        let scale = min(
            canvas.width / source.size.width,
            canvas.height / source.size.height
        )
        let drawSize = NSSize(
            width: source.size.width * scale,
            height: source.size.height * scale
        )
        let drawRect = NSRect(
            x: (canvas.width - drawSize.width) / 2,
            y: (canvas.height - drawSize.height) / 2,
            width: drawSize.width,
            height: drawSize.height
        )

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            return nil
        }
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: canvas).fill()
        source.draw(
            in: drawRect,
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )
        context.flushGraphics()
        return bitmap.representation(using: .png, properties: [:])
    }
}
