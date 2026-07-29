import Foundation
import Testing
@testable import FreeDock

@Suite("Dock window thumbnail geometry")
struct DockWindowThumbnailGeometryTests {
    @Test("Wide windows preserve aspect ratio")
    func wideWindow() {
        let size = DockWindowThumbnailGeometry.pixelSize(
            for: CGSize(width: 1600, height: 900),
            fitting: CGSize(width: 332, height: 192)
        )

        #expect(size == CGSize(width: 332, height: 186))
    }

    @Test("Tall windows preserve aspect ratio")
    func tallWindow() {
        let size = DockWindowThumbnailGeometry.pixelSize(
            for: CGSize(width: 600, height: 1200),
            fitting: CGSize(width: 332, height: 192)
        )

        #expect(size == CGSize(width: 96, height: 192))
    }

    @Test("Invalid sizes do not request a capture")
    func invalidSize() {
        #expect(
            DockWindowThumbnailGeometry.pixelSize(
                for: .zero,
                fitting: CGSize(width: 332, height: 192)
            ) == .zero
        )
        #expect(
            DockWindowThumbnailGeometry.pixelSize(
                for: CGSize(width: 800, height: 600),
                fitting: .zero
            ) == .zero
        )
    }
}
