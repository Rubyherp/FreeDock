import AppKit
import SwiftUI

/// Helper to read a SwiftUI view's screen rect via AppKit
struct ScreenRectReader: NSViewRepresentable {
    let onRect: (NSRect) -> Void
    func makeNSView(context _: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ nsView: NSView, context _: Context) {
        DispatchQueue.main.async {
            guard let win = nsView.window else { return }
            onRect(win.convertToScreen(nsView.convert(nsView.bounds, to: nil)))
        }
    }
}
