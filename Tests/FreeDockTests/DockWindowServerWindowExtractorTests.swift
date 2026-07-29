import CoreGraphics
import Foundation
import Testing

@testable import FreeDock

@Suite("Dock WindowServer window extraction")
struct DockWindowServerWindowExtractorTests {
    @Test("Unshareable surfaces are rejected")
    func unshareableSurfacesAreRejected() {
        let windows = DockWindowServerWindowExtractor.windows(
            from: [
                rawWindow(
                    id: 10,
                    sharingState: CGWindowSharingType.none
                ),
                rawWindow(
                    id: 11,
                    sharingState: .readOnly
                ),
                rawWindow(
                    id: 12,
                    sharingState: .readWrite
                ),
                rawWindow(id: 13, sharingState: nil),
            ],
            matching: [42]
        )

        #expect(windows.map(\.windowID) == [11, 12, 13])
        #expect(windows.map(\.sourceOrder) == [1, 2, 3])
    }

    @Test("Offscreen windows without sharing metadata remain discoverable")
    func offscreenWindowIsRetained() throws {
        let frame = CGRect(
            x: -1_200,
            y: 80,
            width: 900,
            height: 700
        )
        let window = try #require(
            DockWindowServerWindowExtractor.windows(
                from: [
                    rawWindow(
                        id: 20,
                        title: "Other Desktop",
                        frame: frame,
                        sharingState: nil,
                        isOnScreen: false
                    )
                ],
                matching: [42]
            ).first
        )

        #expect(window.windowID == 20)
        #expect(window.processIdentifier == 42)
        #expect(window.title == "Other Desktop")
        #expect(window.frame == frame)
        #expect(!window.isOnScreen)
    }

    @Test("Helper and malformed surfaces are rejected")
    func helperSurfacesAreRejected() {
        var malformed = rawWindow(id: 35)
        malformed.removeValue(
            forKey: kCGWindowBounds as String
        )
        var malformedSharingState = rawWindow(id: 36)
        malformedSharingState[
            kCGWindowSharingState as String
        ] = "invalid"

        let windows = DockWindowServerWindowExtractor.windows(
            from: [
                rawWindow(id: 30),
                rawWindow(id: 31, processIdentifier: 99),
                rawWindow(id: 32, layer: 1),
                rawWindow(
                    id: 33,
                    frame: CGRect(
                        x: 0,
                        y: 0,
                        width: 79,
                        height: 49
                    )
                ),
                rawWindow(id: 34, alpha: 0.01),
                malformed,
                malformedSharingState,
            ],
            matching: [42]
        )

        #expect(windows.map(\.windowID) == [30])
    }

    private func rawWindow(
        id: CGWindowID,
        processIdentifier: pid_t = 42,
        title: String = "Window",
        frame: CGRect = CGRect(
            x: 10,
            y: 20,
            width: 800,
            height: 600
        ),
        layer: Int = 0,
        sharingState: CGWindowSharingType? = .readOnly,
        alpha: Double = 1,
        isOnScreen: Bool = true
    ) -> [String: Any] {
        var values: [String: Any] = [
            kCGWindowOwnerPID as String:
                NSNumber(value: processIdentifier),
            kCGWindowNumber as String: NSNumber(value: id),
            kCGWindowLayer as String: NSNumber(value: layer),
            kCGWindowBounds as String:
                CGRectCreateDictionaryRepresentation(frame),
            kCGWindowName as String: title,
            kCGWindowAlpha as String: NSNumber(value: alpha),
            kCGWindowIsOnscreen as String:
                NSNumber(value: isOnScreen),
        ]
        if let sharingState {
            values[kCGWindowSharingState as String] =
                NSNumber(value: sharingState.rawValue)
        }
        return values
    }
}
