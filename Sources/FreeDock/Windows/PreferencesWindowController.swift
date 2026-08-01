import Cocoa
import SwiftUI

@MainActor
final class PreferencesWindowController: NSWindowController,
    NSWindowDelegate, NSToolbarDelegate
{
    private let store: DockPreferencesStore
    private var permissionRefreshTimer: Timer?
    private let searchToolbarItem = NSSearchToolbarItem(
        itemIdentifier: NSToolbarItem.Identifier("FreeDockSettingsSearch")
    )

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
        let toolbar = NSToolbar(identifier: "FreeDockPreferencesToolbar")
        toolbar.displayMode = .iconOnly
        searchToolbarItem.searchField.placeholderString = "Search Settings"
        searchToolbarItem.searchField.setAccessibilityLabel(
            "Search FreeDock settings"
        )
        window.toolbar = toolbar
        super.init(window: window)
        toolbar.delegate = self
        window.delegate = self
        searchToolbarItem.searchField.target = self
        searchToolbarItem.searchField.action = #selector(searchChanged(_:))
        window.onFind = { [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self.searchToolbarItem.searchField)
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

    @objc private func searchChanged(_ sender: NSSearchField) {
        store.settingsSearchText = sender.stringValue
    }

    func toolbarDefaultItemIdentifiers(
        _: NSToolbar
    ) -> [NSToolbarItem.Identifier] {
        [searchToolbarItem.itemIdentifier]
    }

    func toolbarAllowedItemIdentifiers(
        _: NSToolbar
    ) -> [NSToolbarItem.Identifier] {
        [searchToolbarItem.itemIdentifier, .flexibleSpace]
    }

    func toolbar(
        _: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar _: Bool
    ) -> NSToolbarItem? {
        itemIdentifier == searchToolbarItem.itemIdentifier
            ? searchToolbarItem
            : nil
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
