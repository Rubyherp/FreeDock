import Cocoa
import SwiftUI

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var dockPanels: [UUID: DockPanel] = [:]
    private let configManager = ConfigManager(
        configPath: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/freedock.json")
    )
    private var _lockPositions = false

    private struct IconSizeSelection {
        let dockID: UUID
        let size: Double
    }

    func applicationDidFinishLaunching(_: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let image = NSImage(systemSymbolName: "square.grid.3x3", accessibilityDescription: "FreeDock") {
            statusItem?.button?.image = image
        } else {
            statusItem?.button?.title = "FD"
        }

        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL)
        {
            NSApp.applicationIconImage = icon
        }

        rebuildMenu()
        restoreDocks()
        if configManager.config.docks.isEmpty {
            createInitialSeededDock()
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_: Notification) {
        saveAllPositions()
        configManager.saveImmediately()
    }

    @objc func rebuildMenu() {
        let menu = NSMenu()
        let newSub = NSMenu()
        newSub.addItem(NSMenuItem(title: "Horizontal", action: #selector(newHorizontalDock), keyEquivalent: ""))
        newSub.addItem(NSMenuItem(title: "Vertical", action: #selector(newVerticalDock), keyEquivalent: ""))
        let newItem = NSMenuItem(title: "New Dock", action: nil, keyEquivalent: "n")
        newItem.submenu = newSub
        menu.addItem(newItem)

        if !configManager.config.docks.isEmpty {
            menu.addItem(.separator())
            for dock in configManager.config.docks {
                let dockMenu = NSMenu()

                let renameItem = NSMenuItem(
                    title: "Rename…",
                    action: #selector(renameDock(_:)),
                    keyEquivalent: ""
                )
                renameItem.representedObject = dock.id
                dockMenu.addItem(renameItem)

                dockMenu.addItem(.separator())

                let toggle = NSMenuItem(
                    title: dockPanels[dock.id] != nil ? "Hide Dock" : "Show Dock",
                    action: #selector(toggleDock(_:)),
                    keyEquivalent: ""
                )
                toggle.representedObject = dock.id
                dockMenu.addItem(toggle)

                dockMenu.addItem(.separator())

                let iconMenu = NSMenu()

                for size in [16.0, 24.0, 32.0, 48.0, 64.0, 80.0, 96.0, 128.0] {
                    let sizeItem = NSMenuItem(
                        title: "\(Int(size)) px",
                        action: #selector(changeIconSize(_:)),
                        keyEquivalent: ""
                    )

                    sizeItem.state = dock.iconSize == size ? NSControl.StateValue.on : NSControl.StateValue.off
                    sizeItem.representedObject = IconSizeSelection(
                        dockID: dock.id,
                        size: size
                    )

                    iconMenu.addItem(sizeItem)
                }

                let iconItem = NSMenuItem(title: "Icon Size", action: nil, keyEquivalent: "")
                iconItem.submenu = iconMenu
                dockMenu.addItem(iconItem)

                let root = NSMenuItem(title: dock.name, action: nil, keyEquivalent: "")
                root.submenu = dockMenu

                menu.addItem(root)
            }
        }

        let dockRemoveSub = NSMenu()
        for dock in configManager.config.docks {
            let item = NSMenuItem(title: dock.name, action: #selector(deleteDock(_:)), keyEquivalent: "")
            item.representedObject = dock.id
            dockRemoveSub.addItem(item)
        }
        let removeItem = NSMenuItem(title: "Delete Dock", action: nil, keyEquivalent: "")
        removeItem.submenu = dockRemoveSub
        removeItem.isEnabled = !configManager.config.docks.isEmpty
        menu.addItem(removeItem)

        menu.addItem(.separator())
        let lockItem = NSMenuItem(title: "Lock Dock Positions", action: #selector(toggleLockPositions), keyEquivalent: "l")
        lockItem.state = _lockPositions ? .on : .off
        menu.addItem(lockItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit FreeDock", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    private let snapDistance: CGFloat = 15

    private func snapFrame(_ frame: NSRect) -> NSRect {
        guard let screen = NSScreen.main else { return frame }

        let visible = screen.visibleFrame
        var snapped = frame

        if abs(frame.minX - visible.minX) < snapDistance {
            snapped.origin.x = visible.minX
        }

        if abs(frame.maxX - visible.maxX) < snapDistance {
            snapped.origin.x = visible.maxX - frame.width
        }

        if abs(frame.minY - visible.minY) < snapDistance {
            snapped.origin.y = visible.minY
        }

        if abs(frame.maxY - visible.maxY) < snapDistance {
            snapped.origin.y = visible.maxY - frame.height
        }

        return snapped
    }

    @objc private func newHorizontalDock() {
        createDock(orientation: .horizontal)
    }

    @objc private func newVerticalDock() {
        createDock(orientation: .vertical)
    }

    private var defaultDockPosition: CGPoint {
        let visibleFrame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? NSRect(x: 100, y: 100, width: 1200, height: 800)
        return CGPoint(x: visibleFrame.midX - 150, y: visibleFrame.midY - 30)
    }

    private func createDock(orientation: Orientation) {
        let dock = DockConfig(name: "Dock \(configManager.config.docks.count + 1)", position: defaultDockPosition, orientation: orientation)
        configManager.config.docks.append(dock)
        showDock(dock)
        configManager.save()
        rebuildMenu()
    }

    private func createInitialSeededDock() {
        let dock = DockConfig(name: "Dock 1", position: defaultDockPosition, orientation: .horizontal, items: seededDockItems())
        configManager.config.docks.append(dock)
        showDock(dock)
        configManager.save()
        rebuildMenu()
    }

    private func seededDockItems() -> [DockItem] {
        [
            "/Applications/Safari.app",
            "/Applications/Google Chrome.app",
            "/Applications/Calculator.app",
            "/Applications/Notes.app",
            "/System/Applications/Utilities/Terminal.app",
        ]
        .filter { FileManager.default.fileExists(atPath: $0) }
        .prefix(4)
        .map { path in DockItem(appPath: path, label: AppInfo.resolve(from: path).displayName) }
    }

    @objc private func toggleDock(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        if let panel = dockPanels[id] {
            panel.orderOut(nil)
            dockPanels.removeValue(forKey: id)
        } else if let config = configManager.config.docks.first(where: { $0.id == id }) {
            showDock(config)
        }
        rebuildMenu()
    }

    @objc private func deleteDock(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        dockPanels[id]?.close()
        dockPanels.removeValue(forKey: id)
        configManager.config.docks.removeAll(where: { $0.id == id })
        configManager.save()
        rebuildMenu()
    }

    @objc private func toggleLockPositions() {
        _lockPositions.toggle()
        rebuildMenu()
    }

    @objc private func renameDock(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID,
              let idx = configManager.config.docks.firstIndex(where: { $0.id == id }) else { return }

        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.messageText = "Rename Dock"
        alert.informativeText = "Enter a new name for the dock:"

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        field.stringValue = configManager.config.docks[idx].name
        alert.accessoryView = field

        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            let newName = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !newName.isEmpty else { return }

            configManager.config.docks[idx].name = newName
            configManager.save()
            rebuildMenu()
        }
    }

    @objc private func changeIconSize(_ sender: NSMenuItem) {
        guard let selection = sender.representedObject as? IconSizeSelection,
              let index = configManager.config.docks.firstIndex(where: { $0.id == selection.dockID })
        else {
            return
        }

        configManager.config.docks[index].iconSize = selection.size
        configManager.save()

        if let panel = dockPanels[selection.dockID] {
            panel.close()
            dockPanels.removeValue(forKey: selection.dockID)
        }

        showDock(configManager.config.docks[index])
        rebuildMenu()
    }

    private func showDock(_ config: DockConfig) {
        let rect = NSRect(origin: config.position,
                          size: NSSize(width: 400, height: 70))
        let panel = DockPanel(dockID: config.id, contentRect: rect)
        panel.clampToVisibleFrame()

        let dockID = config.id
        let content = DockContentView(
            panel: panel,
            items: Binding(
                get: { self.configManager.config.docks.first(where: { $0.id == dockID })?.items ?? [] },
                set: { newItems in
                    guard let idx = self.configManager.config.docks.firstIndex(where: { $0.id == dockID }) else { return }
                    self.configManager.config.docks[idx].items = newItems
                }
            ),
            orientation: config.orientation,
            iconSize: config.iconSize,
            onItemsChanged: { _ in
                self.configManager.save()
                DispatchQueue.main.async { panel.resizeToFitContent() }
            },
            onAppLaunch: { item in NSWorkspace.shared.open(URL(fileURLWithPath: item.appPath)) }
        )

        panel.dockOrientation = config.orientation
        panel.setContentView(content)
        panel.dockDelegate = self
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        dockPanels[config.id] = panel
    }

    private func restoreDocks() {
        for dock in configManager.config.docks {
            showDock(dock)
        }
    }

    private func saveAllPositions() {
        for (id, panel) in dockPanels {
            guard let idx = configManager.config.docks.firstIndex(where: { $0.id == id }) else { continue }
            configManager.config.docks[idx].position = panel.frame.origin
        }
    }
}

extension AppDelegate: DockPanelDelegate {
    var lockPositions: Bool {
        get { _lockPositions }
        set { _lockPositions = newValue }
    }

    func dockPanelDidMove(_ panel: DockPanel) {
        let snapped = snapFrame(panel.frame)

        if snapped.origin != panel.frame.origin {
            panel.setFrame(snapped, display: true, animate: true)
        }

        guard let idx = configManager.config.docks.firstIndex(where: { $0.id == panel.dockID }) else { return }

        configManager.config.docks[idx].position = snapped.origin
        configManager.save()
    }
}
