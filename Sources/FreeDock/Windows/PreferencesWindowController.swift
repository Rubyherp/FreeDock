import Cocoa
import SwiftUI

@MainActor
final class PreferencesWindowController: NSWindowController {
    init(store: DockPreferencesStore) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 570),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "FreeDock Preferences"
        window.minSize = NSSize(width: 700, height: 500)
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(
            rootView: DockPreferencesView(store: store)
        )
        window.center()
        window.setFrameAutosaveName("FreeDockPreferencesWindow")
        super.init(window: window)
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
}
