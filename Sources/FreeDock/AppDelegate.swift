import Cocoa
import SwiftUI

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var dockPanels: [UUID: DockPanel] = [:]
    private let shortcutManager = GlobalShortcutManager()
    private let configManager = ConfigManager(
        configPath: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/freedock.json")
    )
    private var _lockPositions = false
    private var dockStates: [UUID: DockState] = [:]
    private var preferencesStore: DockPreferencesStore?
    private var preferencesWindowController: PreferencesWindowController?
    private var menuRefreshWorkItem: DispatchWorkItem?
    private var dockResizeWorkItems: [UUID: DispatchWorkItem] = [:]
    private var pendingAutoHideUpdates: [UUID: (enabled: Bool, orientation: Orientation)] = [:]

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

        restoreDocks()
        if !configManager.loadedFromDisk, configManager.config.docks.isEmpty {
            createInitialSeededDock()
        }
        rebuildMenu()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_: Notification) {
        saveAllPositions()
        configManager.saveImmediately()
    }

    @objc func rebuildMenu() {
        let menu = NSMenu()

        let profileMenu = NSMenu()
        for (index, profile) in configManager.config.profiles.enumerated() {
            let profileItem = NSMenuItem(
                title: profile.name,
                action: #selector(switchProfile(_:)),
                keyEquivalent: index < 9 ? "\(index + 1)" : ""
            )
            profileItem.representedObject = profile.id
            profileItem.state = profile.id == configManager.config.activeProfileID ? .on : .off
            if index < 9 {
                profileItem.keyEquivalentModifierMask = [.control, .option]
            }
            profileMenu.addItem(profileItem)
        }
        profileMenu.addItem(.separator())
        profileMenu.addItem(NSMenuItem(
            title: "New Profile…",
            action: #selector(createProfile),
            keyEquivalent: ""
        ))
        profileMenu.addItem(NSMenuItem(
            title: "Rename Current Profile…",
            action: #selector(renameCurrentProfile),
            keyEquivalent: ""
        ))
        let deleteProfileItem = NSMenuItem(
            title: "Delete Current Profile…",
            action: #selector(deleteCurrentProfile),
            keyEquivalent: ""
        )
        deleteProfileItem.isEnabled = configManager.config.profiles.count > 1
        profileMenu.addItem(deleteProfileItem)

        let profileRoot = NSMenuItem(
            title: "Profile: \(configManager.config.activeProfileName)",
            action: nil,
            keyEquivalent: ""
        )
        profileRoot.submenu = profileMenu
        menu.addItem(profileRoot)

        let toggleProfileItem = NSMenuItem(
            title: dockPanels.isEmpty ? "Show Active Profile" : "Hide Active Profile",
            action: #selector(toggleActiveProfileDocks),
            keyEquivalent: " "
        )
        toggleProfileItem.keyEquivalentModifierMask = [.control, .option]
        toggleProfileItem.isEnabled = !configManager.config.docks.isEmpty
        menu.addItem(toggleProfileItem)
        menu.addItem(.separator())

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

                let autoHideItem = NSMenuItem(
                    title: "Auto-Hide at Screen Edge",
                    action: #selector(toggleDockAutoHide(_:)),
                    keyEquivalent: ""
                )
                autoHideItem.representedObject = dock.id
                autoHideItem.state = dock.autoHideWhenDocked ? .on : .off
                dockMenu.addItem(autoHideItem)

                let dockToEdgeItem = NSMenuItem(
                    title: "Dock to Nearest Screen Edge",
                    action: #selector(dockToNearestEdge(_:)),
                    keyEquivalent: ""
                )
                dockToEdgeItem.representedObject = dock.id
                dockToEdgeItem.isEnabled = dockPanels[dock.id] != nil
                dockMenu.addItem(dockToEdgeItem)

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
        let preferencesItem = NSMenuItem(
            title: "Preferences…",
            action: #selector(showPreferences),
            keyEquivalent: ","
        )
        preferencesItem.keyEquivalentModifierMask = [.command]
        preferencesItem.target = self
        menu.addItem(preferencesItem)

        menu.addItem(.separator())
        let lockItem = NSMenuItem(title: "Lock Dock Positions", action: #selector(toggleLockPositions), keyEquivalent: "l")
        lockItem.state = _lockPositions ? .on : .off
        menu.addItem(lockItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit FreeDock", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu
        configureGlobalShortcuts()
        refreshPreferencesSnapshot()
    }

    @objc private func showPreferences() {
        if preferencesStore == nil {
            let store = DockPreferencesStore(
                profiles: configManager.config.profiles,
                activeProfileID: configManager.config.activeProfileID
            ) { [weak self] dockID, change in
                self?.applyDockPreference(change, to: dockID)
            } onManagementAction: { [weak self] action in
                self?.handleDockManagementAction(action)
            }
            preferencesStore = store
            preferencesWindowController = PreferencesWindowController(store: store)
        }

        refreshPreferencesSnapshot()
        preferencesWindowController?.show()
    }

    private func refreshPreferencesSnapshot() {
        preferencesStore?.reload(
            profiles: configManager.config.profiles,
            activeProfileID: configManager.config.activeProfileID
        )
    }

    private func handleDockManagementAction(_ action: DockManagementAction) {
        switch action {
        case let .activateProfile(profileID):
            activateProfile(profileID)
        case .createProfile:
            createProfile()
        case .renameActiveProfile:
            renameCurrentProfile()
        case .deleteActiveProfile:
            deleteCurrentProfile()
        case let .createDock(orientation):
            createDock(orientation: orientation)
        case let .renameDock(dockID):
            promptToRenameDock(dockID)
        case let .duplicateDock(dockID):
            duplicateDock(dockID)
        case let .deleteDock(dockID):
            confirmAndDeleteDock(dockID)
        case let .resetDockSettings(dockID):
            confirmAndResetDockSettings(dockID)
        case let .copyDockSettingsToAll(dockID):
            confirmAndCopyDockSettingsToAll(dockID)
        }

        DispatchQueue.main.async { [weak self] in
            self?.preferencesWindowController?.show()
        }
    }

    private func scheduleMenuRefresh() {
        menuRefreshWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.rebuildMenu()
        }
        menuRefreshWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
    }

    private let snapDistance: CGFloat = 15

    private func snapFrame(_ frame: NSRect) -> NSRect {
        let center = NSPoint(x: frame.midX, y: frame.midY)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(center) }) ?? NSScreen.main else { return frame }

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

    private func frameDockedToNearestEdge(_ frame: NSRect, orientation: Orientation) -> NSRect {
        let center = NSPoint(x: frame.midX, y: frame.midY)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(center) }) ?? NSScreen.main else { return frame }

        let visible = screen.visibleFrame
        var docked = frame

        if orientation == .horizontal {
            let distanceToBottom = abs(frame.minY - visible.minY)
            let distanceToTop = abs(frame.maxY - visible.maxY)
            docked.origin.y = distanceToBottom <= distanceToTop
                ? visible.minY
                : visible.maxY - frame.height
            docked.origin.x = min(max(frame.origin.x, visible.minX), visible.maxX - frame.width)
        } else {
            let distanceToLeft = abs(frame.minX - visible.minX)
            let distanceToRight = abs(frame.maxX - visible.maxX)
            docked.origin.x = distanceToLeft <= distanceToRight
                ? visible.minX
                : visible.maxX - frame.width
            docked.origin.y = min(max(frame.origin.y, visible.minY), visible.maxY - frame.height)
        }

        return docked
    }

    @objc private func switchProfile(_ sender: NSMenuItem) {
        guard let profileID = sender.representedObject as? UUID else { return }
        activateProfile(profileID)
    }

    private func activateProfile(_ profileID: UUID) {
        guard profileID != configManager.config.activeProfileID,
              configManager.config.profiles.contains(where: { $0.id == profileID })
        else { return }

        saveAllPositions()
        closeAllDockPanels()
        configManager.config.activeProfileID = profileID
        restoreDocks()
        configManager.save()
        rebuildMenu()
    }

    @objc private func toggleActiveProfileDocks() {
        if dockPanels.isEmpty {
            restoreDocks()
        } else {
            saveAllPositions()
            closeAllDockPanels()
        }
        configManager.save()
        rebuildMenu()
    }

    private func configureGlobalShortcuts() {
        shortcutManager.reset()
        shortcutManager.register(id: 1, keyCode: GlobalShortcutManager.showHideKeyCode) { [weak self] in
            self?.toggleActiveProfileDocks()
        }

        for (index, profile) in configManager.config.profiles.prefix(9).enumerated() {
            shortcutManager.register(
                id: UInt32(index + 2),
                keyCode: GlobalShortcutManager.profileKeyCodes[index]
            ) { [weak self] in
                self?.activateProfile(profile.id)
            }
        }
    }

    @objc private func createProfile() {
        guard let name = promptForProfileName(
            title: "New Profile",
            message: "Create a separate set of docks for a workflow.",
            initialValue: suggestedProfileName()
        ) else { return }

        saveAllPositions()
        closeAllDockPanels()

        let starterDock = DockConfig(
            name: "Dock 1",
            position: defaultDockPosition,
            orientation: .horizontal,
            autoHideWhenDocked: false
        )
        let profile = DockProfile(name: name, docks: [starterDock])
        configManager.config.profiles.append(profile)
        configManager.config.activeProfileID = profile.id
        restoreDocks()
        configManager.save()
        rebuildMenu()
    }

    @objc private func renameCurrentProfile() {
        let profileID = configManager.config.activeProfileID
        guard let index = configManager.config.profiles.firstIndex(where: { $0.id == profileID }),
              let name = promptForProfileName(
                  title: "Rename Profile",
                  message: "Choose a name for this dock profile.",
                  initialValue: configManager.config.profiles[index].name,
                  excluding: profileID
              )
        else { return }

        configManager.config.profiles[index].name = name
        configManager.save()
        rebuildMenu()
    }

    @objc private func deleteCurrentProfile() {
        guard configManager.config.profiles.count > 1,
              let index = configManager.config.profiles.firstIndex(where: {
                  $0.id == configManager.config.activeProfileID
              })
        else { return }

        let profile = configManager.config.profiles[index]
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.alertStyle = .warning
        alert.messageText = "Delete “\(profile.name)”?"
        alert.informativeText = profile.docks.isEmpty
            ? "This profile is empty."
            : "This permanently removes \(profile.docks.count) dock\(profile.docks.count == 1 ? "" : "s") from the profile."
        alert.addButton(withTitle: "Cancel")
        let deleteButton = alert.addButton(withTitle: "Delete")
        deleteButton.hasDestructiveAction = true
        guard alert.runModal() == .alertSecondButtonReturn else { return }

        saveAllPositions()
        closeAllDockPanels()
        configManager.config.profiles.remove(at: index)
        let nextIndex = min(index, configManager.config.profiles.count - 1)
        configManager.config.activeProfileID = configManager.config.profiles[nextIndex].id
        restoreDocks()
        configManager.save()
        rebuildMenu()
    }

    private func promptForProfileName(
        title: String,
        message: String,
        initialValue: String,
        excluding excludedID: UUID? = nil
    ) -> String? {
        var proposedValue = initialValue

        while true {
            let alert = NSAlert()
            alert.icon = NSApp.applicationIconImage
            alert.messageText = title
            alert.informativeText = message

            let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
            field.stringValue = proposedValue
            field.selectText(nil)
            alert.accessoryView = field
            alert.addButton(withTitle: "Save")
            alert.addButton(withTitle: "Cancel")

            guard alert.runModal() == .alertFirstButtonReturn else { return nil }
            proposedValue = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

            if proposedValue.isEmpty {
                showProfileNameError("Profile names cannot be empty.")
                continue
            }

            let isDuplicate = configManager.config.profiles.contains {
                $0.id != excludedID
                    && $0.name.compare(proposedValue, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }
            if isDuplicate {
                showProfileNameError("A profile named “\(proposedValue)” already exists.")
                continue
            }

            return proposedValue
        }
    }

    private func showProfileNameError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Choose Another Name"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func suggestedProfileName() -> String {
        let base = "Profile"
        var number = configManager.config.profiles.count + 1
        var candidate = "\(base) \(number)"
        let existing = Set(configManager.config.profiles.map { $0.name.lowercased() })

        while existing.contains(candidate.lowercased()) {
            number += 1
            candidate = "\(base) \(number)"
        }
        return candidate
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
        let dock = DockConfig(
            name: suggestedDockName(),
            position: defaultDockPosition,
            orientation: orientation
        )
        configManager.config.docks.append(dock)
        showDock(dock)
        configManager.save()
        rebuildMenu()
        preferencesStore?.selectedDockID = dock.id
    }

    private func suggestedDockName() -> String {
        let existing = Set(configManager.config.docks.map { $0.name.lowercased() })
        var number = 1
        var candidate = "Dock \(number)"

        while existing.contains(candidate.lowercased()) {
            number += 1
            candidate = "Dock \(number)"
        }
        return candidate
    }

    private func suggestedDuplicateName(for sourceName: String) -> String {
        let existing = Set(configManager.config.docks.map { $0.name.lowercased() })
        let base = "\(sourceName) Copy"
        var candidate = base
        var number = 2

        while existing.contains(candidate.lowercased()) {
            candidate = "\(base) \(number)"
            number += 1
        }
        return candidate
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
            dockResizeWorkItems[id]?.cancel()
            dockResizeWorkItems.removeValue(forKey: id)
            pendingAutoHideUpdates.removeValue(forKey: id)
            panel.tearDown()
            dockPanels.removeValue(forKey: id)
            dockStates.removeValue(forKey: id)
        } else if let config = configManager.config.docks.first(where: { $0.id == id }) {
            showDock(config)
        }
        rebuildMenu()
    }

    @objc private func deleteDock(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        confirmAndDeleteDock(id)
    }

    private func confirmAndDeleteDock(_ id: UUID) {
        guard let dock = configManager.config.docks.first(where: { $0.id == id }) else { return }

        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.alertStyle = .warning
        alert.messageText = "Delete “\(dock.name)”?"
        alert.informativeText = "This removes the dock from the current profile. The apps themselves will not be deleted."
        alert.addButton(withTitle: "Cancel")
        let deleteButton = alert.addButton(withTitle: "Delete")
        deleteButton.hasDestructiveAction = true
        guard alert.runModal() == .alertSecondButtonReturn else { return }

        performDeleteDock(id)
    }

    private func performDeleteDock(_ id: UUID) {
        dockResizeWorkItems[id]?.cancel()
        dockResizeWorkItems.removeValue(forKey: id)
        pendingAutoHideUpdates.removeValue(forKey: id)
        dockPanels[id]?.tearDown()
        dockPanels.removeValue(forKey: id)
        dockStates.removeValue(forKey: id)
        configManager.config.docks.removeAll(where: { $0.id == id })
        configManager.save()
        rebuildMenu()
    }

    @objc private func toggleLockPositions() {
        _lockPositions.toggle()
        for panel in dockPanels.values {
            panel.isMovableByWindowBackground = !_lockPositions
        }
        rebuildMenu()
    }

    @objc private func toggleDockAutoHide(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID,
              let dock = configManager.config.docks.first(where: { $0.id == id })
        else { return }

        applyDockPreference(
            .autoHideWhenDocked(!dock.autoHideWhenDocked),
            to: id
        )
    }

    @objc private func dockToNearestEdge(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        dockPanelToNearestEdge(id)
    }

    private func dockPanelToNearestEdge(_ id: UUID) {
        guard let index = configManager.config.docks.firstIndex(where: { $0.id == id }),
              let panel = dockPanels[id]
        else { return }

        panel.revealImmediately()
        let dockedFrame = frameDockedToNearestEdge(
            panel.frameForPersistence,
            orientation: configManager.config.docks[index].orientation
        )
        panel.setFrame(dockedFrame, display: true, animate: true)
        configManager.config.docks[index].position = dockedFrame.origin
        configManager.save()
        refreshPreferencesSnapshot()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak panel] in
            panel?.updateAutoHideEdge()
            panel?.scheduleAutoHide()
        }
    }

    @objc private func renameDock(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        promptToRenameDock(id)
    }

    private func promptToRenameDock(_ id: UUID) {
        guard let idx = configManager.config.docks.firstIndex(where: { $0.id == id }) else { return }
        var proposedValue = configManager.config.docks[idx].name

        while true {
            let alert = NSAlert()
            alert.icon = NSApp.applicationIconImage
            alert.messageText = "Rename Dock"
            alert.informativeText = "Enter a new name for the dock:"

            let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
            field.stringValue = proposedValue
            field.selectText(nil)
            alert.accessoryView = field

            alert.addButton(withTitle: "Save")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }

            proposedValue = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if proposedValue.isEmpty {
                showDockNameError("Dock names cannot be empty.")
                continue
            }

            let isDuplicate = configManager.config.docks.contains {
                $0.id != id
                    && $0.name.compare(
                        proposedValue,
                        options: [.caseInsensitive, .diacriticInsensitive]
                    ) == .orderedSame
            }
            if isDuplicate {
                showDockNameError("A dock named “\(proposedValue)” already exists in this profile.")
                continue
            }

            guard let currentIndex = configManager.config.docks.firstIndex(where: { $0.id == id }) else { return }
            configManager.config.docks[currentIndex].name = proposedValue
            configManager.save()
            rebuildMenu()
            return
        }
    }

    private func showDockNameError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Choose Another Dock Name"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func duplicateDock(_ id: UUID) {
        saveAllPositions()
        guard let sourceIndex = configManager.config.docks.firstIndex(where: { $0.id == id }) else { return }
        let source = configManager.config.docks[sourceIndex]

        var duplicatedPosition = source.position
        if source.orientation == .horizontal {
            duplicatedPosition.x += 32
        } else {
            duplicatedPosition.y -= 32
        }

        let duplicate = source.duplicated(
            name: suggestedDuplicateName(for: source.name),
            position: duplicatedPosition
        )

        configManager.config.docks.insert(duplicate, at: sourceIndex + 1)
        showDock(duplicate)
        configManager.save()
        rebuildMenu()
        preferencesStore?.selectedDockID = duplicate.id
    }

    private func confirmAndResetDockSettings(_ id: UUID) {
        guard let dock = configManager.config.docks.first(where: { $0.id == id }) else { return }

        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.alertStyle = .warning
        alert.messageText = "Reset settings for “\(dock.name)”?"
        alert.informativeText = "Appearance, icon layout, orientation, indicators, and auto-hide will return to their defaults. The dock’s name, pinned apps, and saved position will stay unchanged."
        alert.addButton(withTitle: "Cancel")
        let resetButton = alert.addButton(withTitle: "Reset")
        resetButton.hasDestructiveAction = true
        guard alert.runModal() == .alertSecondButtonReturn else { return }

        applyDockSettings(DockConfig.defaultSettings, to: [id])
    }

    private func confirmAndCopyDockSettingsToAll(_ sourceID: UUID) {
        let docks = configManager.config.docks
        guard let source = docks.first(where: { $0.id == sourceID }) else { return }
        let targetIDs = docks.filter { $0.id != sourceID }.map(\.id)
        guard !targetIDs.isEmpty else { return }

        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.messageText = "Copy “\(source.name)” settings?"
        alert.informativeText = "This replaces the visible settings on \(targetIDs.count) other dock\(targetIDs.count == 1 ? "" : "s") in the current profile. Dock names, pinned apps, and saved positions will stay unchanged."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Copy")
        guard alert.runModal() == .alertSecondButtonReturn else { return }

        applyDockSettings(source.settings, to: Set(targetIDs))
    }

    private func applyDockSettings(_ settings: DockSettings, to targetIDs: Set<UUID>) {
        var docks = configManager.config.docks
        var transitions: [(previous: DockConfig, updated: DockConfig)] = []

        for index in docks.indices where targetIDs.contains(docks[index].id) {
            let previous = docks[index]
            docks[index].apply(settings: settings)
            if docks[index] != previous {
                transitions.append((previous, docks[index]))
            }
        }

        guard !transitions.isEmpty else { return }
        configManager.config.docks = docks

        for transition in transitions {
            reconcileDockRuntime(from: transition.previous, to: transition.updated)
        }

        configManager.save()
        rebuildMenu()
    }

    @objc private func changeIconSize(_ sender: NSMenuItem) {
        guard let selection = sender.representedObject as? IconSizeSelection else { return }

        applyDockPreference(.iconSize(selection.size), to: selection.dockID)
    }

    private func applyDockPreference(_ change: DockPreferenceChange, to dockID: UUID) {
        var docks = configManager.config.docks
        guard let index = docks.firstIndex(where: { $0.id == dockID }) else { return }

        let previous = docks[index]
        docks[index].apply(change)
        let updated = docks[index]
        configManager.config.docks = docks
        preferencesStore?.replaceDock(updated)
        reconcileDockRuntime(from: previous, to: updated)

        configManager.save()
        refreshPreferencesSnapshot()

        switch change {
        case .iconSize, .autoHideWhenDocked:
            scheduleMenuRefresh()
        case .orientation, .magnification, .itemSpacing, .appearance,
             .cornerRadius, .showRunningIndicators, .autoHideDelay:
            break
        }
    }

    private func reconcileDockRuntime(from previous: DockConfig, to updated: DockConfig) {
        let dockID = updated.id
        guard previous != updated else { return }

        if previous.orientation != updated.orientation {
            rebuildVisibleDock(dockID, using: updated)
            return
        }

        dockStates[dockID]?.apply(updated)
        if let panel = dockPanels[dockID] {
            panel.autoHideDelay = updated.autoHideDelay
        }

        let geometryChanged = previous.iconSize != updated.iconSize
            || previous.magnification != updated.magnification
            || previous.itemSpacing != updated.itemSpacing
        let autoHideChanged = previous.autoHideWhenDocked != updated.autoHideWhenDocked

        if geometryChanged {
            if autoHideChanged, dockPanels[dockID] != nil {
                pendingAutoHideUpdates[dockID] = (
                    enabled: updated.autoHideWhenDocked,
                    orientation: updated.orientation
                )
            }
            scheduleDockResize(dockID)
        } else if autoHideChanged {
            updateAutoHideRuntime(
                for: dockID,
                enabled: updated.autoHideWhenDocked,
                orientation: updated.orientation
            )
        } else if previous.autoHideDelay != updated.autoHideDelay {
            dockPanels[dockID]?.scheduleAutoHide()
        }
    }

    private func scheduleDockResize(_ dockID: UUID) {
        guard let panel = dockPanels[dockID] else { return }

        panel.revealImmediately()
        dockResizeWorkItems[dockID]?.cancel()

        let work = DispatchWorkItem { [weak self, weak panel] in
            guard let self else { return }
            guard let panel else {
                self.pendingAutoHideUpdates.removeValue(forKey: dockID)
                self.dockResizeWorkItems.removeValue(forKey: dockID)
                return
            }
            panel.resizeToFitContent()

            if self.pendingAutoHideUpdates[dockID] == nil {
                panel.updateAutoHideEdge()
                if panel.autoHideWhenDocked {
                    panel.scheduleAutoHide()
                }
            }

            if let index = self.configManager.config.docks.firstIndex(where: { $0.id == dockID }) {
                self.configManager.config.docks[index].position = panel.frameForPersistence.origin
                self.configManager.save()
            }
            self.dockResizeWorkItems.removeValue(forKey: dockID)

            if let pending = self.pendingAutoHideUpdates.removeValue(forKey: dockID) {
                self.updateAutoHideRuntime(
                    for: dockID,
                    enabled: pending.enabled,
                    orientation: pending.orientation
                )
            }
        }
        dockResizeWorkItems[dockID] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.035, execute: work)
    }

    private func updateAutoHideRuntime(
        for dockID: UUID,
        enabled: Bool,
        orientation: Orientation
    ) {
        guard let panel = dockPanels[dockID] else { return }

        panel.autoHideWhenDocked = enabled
        guard enabled else { return }

        panel.revealImmediately()
        let dockedFrame = frameDockedToNearestEdge(
            panel.frameForPersistence,
            orientation: orientation
        )
        panel.setFrame(dockedFrame, display: true, animate: true)
        if let index = configManager.config.docks.firstIndex(where: { $0.id == dockID }) {
            configManager.config.docks[index].position = dockedFrame.origin
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak panel] in
            panel?.updateAutoHideEdge()
            panel?.scheduleAutoHide()
        }
    }

    private func rebuildVisibleDock(_ dockID: UUID, using config: DockConfig) {
        guard let panel = dockPanels[dockID] else { return }

        dockResizeWorkItems[dockID]?.cancel()
        dockResizeWorkItems.removeValue(forKey: dockID)
        pendingAutoHideUpdates.removeValue(forKey: dockID)
        let visibleOrigin = panel.frameForPersistence.origin
        panel.revealImmediately()
        panel.tearDown()
        dockPanels.removeValue(forKey: dockID)
        dockStates.removeValue(forKey: dockID)

        var rebuiltConfig = config
        rebuiltConfig.position = visibleOrigin
        if let index = configManager.config.docks.firstIndex(where: { $0.id == dockID }) {
            configManager.config.docks[index].position = visibleOrigin
        }
        showDock(rebuiltConfig)
    }

    private func showDock(_ config: DockConfig) {
        let rect = NSRect(origin: config.position,
                          size: NSSize(width: 400, height: 70))
        let panel = DockPanel(dockID: config.id, contentRect: rect)
        panel.clampToVisibleFrame()

        let dockID = config.id
        let state = DockState(config: config)
        dockStates[config.id] = state

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
            state: state,
            onItemsChanged: { _ in
                self.configManager.save()
                DispatchQueue.main.async { panel.resizeToFitContent() }
            },
            onAppLaunch: { item in NSWorkspace.shared.open(URL(fileURLWithPath: item.appPath)) }
        )

        panel.dockOrientation = config.orientation
        panel.autoHideDelay = config.autoHideDelay
        panel.autoHideWhenDocked = config.autoHideWhenDocked
        panel.setContentView(content)
        panel.dockDelegate = self
        panel.isMovableByWindowBackground = !_lockPositions
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        panel.clampToVisibleFrame()

        if config.autoHideWhenDocked {
            let dockedFrame = frameDockedToNearestEdge(panel.frame, orientation: config.orientation)
            panel.setFrame(dockedFrame, display: true)
            if let index = configManager.config.docks.firstIndex(where: { $0.id == config.id }) {
                configManager.config.docks[index].position = dockedFrame.origin
            }
            panel.updateAutoHideEdge()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak panel] in
                panel?.scheduleAutoHide()
            }
        }
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
            configManager.config.docks[idx].position = panel.frameForPersistence.origin
        }
    }

    private func closeAllDockPanels() {
        TooltipManager.shared.hide()
        for work in dockResizeWorkItems.values {
            work.cancel()
        }
        dockResizeWorkItems.removeAll()
        pendingAutoHideUpdates.removeAll()
        for panel in dockPanels.values {
            panel.tearDown()
        }
        dockPanels.removeAll()
        dockStates.removeAll()
    }
}

extension AppDelegate: DockPanelDelegate {
    var lockPositions: Bool {
        get { _lockPositions }
        set { _lockPositions = newValue }
    }

    func dockPanelDidMove(_ panel: DockPanel) {
        let snapped = panel.autoHideWhenDocked
            ? frameDockedToNearestEdge(panel.frame, orientation: panel.dockOrientation)
            : snapFrame(panel.frame)

        if snapped.origin != panel.frame.origin {
            panel.setFrame(snapped, display: true, animate: true)
        }

        panel.updateAutoHideEdge()

        guard let idx = configManager.config.docks.firstIndex(where: { $0.id == panel.dockID }) else { return }

        configManager.config.docks[idx].position = snapped.origin
        configManager.save()
    }

    func currentIconSize(for panel: DockPanel) -> Double {
        dockStates[panel.dockID]?.iconSize ?? 48
    }

    func dockPanelDidResize(_ panel: DockPanel, proposedIconSize: Double) {
        applyDockPreference(.iconSize(proposedIconSize), to: panel.dockID)
    }

    func dockPanelDidFinishResize(_ panel: DockPanel) {
        guard let idx = configManager.config.docks.firstIndex(where: { $0.id == panel.dockID }) else { return }

        let snapped = snapFrame(panel.frame)
        if snapped.origin != panel.frame.origin {
            panel.setFrame(snapped, display: true, animate: true)
        }
        panel.updateAutoHideEdge()
        configManager.config.docks[idx].position = panel.frameForPersistence.origin
        configManager.save()
        refreshPreferencesSnapshot()
        scheduleMenuRefresh()
    }
}
