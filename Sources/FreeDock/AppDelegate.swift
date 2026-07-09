import Cocoa
import SwiftUI

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var dockPanels: [UUID: DockPanel] = [:]
    private let configManager = ConfigManager(
        configPath: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/freedock.json")
    )
    private var _lockPositions = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.image = NSImage(systemSymbolName: "square.grid.3x3", accessibilityDescription: "FreeDock")
        rebuildMenu()
        restoreDocks()
    }

    func applicationWillTerminate(_ notification: Notification) {
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
                let item = NSMenuItem(title: dock.name, action: #selector(toggleDock(_:)), keyEquivalent: "")
                item.representedObject = dock.id
                item.state = (dockPanels[dock.id] != nil) ? .on : .off
                menu.addItem(item)
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

    @objc private func newHorizontalDock() { createDock(orientation: .horizontal) }
    @objc private func newVerticalDock() { createDock(orientation: .vertical) }

    private func createDock(orientation: Orientation) {
        guard let screen = NSScreen.main else { return }
        let pos = CGPoint(x: screen.visibleFrame.midX - 150, y: screen.visibleFrame.midY - 30)
        let dock = DockConfig(name: "Dock \(configManager.config.docks.count + 1)", position: pos, orientation: orientation)
        configManager.config.docks.append(dock)
        showDock(dock)
        configManager.save()
        rebuildMenu()
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

    private func showDock(_ config: DockConfig) {
        let rect = NSRect(origin: config.position, size: NSSize(width: 280, height: 64))
        let panel = DockPanel(dockID: config.id, contentRect: rect)
        panel.clampToVisibleFrame()
        panel.setContentView(
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial)
                Text("Drag apps here").foregroundColor(.secondary).font(.caption)
            }
            .frame(minWidth: 120, minHeight: 40)
        )
        panel.orderFront(nil)
        dockPanels[config.id] = panel
    }

    private func restoreDocks() {
        for dock in configManager.config.docks { showDock(dock) }
    }

    private func saveAllPositions() {
        for (id, panel) in dockPanels {
            guard let idx = configManager.config.docks.firstIndex(where: { $0.id == id }) else { continue }
            configManager.config.docks[idx].position = panel.frame.origin
        }
    }
}
