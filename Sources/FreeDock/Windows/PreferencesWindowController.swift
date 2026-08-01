import Cocoa
import SwiftUI

@MainActor
final class PreferencesWindowController: NSWindowController, NSWindowDelegate {
    private let store: DockPreferencesStore
    private var permissionRefreshTimer: Timer?

    init(store: DockPreferencesStore) {
        self.store = store
        let window = PreferencesWindow(
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
        window.delegate = self
        window.onFind = {
            NotificationCenter.default.post(
                name: .freeDockFocusSettingsSearch,
                object: nil
            )
        }
        window.onUndo = { [weak self] in
            self?.store.perform(.undo)
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.deminiaturize(nil)
        window?.makeKeyAndOrderFront(nil)
        store.refreshPermissions()
        startPermissionRefreshTimer()
    }

    func windowWillClose(_: Notification) {
        stopPermissionRefreshTimer()
    }

    func windowDidMiniaturize(_: Notification) {
        stopPermissionRefreshTimer()
    }

    func windowDidDeminiaturize(_: Notification) {
        store.refreshPermissions()
        startPermissionRefreshTimer()
    }

    private func startPermissionRefreshTimer() {
        guard permissionRefreshTimer == nil,
              window?.isVisible == true,
              window?.isMiniaturized == false
        else {
            return
        }

        let timer = Timer(
            timeInterval: 0.9,
            target: self,
            selector: #selector(refreshPermissionStatus),
            userInfo: nil,
            repeats: true
        )
        timer.tolerance = 0.15
        RunLoop.main.add(timer, forMode: .common)
        permissionRefreshTimer = timer
    }

    private func stopPermissionRefreshTimer() {
        permissionRefreshTimer?.invalidate()
        permissionRefreshTimer = nil
    }

    @objc private func refreshPermissionStatus() {
        store.refreshPermissions()
    }

}

private final class PreferencesWindow: NSWindow {
    var onFind: (() -> Void)?
    var onUndo: (() -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(
            .deviceIndependentFlagsMask
        )
        if modifiers == .command,
           event.charactersIgnoringModifiers?.lowercased() == "f"
        {
            onFind?()
            return true
        }
        if modifiers == .command,
           event.charactersIgnoringModifiers?.lowercased() == "z"
        {
            onUndo?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
