import Cocoa
import SwiftUI

@MainActor
final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    private let onClosed: () -> Void

    init(
        requestAccessibility: @escaping @MainActor () -> Bool,
        requestScreenRecording: @escaping @MainActor () -> Bool,
        onFinish: @escaping @MainActor (Bool) -> Void,
        onClosed: @escaping () -> Void
    ) {
        self.onClosed = onClosed
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 520),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to FreeDock"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.minSize = NSSize(width: 680, height: 520)
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(
            rootView: OnboardingView(
                requestAccessibility: requestAccessibility,
                requestScreenRecording: requestScreenRecording,
                onFinish: onFinish
            )
        )
        window.center()
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_: Notification) {
        onClosed()
    }
}
