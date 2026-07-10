import AppKit
import SwiftUI

@MainActor
final class TooltipManager {
    static let shared = TooltipManager()
    private var panel: NSPanel?
    private var showTask: DispatchWorkItem?

    func show(_ text: String, at screenRect: NSRect, orientation: Orientation) {
        showTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            self?.present(text, at: screenRect, orientation: orientation)
        }
        showTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: task)
    }

    func hide() {
        showTask?.cancel()
        showTask = nil
        panel?.orderOut(nil)
        panel = nil
    }

    private func present(_ text: String, at screenRect: NSRect, orientation: Orientation) {
        panel?.orderOut(nil)
        panel = nil
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.level = .popUpMenu
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let host = NSHostingView(rootView:
            Text(text)
                .font(.caption)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .shadow(radius: 5))
        let size = host.fittingSize
        p.contentView = host
        let origin: NSPoint
        switch orientation {
        case .horizontal:
            origin = NSPoint(x: screenRect.midX - size.width / 2, y: screenRect.maxY + 6)
        case .vertical:
            origin = NSPoint(x: screenRect.maxX + 6, y: screenRect.midY - size.height / 2)
        }
        p.setFrame(NSRect(origin: origin, size: size), display: false)
        p.orderFront(nil)
        panel = p
    }
}

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
