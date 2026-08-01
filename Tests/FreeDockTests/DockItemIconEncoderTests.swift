import AppKit
import Foundation
import Testing
@testable import FreeDock

@MainActor
@Test("Custom dock icons are normalized to portable square PNG data")
func customDockIconEncoding() throws {
    let source = try #require(NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: 24,
        pixelsHigh: 12,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ))
    let sourceData = try #require(
        source.representation(using: .png, properties: [:])
    )
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("freedock-custom-icon-\(UUID().uuidString).png")
    try sourceData.write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }

    let encoded = try #require(DockItemIconEncoder.encodeImage(at: url))
    let normalized = try #require(NSBitmapImageRep(data: encoded))

    #expect(normalized.pixelsWide == DockItemIconEncoder.pixelSize)
    #expect(normalized.pixelsHigh == DockItemIconEncoder.pixelSize)
    #expect(NSImage(data: encoded) != nil)
}
