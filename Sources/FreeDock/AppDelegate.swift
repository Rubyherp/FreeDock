import Cocoa
import Carbon.HIToolbox
import SwiftUI
import UniformTypeIdentifiers

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var dockPanels: [UUID: DockPanel] = [:]
    private let shortcutManager = GlobalShortcutManager()
    private let actionUndoManager = UndoManager()
    private let configManager = ConfigManager(
        configPath: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/freedock.json")
    )
    private let itemDragCoordinator = DockItemDragCoordinator()
    private var _lockPositions = false
    private var dockStates: [UUID: DockState] = [:]
    private var preferencesStore: DockPreferencesStore?
    private var preferencesWindowController: PreferencesWindowController?
    private var onboardingWindowController: OnboardingWindowController?
    private var menuRefreshWorkItem: DispatchWorkItem?
    private var dockResizeWorkItems: [UUID: DispatchWorkItem] = [:]
    private var liveDockResizeWorkItems: [UUID: DispatchWorkItem] = [:]
    private var dockResizeFinishWorkItems: [UUID: DispatchWorkItem] = [:]
    private var activeDockResizeIDs: Set<UUID> = []
    private var pendingAutoHideUpdates: [UUID: (enabled: Bool, orientation: Orientation)] = [:]
    private var screenParametersWorkItem: DispatchWorkItem?
    private var observesProfileAutomation = false
    private var runtimeDisplayStates: [UUID: RuntimeDisplayState] = [:]
    private var folderStackController: FolderStackPanelController?
    private let windowPreviewController =
        WindowPreviewPanelController()
    private var quickLaunchSession: QuickLaunchSession?
    private var quickLaunchResizeWorkItem: DispatchWorkItem?
    private var hideRestoredDocksAfterFolderStack = false
    private var itemDragInteractionTokens: [UUID: UUID] = [:]
    private static let onboardingCompletionKey =
        "FreeDockHasCompletedOnboardingV1"

    private struct QuickLaunchSession {
        let dockID: UUID
        let interactionToken: UUID
        let restingFrame: NSRect
        let previousApplication: NSRunningApplication?
        let restoredHiddenProfile: Bool
    }

    private struct RuntimeDisplayState {
        var effectiveDisplayID: UUID?
        var isUsingFallback: Bool
    }

    private struct IconSizeSelection {
        let dockID: UUID
        let size: Double
    }

    private struct ApplicationFileOpenRequest {
        let applicationURL: URL
        let fileURLs: [URL]
        let applicationName: String
    }

    private enum ApplicationFileOpenPreparation {
        case ready(ApplicationFileOpenRequest)
        case rejected(title: String, message: String)
    }

    func applicationDidFinishLaunching(_: Notification) {
        let shouldPresentOnboarding = OnboardingLaunchPolicy.shouldPresent(
            loadedConfigurationFromDisk: configManager.loadedFromDisk,
            hasCompletedOnboarding: UserDefaults.standard.bool(
                forKey: Self.onboardingCompletionKey
            )
        )
        itemDragCoordinator.onSessionBegan = { [weak self] _ in
            self?.beginDockItemDragInteraction()
        }
        itemDragCoordinator.onSessionEnded = { [weak self] _ in
            self?.endDockItemDragInteraction()
        }

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

        configureRecentApplicationTracking()
        configureProfileAutomation()

        restoreDocks()
        if !configManager.loadedFromDisk, configManager.config.docks.isEmpty {
            createInitialSeededDock()
        }
        rebuildMenu()
        DispatchQueue.main.async { [weak self] in
            self?.evaluateConnectedDisplayAutomation()
        }
        NSApp.activate(ignoringOtherApps: true)
        if shouldPresentOnboarding {
            DispatchQueue.main.async { [weak self] in
                self?.presentOnboarding()
            }
        }
    }

    func applicationWillTerminate(_: Notification) {
        screenParametersWorkItem?.cancel()
        itemDragCoordinator.cancel()
        windowPreviewController.close(resetNativeController: true)
        endQuickLaunch(reactivatePreviousApplication: false)
        closeFolderStack()
        saveAllPositions()
        configManager.saveImmediately()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    func applicationDidChangeScreenParameters(_: Notification) {
        windowPreviewController.close(resetNativeController: false)
        endQuickLaunch(reactivatePreviousApplication: false)
        closeFolderStack()
        for panel in dockPanels.values {
            panel.revealImmediately()
        }
        screenParametersWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.reconcileDisplayTopology()
            self?.evaluateConnectedDisplayAutomation()
        }
        screenParametersWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
    }

    @objc func rebuildMenu() {
        let menu = NSMenu()

        let profileMenu = NSMenu()
        for profile in configManager.config.profiles {
            let profileItem = NSMenuItem(
                title: profile.name,
                action: #selector(switchProfile(_:)),
                keyEquivalent: ""
            )
            profileItem.representedObject = profile.id
            profileItem.state = profile.id == configManager.config.activeProfileID ? .on : .off
            configureMenuShortcut(
                profileItem,
                shortcut: configManager.config.globalShortcuts.shortcut(
                    forProfile: profile.id
                )
            )
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
            keyEquivalent: ""
        )
        configureMenuShortcut(
            toggleProfileItem,
            shortcut: configManager.config.globalShortcuts.showHideDocks
        )
        toggleProfileItem.isEnabled = !configManager.config.docks.isEmpty
        menu.addItem(toggleProfileItem)

        let quickLaunchItem = NSMenuItem(
            title: "Quick Launch…",
            action: #selector(toggleQuickLaunch),
            keyEquivalent: ""
        )
        configureMenuShortcut(
            quickLaunchItem,
            shortcut: configManager.config.globalShortcuts.quickLaunch
        )
        quickLaunchItem.isEnabled = !configManager.config.docks.isEmpty
        quickLaunchItem.target = self
        menu.addItem(quickLaunchItem)
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
        let welcomeItem = NSMenuItem(
            title: "Welcome to FreeDock…",
            action: #selector(showOnboarding),
            keyEquivalent: ""
        )
        welcomeItem.target = self
        menu.addItem(welcomeItem)
        let supportItem = NSMenuItem(
            title: "Support FreeDock…",
            action: #selector(openSupportPage),
            keyEquivalent: ""
        )
        supportItem.target = self
        menu.addItem(supportItem)
        let preferencesItem = NSMenuItem(
            title: "Preferences…",
            action: #selector(showPreferences),
            keyEquivalent: ","
        )
        preferencesItem.keyEquivalentModifierMask = [.command]
        preferencesItem.target = self
        menu.addItem(preferencesItem)

        let undoTitle = actionUndoManager.canUndo
            ? "Undo \(actionUndoManager.undoActionName)"
            : "Undo"
        let undoItem = NSMenuItem(
            title: undoTitle,
            action: #selector(performUndo),
            keyEquivalent: "z"
        )
        undoItem.keyEquivalentModifierMask = [.command]
        undoItem.isEnabled = actionUndoManager.canUndo
        undoItem.target = self
        menu.addItem(undoItem)

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

    private func configureMenuShortcut(
        _ item: NSMenuItem,
        shortcut: GlobalShortcut?
    ) {
        guard let shortcut,
              let keyName = GlobalShortcut.keyName(for: shortcut.keyCode),
              let keyEquivalent = menuKeyEquivalent(for: keyName)
        else { return }

        item.keyEquivalent = keyEquivalent
        var modifiers: NSEvent.ModifierFlags = []
        if shortcut.modifiers & UInt32(cmdKey) != 0 {
            modifiers.insert(.command)
        }
        if shortcut.modifiers & UInt32(optionKey) != 0 {
            modifiers.insert(.option)
        }
        if shortcut.modifiers & UInt32(controlKey) != 0 {
            modifiers.insert(.control)
        }
        if shortcut.modifiers & UInt32(shiftKey) != 0 {
            modifiers.insert(.shift)
        }
        item.keyEquivalentModifierMask = modifiers
    }

    private func menuKeyEquivalent(for keyName: String) -> String? {
        if keyName.count == 1 {
            return keyName.lowercased()
        }
        if keyName.hasPrefix("F"),
           let number = Int(keyName.dropFirst()),
           (1...12).contains(number),
           let scalar = UnicodeScalar(0xF704 + number - 1)
        {
            return String(Character(scalar))
        }

        let specialKeys: [String: UInt32] = [
            "Space": 0x20,
            "Return": 0x0D,
            "Tab": 0x09,
            "Delete": 0x08,
            "Forward Delete": 0xF728,
            "Escape": 0x1B,
            "←": 0xF702,
            "→": 0xF703,
            "↑": 0xF700,
            "↓": 0xF701,
            "Home": 0xF729,
            "End": 0xF72B,
            "Page Up": 0xF72C,
            "Page Down": 0xF72D,
        ]
        guard let value = specialKeys[keyName],
              let scalar = UnicodeScalar(value)
        else { return nil }
        return String(Character(scalar))
    }

    @objc private func showOnboarding() {
        presentOnboarding()
    }

    @objc private func openSupportPage() {
        guard let url = URL(
            string: "https://www.buymeacoffee.com/thksalot"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func performUndo() {
        actionUndoManager.undo()
        rebuildMenu()
    }

    private func registerUndo(
        _ actionName: String,
        action: @escaping (AppDelegate) -> Void
    ) {
        actionUndoManager.registerUndo(withTarget: self) { target in
            action(target)
        }
        actionUndoManager.setActionName(actionName)
    }

    private func presentOnboarding() {
        if let onboardingWindowController {
            onboardingWindowController.show()
            return
        }
        let controller = OnboardingWindowController(
            requestAccessibility: { [weak self] in
                guard let self else { return false }
                return self.windowPreviewController.requestAccessibilityAccess()
                    || self.windowPreviewController.isAccessibilityTrusted
            },
            requestScreenRecording: { [weak self] in
                guard let self else { return false }
                return self.windowPreviewController.requestScreenCaptureAccess()
                    || self.windowPreviewController.isScreenCaptureTrusted
            },
            onFinish: { [weak self] openPreferences in
                self?.finishOnboarding(openPreferences: openPreferences)
            },
            onClosed: { [weak self] in
                self?.markOnboardingCompleted()
                self?.onboardingWindowController = nil
            }
        )
        onboardingWindowController = controller
        controller.show()
    }

    private func finishOnboarding(openPreferences: Bool) {
        markOnboardingCompleted()
        let controller = onboardingWindowController
        onboardingWindowController = nil
        controller?.close()
        if openPreferences {
            showPreferences()
        }
    }

    private func markOnboardingCompleted() {
        UserDefaults.standard.set(
            true,
            forKey: Self.onboardingCompletionKey
        )
    }

    @objc private func showPreferences() {
        if preferencesStore == nil {
            let store = DockPreferencesStore(
                profiles: configManager.config.profiles,
                activeProfileID: configManager.config.activeProfileID,
                displays: DockDisplayManager.connectedDisplays,
                globalShortcuts: configManager.config.globalShortcuts,
                themes: configManager.config.themes,
                onChange: { [weak self] dockID, change in
                    self?.applyDockPreference(change, to: dockID)
                },
                onManagementAction: { [weak self] action in
                    self?.handleDockManagementAction(action)
                },
                permissionSnapshot: { [weak self] in
                    guard let self else { return .checking }
                    return PreferencesPermissionSnapshot(
                        accessibilityGranted:
                            self.windowPreviewController
                                .isAccessibilityTrusted,
                        screenRecordingGranted:
                            self.windowPreviewController
                                .isScreenCaptureTrusted
                    )
                },
                onPermissionAction: { [weak self] permission in
                    self?.handlePermissionAction(permission)
                },
                onOpenPermissionSettings: {
                    [weak self] permission in
                    self?.openPermissionSettings(permission)
                },
                launchAtLoginSnapshot: {
                    LaunchAtLoginController.state
                },
                onLaunchAtLoginChange: { enabled in
                    LaunchAtLoginController.setEnabled(enabled)
                },
                onOpenLoginItemsSettings: {
                    LaunchAtLoginController.openSystemSettings()
                },
                onGlobalShortcutsChange: { [weak self] settings in
                    self?.applyGlobalShortcuts(settings)
                }
            )
            preferencesStore = store
            preferencesWindowController = PreferencesWindowController(store: store)
        }

        refreshPreferencesSnapshot()
        preferencesWindowController?.show()
    }

    private func refreshPreferencesSnapshot() {
        preferencesStore?.reload(
            profiles: configManager.config.profiles,
            activeProfileID: configManager.config.activeProfileID,
            displays: DockDisplayManager.connectedDisplays,
            globalShortcuts: configManager.config.globalShortcuts,
            themes: configManager.config.themes
        )
        preferencesStore?.refreshPermissions()
        preferencesStore?.refreshLaunchAtLogin()
    }

    private func handlePermissionAction(
        _ permission: PreferencesPermissionKind
    ) {
        switch permission {
        case .accessibility:
            if windowPreviewController.isAccessibilityTrusted {
                openPermissionSettings(permission)
            } else {
                windowPreviewController.requestAccessibilityAccess()
            }
        case .screenRecording:
            if windowPreviewController.isScreenCaptureTrusted {
                openPermissionSettings(permission)
            } else {
                windowPreviewController.requestScreenCaptureAccess()
            }
        }

        preferencesStore?.refreshPermissions()
    }

    private func openPermissionSettings(
        _ permission: PreferencesPermissionKind
    ) {
        let privacyAnchor: String
        switch permission {
        case .accessibility:
            privacyAnchor = "Privacy_Accessibility"
        case .screenRecording:
            privacyAnchor = "Privacy_ScreenCapture"
        }

        let workspace = NSWorkspace.shared
        if let privacyURL = URL(
            string:
                "x-apple.systempreferences:com.apple.preference.security?\(privacyAnchor)"
        ),
           workspace.open(privacyURL)
        {
            return
        }

        if let settingsURL = workspace.urlForApplication(
            withBundleIdentifier: "com.apple.systempreferences"
        ),
           workspace.open(settingsURL)
        {
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Open Privacy Settings"
        alert.informativeText = """
        Open System Settings → Privacy & Security and select \(permission.title). On macOS 12, open System Preferences → Security & Privacy → Privacy.
        """
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func handleDockManagementAction(_ action: DockManagementAction) {
        switch action {
        case .exportConfiguration:
            exportConfiguration()
        case .importConfiguration:
            importConfiguration()
        case let .activateProfile(profileID):
            activateProfile(profileID)
        case let .addProfileApplicationAutomation(profileID):
            chooseProfileAutomationApplication(for: profileID)
        case let .addProfileDisplayAutomation(profileID, displayID):
            addProfileDisplayAutomation(displayID, to: profileID)
        case let .setProfileAutomationEnabled(profileID, ruleID, enabled):
            setProfileAutomationEnabled(
                enabled,
                profileID: profileID,
                ruleID: ruleID
            )
        case let .deleteProfileAutomation(profileID, ruleID):
            deleteProfileAutomation(profileID: profileID, ruleID: ruleID)
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
        case let .setDockDisplay(dockID, displayID):
            setPreferredDisplay(displayID, for: dockID)
        case let .addDockItems(dockID):
            chooseDockItems(for: dockID)
        case let .addSmartStack(dockID, source):
            addSmartStack(source, to: dockID)
        case let .addTrash(dockID):
            addTrash(to: dockID)
        case .clearRecentFiles:
            confirmAndClearRecentFiles()
        case let .importSystemDockApps(dockID):
            confirmAndImportSystemDockApps(into: dockID)
        case let .resetDockSettings(dockID):
            confirmAndResetDockSettings(dockID)
        case let .copyDockSettingsToAll(dockID):
            confirmAndCopyDockSettingsToAll(dockID)
        case let .saveDockTheme(dockID):
            promptToSaveDockTheme(from: dockID)
        case let .applyDockTheme(themeID, dockID):
            applyDockTheme(themeID, to: dockID)
        case let .deleteDockTheme(themeID):
            confirmAndDeleteDockTheme(themeID)
        }

        DispatchQueue.main.async { [weak self] in
            self?.preferencesWindowController?.show()
        }
    }

    private func exportConfiguration() {
        saveAllPositions()

        let panel = NSSavePanel()
        panel.title = "Export FreeDock Configuration"
        panel.prompt = "Export"
        panel.nameFieldStringValue = "FreeDock Configuration.json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let data = try ConfigFileCodec.encode(configManager.config)
            try data.write(to: url, options: .atomic)
        } catch {
            showConfigurationFileError(
                title: "Couldn’t Export Configuration",
                error: error
            )
        }
    }

    private func importConfiguration() {
        let panel = NSOpenPanel()
        panel.title = "Import FreeDock Configuration"
        panel.prompt = "Choose"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let imported: AppConfig
        do {
            imported = try ConfigFileCodec.decode(Data(contentsOf: url))
        } catch {
            showConfigurationFileError(
                title: "Couldn’t Import Configuration",
                error: error
            )
            return
        }

        let profileCount = imported.profiles.count
        let dockCount = imported.profiles.reduce(0) { $0 + $1.docks.count }
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.alertStyle = .warning
        alert.messageText = "Replace the current FreeDock configuration?"
        alert.informativeText = "This file contains \(profileCount) profile\(profileCount == 1 ? "" : "s") and \(dockCount) dock\(dockCount == 1 ? "" : "s"). Your current configuration will be kept in freedock.json.bak."
        alert.addButton(withTitle: "Cancel")
        let importButton = alert.addButton(withTitle: "Import")
        importButton.hasDestructiveAction = true
        guard alert.runModal() == .alertSecondButtonReturn else { return }

        saveAllPositions()
        configManager.saveImmediately()
        closeAllDockPanels()
        configManager.config = imported
        configureRecentApplicationTracking()
        configManager.saveImmediately()
        restoreDocks()
        rebuildMenu()
    }

    private func showConfigurationFileError(title: String, error: Error) {
        let alert = NSAlert(error: error)
        alert.icon = NSApp.applicationIconImage
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }

    private func confirmAndEmptyTrash() {
        guard !TrashMonitor.shared.isEmpty else { return }
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.alertStyle = .warning
        alert.messageText = "Empty Trash?"
        alert.informativeText = "Items in Trash will be permanently deleted. This action cannot be undone."
        alert.addButton(withTitle: "Cancel")
        let emptyButton = alert.addButton(withTitle: "Empty Trash")
        emptyButton.hasDestructiveAction = true
        guard alert.runModal() == .alertSecondButtonReturn else { return }

        Task { @MainActor in
            let messages = await Task.detached(priority: .utility) {
                TrashController.emptyTrash().map(\.localizedDescription)
            }.value
            TrashMonitor.shared.refresh()
            guard let first = messages.first else { return }
            showTrashError(
                title: messages.count == 1
                    ? "An Item Couldn’t Be Deleted"
                    : "Some Items Couldn’t Be Deleted",
                message: first
            )
        }
    }

    private func showTrashError(title: String, error: Error) {
        showTrashError(title: title, message: error.localizedDescription)
    }

    private func showTrashError(title: String, message: String) {
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func configureRecentApplicationTracking() {
        RunningAppMonitor.shared.configureRecentApplications(
            configManager.config.recentApplications
        ) { [weak self] records in
            guard let self else { return }
            self.configManager.config.recentApplications = records
            self.configManager.save()
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

    private func setPreferredDisplay(_ displayID: UUID?, for dockID: UUID) {
        guard let index = configManager.config.docks.firstIndex(where: { $0.id == dockID }) else {
            return
        }

        var dock = configManager.config.docks[index]
        if displayID == nil {
            dock.displayPlacement = nil
            if let panel = dockPanels[dockID] {
                let frame = panel.frameForPersistence
                dock.position = frame.origin
                let descriptor = DockDisplayGeometry.bestDisplay(
                    for: frame,
                    among: DockDisplayManager.connectedDisplays
                )
                runtimeDisplayStates[dockID] = RuntimeDisplayState(
                    effectiveDisplayID: descriptor?.id,
                    isUsingFallback: false
                )
            }
            configManager.config.docks[index] = dock
            preferencesStore?.replaceDock(dock)
            configManager.save()
            refreshPreferencesSnapshot()
            return
        }

        guard let displayID,
              let targetScreen = DockDisplayManager.screen(withID: displayID),
              let targetDisplay = DockDisplayManager.descriptor(for: targetScreen)
        else {
            return
        }

        let existingPlacement = dock.displayPlacement
        let panel = dockPanels[dockID]
        let currentFrame = panel?.frameForPersistence
        let currentDisplay = currentFrame.flatMap {
            DockDisplayGeometry.bestDisplay(
                for: $0,
                among: DockDisplayManager.connectedDisplays
            )
        }
        let normalizedCenter = if let currentFrame, let currentDisplay {
            DockDisplayGeometry.normalizedCenter(
                of: currentFrame,
                in: currentDisplay.visibleFrame
            )
        } else {
            existingPlacement?.normalizedCenter ?? CGPoint(x: 0.5, y: 0.5)
        }
        let edge: DockScreenEdge? = if dock.autoHideWhenDocked,
                                      let currentFrame,
                                      let currentDisplay
        {
            DockDisplayGeometry.nearestEdge(
                of: currentFrame,
                in: currentDisplay.visibleFrame,
                orientation: dock.orientation
            )
        } else {
            dock.autoHideWhenDocked ? existingPlacement?.edge : nil
        }

        dock.displayPlacement = DockDisplayPlacement(
            displayID: displayID,
            displayName: targetDisplay.label,
            normalizedCenter: normalizedCenter,
            edge: edge
        )
        configManager.config.docks[index] = dock

        if let panel {
            placePanel(
                panel,
                using: dock,
                on: targetScreen,
                display: targetDisplay,
                isFallback: false,
                animate: true
            )
            _ = mirrorPanelPosition(panel, on: targetDisplay)
            dock = configManager.config.docks[index]
        }

        preferencesStore?.replaceDock(dock)
        configManager.save()
        refreshPreferencesSnapshot()
    }

    private func reconcileDisplayTopology() {
        TooltipManager.shared.hide()
        let docks = configManager.config.docks
        var configChanged = false

        for dock in docks {
            guard let panel = dockPanels[dock.id],
                  let resolution = displayResolution(for: dock, panelFrame: panel.frameForPersistence)
            else {
                continue
            }

            placePanel(
                panel,
                using: dock,
                on: resolution.screen,
                display: resolution.display,
                isFallback: resolution.isFallback,
                animate: false
            )
            if !resolution.isFallback {
                configChanged = mirrorPanelPosition(
                    panel,
                    on: resolution.display
                ) || configChanged
            }
        }

        if configChanged {
            configManager.save()
        }
        refreshPreferencesSnapshot()
    }

    private func displayResolution(
        for dock: DockConfig,
        panelFrame: CGRect
    ) -> (screen: NSScreen, display: DockDisplayDescriptor, isFallback: Bool)? {
        guard let resolution = DockDisplayGeometry.resolveDisplay(
            for: dock.displayPlacement,
            panelFrame: panelFrame,
            among: DockDisplayManager.connectedDisplays
        ),
        let screen = DockDisplayManager.screen(withID: resolution.display.id)
        else {
            return nil
        }
        return (screen, resolution.display, resolution.isFallback)
    }

    private func placePanel(
        _ panel: DockPanel,
        using dock: DockConfig,
        on screen: NSScreen,
        display: DockDisplayDescriptor,
        isFallback: Bool,
        animate: Bool
    ) {
        panel.revealImmediately()

        var targetFrame: CGRect
        let placement = dock.displayPlacement?.respecting(
            orientation: dock.orientation,
            autoHideWhenDocked: dock.autoHideWhenDocked
        )
        if var placement {
            let preferredEdge = placement.edge
            placement.edge = nil
            targetFrame = DockDisplayGeometry.frame(
                size: panel.frame.size,
                placement: placement,
                in: display.visibleFrame
            )

            if dock.autoHideWhenDocked {
                let exposedEdges = DockDisplayGeometry.exposedEdges(
                    for: targetFrame,
                    on: display,
                    among: DockDisplayManager.connectedDisplays
                )
                let edge = if let preferredEdge,
                              exposedEdges.contains(preferredEdge)
                {
                    preferredEdge
                } else {
                    DockDisplayGeometry.preferredDockingEdge(
                        of: targetFrame,
                        on: display,
                        among: DockDisplayManager.connectedDisplays,
                        orientation: dock.orientation
                    )
                }
                if let edge {
                    targetFrame = DockDisplayGeometry.dockedFrame(
                        targetFrame,
                        at: edge,
                        in: display.visibleFrame
                    )
                }
            }
        } else {
            targetFrame = panel.frameForPersistence
            targetFrame.origin = dock.position
            targetFrame = DockDisplayGeometry.clamped(
                targetFrame,
                to: display.visibleFrame
            )
        }

        if dock.autoHideWhenDocked, placement == nil {
            targetFrame = frameDockedToNearestEdge(
                targetFrame,
                orientation: dock.orientation,
                on: screen
            )
        }

        panel.setFrame(targetFrame, display: true, animate: animate)
        runtimeDisplayStates[dock.id] = RuntimeDisplayState(
            effectiveDisplayID: display.id,
            isUsingFallback: isFallback
        )

        if animate {
            DispatchQueue.main.asyncAfter(
                deadline: .now() + 0.35
            ) { [weak self, weak panel] in
                guard let self, let panel else { return }
                self.updateAutoHideGeometry(for: panel, on: display)
                if dock.autoHideWhenDocked {
                    panel.scheduleAutoHide()
                }
            }
        } else {
            updateAutoHideGeometry(for: panel, on: display)
            if dock.autoHideWhenDocked {
                DispatchQueue.main.asyncAfter(
                    deadline: .now() + 0.12
                ) { [weak panel] in
                    panel?.scheduleAutoHide()
                }
            }
        }
    }

    @discardableResult
    private func mirrorPanelPosition(
        _ panel: DockPanel,
        on display: DockDisplayDescriptor
    ) -> Bool {
        guard runtimeDisplayStates[panel.dockID]?.isUsingFallback != true,
              let index = configManager.config.docks.firstIndex(where: {
                  $0.id == panel.dockID
              })
        else {
            return false
        }

        var dock = configManager.config.docks[index]
        dock.position = panel.frameForPersistence.origin
        if var placement = dock.displayPlacement,
           placement.displayID == display.id
        {
            placement.displayName = display.label
            dock.displayPlacement = placement
        }

        guard dock != configManager.config.docks[index] else { return false }
        configManager.config.docks[index] = dock
        preferencesStore?.replaceDock(dock)
        return true
    }

    @discardableResult
    private func persistPanelPlacement(
        _ panel: DockPanel,
        userInitiated: Bool
    ) -> Bool {
        guard let index = configManager.config.docks.firstIndex(where: {
            $0.id == panel.dockID
        }) else {
            return false
        }

        let runtimeState = runtimeDisplayStates[panel.dockID]
        if runtimeState?.isUsingFallback == true, !userInitiated {
            return false
        }

        let frame = panel.frameForPersistence
        guard let display = DockDisplayGeometry.bestDisplay(
            for: frame,
            among: DockDisplayManager.connectedDisplays
        ) else {
            return false
        }

        var dock = configManager.config.docks[index]
        if let placement = dock.displayPlacement,
           !userInitiated,
           placement.displayID != display.id
        {
            return false
        }

        dock.position = frame.origin
        if dock.displayPlacement != nil {
            dock.displayPlacement = DockDisplayPlacement(
                displayID: display.id,
                displayName: display.label,
                normalizedCenter: DockDisplayGeometry.normalizedCenter(
                    of: frame,
                    in: display.visibleFrame
                ),
                edge: dock.autoHideWhenDocked
                    ? DockDisplayGeometry.nearestEdge(
                        of: frame,
                        in: display.visibleFrame,
                        orientation: dock.orientation
                    )
                    : nil
            )
        }

        guard dock != configManager.config.docks[index] else { return false }
        configManager.config.docks[index] = dock
        preferencesStore?.replaceDock(dock)
        runtimeDisplayStates[panel.dockID] = RuntimeDisplayState(
            effectiveDisplayID: display.id,
            isUsingFallback: false
        )
        return true
    }

    private func effectiveScreen(for panel: DockPanel) -> NSScreen? {
        if let displayID = runtimeDisplayStates[panel.dockID]?.effectiveDisplayID,
           let screen = DockDisplayManager.screen(withID: displayID)
        {
            return screen
        }
        return DockDisplayManager.screen(containing: panel.frameForPersistence)
    }

    private func updateAutoHideGeometry(
        for panel: DockPanel,
        on preferredDisplay: DockDisplayDescriptor? = nil
    ) {
        let displays = DockDisplayManager.connectedDisplays
        let display = preferredDisplay ?? DockDisplayGeometry.bestDisplay(
            for: panel.frameForPersistence,
            among: displays
        )
        guard let display else {
            panel.allowedAutoHideEdges = []
            panel.updateAutoHideEdge()
            return
        }

        panel.allowedAutoHideEdges = Set(
            DockDisplayGeometry.exposedEdges(
                for: panel.frameForPersistence,
                on: display,
                among: displays
            ).filter {
                $0.isCompatible(with: panel.dockOrientation)
            }
        )
        panel.updateAutoHideEdge()
    }

    private let snapDistance: CGFloat = 15

    private func snapFrame(
        _ frame: NSRect,
        on preferredScreen: NSScreen? = nil
    ) -> NSRect {
        guard let screen = preferredScreen ?? DockDisplayManager.screen(containing: frame) else {
            return frame
        }

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

    private func frameDockedToNearestEdge(
        _ frame: NSRect,
        orientation: Orientation,
        on preferredScreen: NSScreen? = nil
    ) -> NSRect {
        guard let screen = preferredScreen
                ?? DockDisplayManager.screen(containing: frame),
              let display = DockDisplayManager.descriptor(for: screen)
        else {
            return frame
        }

        guard let edge = DockDisplayGeometry.preferredDockingEdge(
            of: frame,
            on: display,
            among: DockDisplayManager.connectedDisplays,
            orientation: orientation
        ) else {
            return DockDisplayGeometry.clamped(
                frame,
                to: display.visibleFrame
            )
        }

        return DockDisplayGeometry.dockedFrame(
            frame,
            at: edge,
            in: display.visibleFrame
        )
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

    private func configureProfileAutomation() {
        guard !observesProfileAutomation else { return }
        observesProfileAutomation = true
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(applicationDidActivateForProfileAutomation(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    @objc private func applicationDidActivateForProfileAutomation(
        _ notification: Notification
    ) {
        guard let application = notification.userInfo?[
            NSWorkspace.applicationUserInfoKey
        ] as? NSRunningApplication,
              application.processIdentifier
                != ProcessInfo.processInfo.processIdentifier,
              let bundleIdentifier = application.bundleIdentifier,
              let profileID = ProfileAutomationPlanner.matchingProfileID(
                triggerKind: .application,
                value: bundleIdentifier,
                profiles: configManager.config.profiles
              )
        else { return }
        activateProfile(profileID)
    }

    private func evaluateConnectedDisplayAutomation() {
        let displayIDs = DockDisplayManager.connectedDisplays.map {
            $0.id.uuidString
        }
        for displayID in displayIDs {
            if let profileID = ProfileAutomationPlanner.matchingProfileID(
                triggerKind: .display,
                value: displayID,
                profiles: configManager.config.profiles
            ) {
                activateProfile(profileID)
                return
            }
        }
    }

    private func chooseProfileAutomationApplication(for profileID: UUID) {
        let panel = NSOpenPanel()
        panel.title = "Choose an Application"
        panel.prompt = "Use Application"
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK,
              let url = panel.url,
              let bundle = Bundle(url: url),
              let bundleIdentifier = bundle.bundleIdentifier
        else { return }

        addProfileAutomationRule(
            ProfileAutomationRule(
                triggerKind: .application,
                value: bundleIdentifier,
                label: bundle.object(forInfoDictionaryKey: "CFBundleDisplayName")
                    as? String
                    ?? bundle.object(forInfoDictionaryKey: "CFBundleName")
                    as? String
                    ?? url.deletingPathExtension().lastPathComponent
            ),
            to: profileID
        )
    }

    private func addProfileDisplayAutomation(
        _ displayID: UUID,
        to profileID: UUID
    ) {
        guard let display = DockDisplayManager.connectedDisplays.first(where: {
            $0.id == displayID
        }) else { return }
        addProfileAutomationRule(
            ProfileAutomationRule(
                triggerKind: .display,
                value: display.id.uuidString,
                label: display.label
            ),
            to: profileID
        )
    }

    private func addProfileAutomationRule(
        _ rule: ProfileAutomationRule,
        to profileID: UUID
    ) {
        guard let index = configManager.config.profiles.firstIndex(where: {
            $0.id == profileID
        }), !configManager.config.profiles[index].automationRules.contains(where: {
            $0.triggerKind == rule.triggerKind
                && $0.value.caseInsensitiveCompare(rule.value) == .orderedSame
        }) else { return }
        configManager.config.profiles[index].automationRules.append(rule)
        configManager.save()
        refreshPreferencesSnapshot()
    }

    private func setProfileAutomationEnabled(
        _ enabled: Bool,
        profileID: UUID,
        ruleID: UUID
    ) {
        guard let profileIndex = configManager.config.profiles.firstIndex(where: {
            $0.id == profileID
        }), let ruleIndex = configManager.config.profiles[profileIndex]
            .automationRules.firstIndex(where: { $0.id == ruleID })
        else { return }
        configManager.config.profiles[profileIndex]
            .automationRules[ruleIndex].isEnabled = enabled
        configManager.save()
        refreshPreferencesSnapshot()
    }

    private func deleteProfileAutomation(
        profileID: UUID,
        ruleID: UUID
    ) {
        guard let profileIndex = configManager.config.profiles.firstIndex(where: {
            $0.id == profileID
        }) else { return }
        configManager.config.profiles[profileIndex].automationRules.removeAll {
            $0.id == ruleID
        }
        configManager.save()
        refreshPreferencesSnapshot()
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

    @discardableResult
    private func configureGlobalShortcuts() -> Bool {
        shortcutManager.reset()
        let settings = configManager.config.globalShortcuts
        let showHide = settings.showHideDocks
        let didRegisterShowHide = shortcutManager.register(
            id: 1,
            keyCode: showHide.keyCode,
            modifiers: showHide.modifiers
        ) { [weak self] in
            self?.toggleActiveProfileDocks()
        }
        let quickLaunch = settings.quickLaunch
        let didRegisterQuickLaunch = shortcutManager.register(
            id: 100,
            keyCode: quickLaunch.keyCode,
            modifiers: quickLaunch.modifiers
        ) { [weak self] in
            self?.toggleQuickLaunch()
        }
        if !didRegisterQuickLaunch {
            NSLog("FreeDock could not register the global Quick Launch shortcut Command-Shift-Space.")
        }

        var didRegisterProfiles = true
        for (index, profile) in configManager.config.profiles.enumerated() {
            guard let shortcut = settings.shortcut(forProfile: profile.id) else {
                continue
            }
            let registered = shortcutManager.register(
                id: UInt32(index + 1_000),
                keyCode: shortcut.keyCode,
                modifiers: shortcut.modifiers
            ) { [weak self] in
                self?.activateProfile(profile.id)
            }
            didRegisterProfiles = didRegisterProfiles && registered
        }
        return didRegisterShowHide && didRegisterQuickLaunch
            && didRegisterProfiles
    }

    private func applyGlobalShortcuts(
        _ settings: GlobalShortcutSettings
    ) -> String? {
        var settings = settings
        settings.reconcileProfiles(configManager.config.profiles)
        if let error = settings.validationError() {
            return error
        }

        let previous = configManager.config.globalShortcuts
        configManager.config.globalShortcuts = settings
        guard configureGlobalShortcuts() else {
            configManager.config.globalShortcuts = previous
            configureGlobalShortcuts()
            return "macOS could not register that shortcut. It may already be used by another app."
        }

        configManager.save()
        rebuildMenu()
        return nil
    }

    @objc private func toggleQuickLaunch() {
        windowPreviewController.close(resetNativeController: false)
        if quickLaunchSession != nil {
            endQuickLaunch(reactivatePreviousApplication: true)
            return
        }

        closeFolderStack()
        TooltipManager.shared.hide()

        let restoredHiddenProfile = dockPanels.isEmpty
        if restoredHiddenProfile, !configManager.config.docks.isEmpty {
            restoreDocks()
            scheduleMenuRefresh()
        }

        guard let panel = quickLaunchTargetPanel(),
              let state = dockStates[panel.dockID]
        else {
            NSSound.beep()
            return
        }

        let frontmostApplication = NSWorkspace.shared.frontmostApplication
        let previousApplication = frontmostApplication?.processIdentifier
            == ProcessInfo.processInfo.processIdentifier
            ? nil
            : frontmostApplication
        let interactionToken = panel.beginTransientInteraction()
        panel.setPositionLocked(true)
        quickLaunchSession = QuickLaunchSession(
            dockID: panel.dockID,
            interactionToken: interactionToken,
            restingFrame: panel.frameForPersistence,
            previousApplication: previousApplication,
            restoredHiddenProfile: restoredHiddenProfile
        )

        panel.setQuickLaunchKeyMode(true)
        state.presentQuickLaunch()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        resizeAfterQuickLaunchTransition(panel)
    }

    private func quickLaunchTargetPanel() -> DockPanel? {
        let orderedDocks = configManager.config.docks
        if let keyPanel = orderedDocks.lazy.compactMap({
            self.dockPanels[$0.id]
        }).first(where: \.isKeyWindow) {
            return keyPanel
        }

        let pointer = NSEvent.mouseLocation
        let pointerScreen = NSScreen.screens.first {
            $0.frame.contains(pointer)
        }
        let candidates = orderedDocks.enumerated().compactMap {
            order, dock -> QuickLaunchDockCandidate? in
            guard let panel = dockPanels[dock.id] else { return nil }
            return QuickLaunchDockCandidate(
                dockID: dock.id,
                frame: panel.frameForPersistence,
                configOrder: order
            )
        }
        guard let targetID = QuickLaunchDockRouter.targetDockID(
            for: pointer,
            pointerScreenFrame: pointerScreen?.frame,
            candidates: candidates
        ) else {
            return nil
        }
        return dockPanels[targetID]
    }

    @discardableResult
    private func endQuickLaunch(
        ifDockID dockID: UUID? = nil,
        reactivatePreviousApplication: Bool,
        restoreHiddenProfile: Bool = true
    ) -> Bool {
        guard let session = quickLaunchSession,
              dockID == nil || session.dockID == dockID
        else {
            return false
        }

        quickLaunchSession = nil
        quickLaunchResizeWorkItem?.cancel()
        quickLaunchResizeWorkItem = nil

        let panel = dockPanels[session.dockID]
        dockStates[session.dockID]?.dismissQuickLaunch()
        panel?.setFrame(session.restingFrame, display: true)
        panel?.endTransientInteraction(session.interactionToken)
        panel?.setPositionLocked(_lockPositions)
        if panel?.isKeyWindow == true {
            panel?.resignKey()
        }
        panel?.setQuickLaunchKeyMode(false)
        if session.restoredHiddenProfile, restoreHiddenProfile {
            hideDocksRestoredForQuickLaunch()
        } else if let panel {
            resizeAfterQuickLaunchTransition(panel)
        }

        if reactivatePreviousApplication,
           let previousApplication = session.previousApplication,
           !previousApplication.isTerminated
        {
            DispatchQueue.main.async {
                previousApplication.activate(
                    options: [.activateIgnoringOtherApps]
                )
            }
        }
        return session.restoredHiddenProfile
    }

    private func resizeAfterQuickLaunchTransition(_ panel: DockPanel) {
        quickLaunchResizeWorkItem?.cancel()
        let dockID = panel.dockID
        let work = DispatchWorkItem { [weak self, weak panel] in
            guard let self else { return }
            self.quickLaunchResizeWorkItem = nil
            guard let panel,
                  self.dockPanels[dockID] === panel
            else {
                return
            }
            panel.resizeToFitContent()
            self.updateAutoHideGeometry(for: panel)
        }
        quickLaunchResizeWorkItem = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + (1.0 / 60.0),
            execute: work
        )
    }

    private func hideDocksRestoredForQuickLaunch() {
        hideRestoredDocksAfterFolderStack = false
        quickLaunchResizeWorkItem?.cancel()
        quickLaunchResizeWorkItem = nil
        guard !dockPanels.isEmpty else { return }
        closeAllDockPanels()
        scheduleMenuRefresh()
    }

    @objc private func createProfile() {
        guard let name = promptForProfileName(
            title: "New Profile",
            message: "Create a separate set of docks for a workflow.",
            initialValue: suggestedProfileName()
        ) else { return }

        saveAllPositions()
        closeAllDockPanels()

        let placement = defaultDockPlacement
        let starterDock = DockConfig(
            name: "Dock 1",
            position: placement.position,
            displayPlacement: placement.displayPlacement,
            orientation: .horizontal,
            autoHideWhenDocked: false
        )
        let profile = DockProfile(name: name, docks: [starterDock])
        configManager.config.profiles.append(profile)
        configManager.config.globalShortcuts.reconcileProfiles(
            configManager.config.profiles
        )
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

        let previousActiveProfileID = configManager.config.activeProfileID
        registerUndo("Delete Profile") { target in
            target.restoreDeletedProfile(
                profile,
                at: index,
                activeProfileID: previousActiveProfileID
            )
        }
        saveAllPositions()
        closeAllDockPanels()
        configManager.config.profiles.remove(at: index)
        configManager.config.globalShortcuts.reconcileProfiles(
            configManager.config.profiles
        )
        let nextIndex = min(index, configManager.config.profiles.count - 1)
        configManager.config.activeProfileID = configManager.config.profiles[nextIndex].id
        restoreDocks()
        configManager.save()
        rebuildMenu()
    }

    private func restoreDeletedProfile(
        _ profile: DockProfile,
        at requestedIndex: Int,
        activeProfileID: UUID
    ) {
        guard !configManager.config.profiles.contains(where: {
            $0.id == profile.id
        }) else { return }
        saveAllPositions()
        closeAllDockPanels()
        let index = min(requestedIndex, configManager.config.profiles.count)
        configManager.config.profiles.insert(profile, at: index)
        configManager.config.globalShortcuts.reconcileProfiles(
            configManager.config.profiles
        )
        configManager.config.activeProfileID = activeProfileID
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

    private var defaultDockPlacement: (
        position: CGPoint,
        displayPlacement: DockDisplayPlacement?
    ) {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: {
            $0.frame.contains(mouseLocation)
        }) ?? DockDisplayManager.primaryScreen
        let visibleFrame = screen?.visibleFrame
            ?? NSRect(x: 100, y: 100, width: 1200, height: 800)
        let position = CGPoint(
            x: visibleFrame.midX - 150,
            y: visibleFrame.midY - 30
        )
        let displayPlacement = screen
            .flatMap(DockDisplayManager.descriptor(for:))
            .map {
                DockDisplayPlacement(
                    displayID: $0.id,
                    displayName: $0.label
                )
            }
        return (position, displayPlacement)
    }

    private func createDock(orientation: Orientation) {
        let placement = defaultDockPlacement
        let dock = DockConfig(
            name: suggestedDockName(),
            position: placement.position,
            displayPlacement: placement.displayPlacement,
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
        let placement = defaultDockPlacement
        let dock = DockConfig(
            name: "Dock 1",
            position: placement.position,
            displayPlacement: placement.displayPlacement,
            orientation: .horizontal,
            items: seededDockItems()
        )
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
            endQuickLaunch(
                ifDockID: id,
                reactivatePreviousApplication: false
            )
            closeFolderStack(for: id)
            cancelDockResizeWork(for: id)
            pendingAutoHideUpdates.removeValue(forKey: id)
            panel.tearDown()
            dockPanels.removeValue(forKey: id)
            dockStates.removeValue(forKey: id)
            runtimeDisplayStates.removeValue(forKey: id)
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
        guard let index = configManager.config.docks.firstIndex(where: {
            $0.id == id
        }) else { return }
        let dock = configManager.config.docks[index]

        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.alertStyle = .warning
        alert.messageText = "Delete “\(dock.name)”?"
        alert.informativeText = "This removes the dock from the current profile. The pinned applications, files, and folders themselves will not be deleted."
        alert.addButton(withTitle: "Cancel")
        let deleteButton = alert.addButton(withTitle: "Delete")
        deleteButton.hasDestructiveAction = true
        guard alert.runModal() == .alertSecondButtonReturn else { return }

        let profileID = configManager.config.activeProfileID
        registerUndo("Delete Dock") { target in
            target.restoreDeletedDock(
                dock,
                at: index,
                in: profileID
            )
        }
        performDeleteDock(id)
    }

    private func restoreDeletedDock(
        _ dock: DockConfig,
        at requestedIndex: Int,
        in profileID: UUID
    ) {
        guard let profileIndex = configManager.config.profiles.firstIndex(where: {
            $0.id == profileID
        }), !configManager.config.profiles[profileIndex].docks.contains(where: {
            $0.id == dock.id
        }) else { return }
        let index = min(requestedIndex, configManager.config.profiles[profileIndex].docks.count)
        configManager.config.profiles[profileIndex].docks.insert(dock, at: index)
        if profileID == configManager.config.activeProfileID {
            showDock(dock)
        }
        configManager.save()
        rebuildMenu()
    }

    private func performDeleteDock(_ id: UUID) {
        endQuickLaunch(
            ifDockID: id,
            reactivatePreviousApplication: false
        )
        closeFolderStack(for: id)
        cancelDockResizeWork(for: id)
        pendingAutoHideUpdates.removeValue(forKey: id)
        dockPanels[id]?.tearDown()
        dockPanels.removeValue(forKey: id)
        dockStates.removeValue(forKey: id)
        runtimeDisplayStates.removeValue(forKey: id)
        configManager.config.docks.removeAll(where: { $0.id == id })
        configManager.save()
        rebuildMenu()
    }

    @objc private func toggleLockPositions() {
        _lockPositions.toggle()
        for panel in dockPanels.values {
            panel.setPositionLocked(_lockPositions)
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
        let screen = effectiveScreen(for: panel)
        let dockedFrame = frameDockedToNearestEdge(
            panel.frameForPersistence,
            orientation: configManager.config.docks[index].orientation,
            on: screen
        )
        panel.setFrame(dockedFrame, display: true, animate: true)
        _ = persistPanelPlacement(panel, userInitiated: false)
        configManager.save()
        refreshPreferencesSnapshot()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            [weak self, weak panel] in
            guard let self, let panel else { return }
            self.updateAutoHideGeometry(for: panel)
            panel.scheduleAutoHide()
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
            dockStates[id]?.name = proposedValue
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

        var duplicate = source.duplicated(
            name: suggestedDuplicateName(for: source.name),
            position: duplicatedPosition
        )
        if let placement = duplicate.displayPlacement,
           let resolution = DockDisplayGeometry.resolveDisplay(
               for: placement,
               panelFrame: dockPanels[id]?.frameForPersistence
                   ?? CGRect(origin: source.position, size: .zero),
               among: DockDisplayManager.connectedDisplays
           )
        {
            let delta = source.orientation == .horizontal
                ? CGPoint(x: 32, y: 0)
                : CGPoint(x: 0, y: -32)
            duplicate.displayPlacement = DockDisplayGeometry.offset(
                placement,
                by: delta,
                in: resolution.display.visibleFrame
            )
        }

        configManager.config.docks.insert(duplicate, at: sourceIndex + 1)
        showDock(duplicate)
        configManager.save()
        rebuildMenu()
        preferencesStore?.selectedDockID = duplicate.id
    }

    private func chooseDockItems(for dockID: UUID) {
        guard configManager.config.docks.contains(where: { $0.id == dockID }) else {
            return
        }

        windowPreviewController.close(resetNativeController: false)
        closeFolderStack()
        let sourceDock = dockPanels[dockID]
        let interactionToken = sourceDock?.beginTransientInteraction()
        let openPanel = NSOpenPanel()
        openPanel.title = "Add Items to FreeDock"
        openPanel.message = "Choose applications, documents, or folders to pin."
        openPanel.prompt = "Add"
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = true
        openPanel.resolvesAliases = true
        openPanel.treatsFilePackagesAsDirectories = false

        let completion: (NSApplication.ModalResponse) -> Void = {
            [weak self, weak sourceDock] response in
            if let interactionToken {
                sourceDock?.endTransientInteraction(interactionToken)
            }
            guard response == .OK, let self else { return }

            let currentItems = self.configManager.config.docks.first(where: {
                $0.id == dockID
            })?.items ?? []
            let plan = DockItemPlanner.planAdding(
                urls: openPanel.urls,
                to: currentItems
            )
            guard plan.addedCount > 0 else {
                NSSound.beep()
                return
            }
            self.replaceDockItems(plan.items, for: dockID)
        }

        if let preferencesWindow = preferencesWindowController?.window,
           preferencesWindow.isVisible
        {
            openPanel.beginSheetModal(
                for: preferencesWindow,
                completionHandler: completion
            )
        } else {
            openPanel.begin(completionHandler: completion)
        }
    }

    private func addSmartStack(
        _ source: SmartStackSource,
        to dockID: UUID
    ) {
        guard let dock = configManager.config.docks.first(where: {
            $0.id == dockID
        }) else {
            return
        }

        let plan = DockItemPlanner.planAdding(
            smartStack: source,
            to: dock.items
        )
        guard plan.addedCount > 0 else {
            NSSound.beep()
            return
        }
        replaceDockItems(plan.items, for: dockID)
    }

    private func addTrash(to dockID: UUID) {
        guard let dock = configManager.config.docks.first(where: {
            $0.id == dockID
        }) else { return }
        let plan = DockItemPlanner.planAddingTrash(to: dock.items)
        guard plan.addedCount > 0 else {
            NSSound.beep()
            return
        }
        replaceDockItems(plan.items, for: dockID)
    }

    private func replaceDockItems(
        _ items: [DockItem],
        for dockID: UUID,
        preservingOpenFolderStack: Bool = false
    ) {
        guard let index = configManager.config.docks.firstIndex(where: {
            $0.id == dockID
        }) else {
            return
        }

        let previous = configManager.config.docks[index]
        guard previous.items != items else { return }
        let removedItemIDs = Set(previous.items.map(\.id))
            .subtracting(items.map(\.id))
        if !removedItemIDs.isEmpty {
            let profileID = configManager.config.activeProfileID
            registerUndo("Remove Dock Item") { target in
                target.restoreDockItems(
                    previous.items,
                    dockID: dockID,
                    profileID: profileID
                )
            }
        }
        var updated = previous
        updated.items = items
        configManager.config.docks[index] = updated

        if let controller = folderStackController,
           controller.dockID == dockID
        {
            let matchingItem = items.first { $0.id == controller.itemID }
            if !preservingOpenFolderStack || matchingItem?.kind != .folder {
                closeFolderStack()
            }
        }

        preferencesStore?.replaceDock(updated)
        reconcileDockRuntime(from: previous, to: updated)
        configManager.save()
        refreshPreferencesSnapshot()
        if !removedItemIDs.isEmpty {
            rebuildMenu()
        }
    }

    private func restoreDockItems(
        _ items: [DockItem],
        dockID: UUID,
        profileID: UUID
    ) {
        guard let profileIndex = configManager.config.profiles.firstIndex(where: {
            $0.id == profileID
        }), let dockIndex = configManager.config.profiles[profileIndex]
            .docks.firstIndex(where: { $0.id == dockID })
        else { return }
        let previous = configManager.config.profiles[profileIndex].docks[dockIndex]
        var restored = previous
        restored.items = items
        configManager.config.profiles[profileIndex].docks[dockIndex] = restored
        if profileID == configManager.config.activeProfileID {
            preferencesStore?.replaceDock(restored)
            reconcileDockRuntime(from: previous, to: restored)
        }
        configManager.save()
        refreshPreferencesSnapshot()
    }

    private func promptToRenameDockItem(
        _ item: DockItem,
        in dockID: UUID
    ) {
        guard item.kind != .separator, item.kind != .trash else { return }
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.messageText = "Rename Dock Item"
        alert.informativeText = "Enter a custom label, or leave it empty to use the original name."
        let field = NSTextField(
            frame: NSRect(x: 0, y: 0, width: 240, height: 24)
        )
        field.stringValue = DockItemPresentation.resolve(item).displayName
        field.selectText(nil)
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        var updatedItems = configManager.config.docks.first(where: {
            $0.id == dockID
        })?.items ?? []
        guard let index = updatedItems.firstIndex(where: {
            $0.id == item.id
        }) else { return }
        let label = field.stringValue.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        updatedItems[index].label = label.isEmpty ? nil : label
        replaceDockItems(updatedItems, for: dockID)
    }

    private func chooseCustomIcon(
        for item: DockItem,
        in dockID: UUID
    ) {
        guard item.kind != .separator, item.kind != .trash else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose an Icon for \(DockItemPresentation.resolve(item).displayName)"
        panel.prompt = "Choose Icon"
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK,
              let url = panel.url,
              let iconData = DockItemIconEncoder.encodeImage(at: url)
        else {
            if panel.url != nil {
                showCustomIconError()
            }
            return
        }
        updateCustomIcon(iconData, for: item.id, in: dockID)
    }

    private func updateCustomIcon(
        _ data: Data?,
        for itemID: DockItem.ID,
        in dockID: UUID
    ) {
        var updatedItems = configManager.config.docks.first(where: {
            $0.id == dockID
        })?.items ?? []
        guard let index = updatedItems.firstIndex(where: {
            $0.id == itemID
        }) else { return }
        updatedItems[index].customIconData = data
        replaceDockItems(updatedItems, for: dockID)
    }

    private func showCustomIconError() {
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.alertStyle = .warning
        alert.messageText = "Icon Couldn’t Be Used"
        alert.informativeText = "Choose a valid image smaller than 10 MB. FreeDock stores a portable optimized copy in its configuration."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func transferDockItem(
        _ session: DockItemDragSession,
        to targetDockID: UUID,
        destination: DockItemTransferDestination,
        operation: DockItemTransferOperation
    ) -> Bool {
        guard itemDragCoordinator.activeSession == session,
              session.profileID == configManager.config.activeProfileID,
              dockPanels[session.sourceDockID] != nil,
              dockPanels[targetDockID] != nil
        else {
            itemDragCoordinator.finish(sessionID: session.id)
            return false
        }

        var docks = configManager.config.docks
        let originalDocks = docks
        guard let sourceIndex = docks.firstIndex(where: {
            $0.id == session.sourceDockID
        }),
        let targetIndex = docks.firstIndex(where: {
            $0.id == targetDockID
        })
        else {
            itemDragCoordinator.finish(sessionID: session.id)
            return false
        }

        let effectiveOperation: DockItemTransferOperation =
            session.sourceDockID == targetDockID ? .move : operation
        let plan = DockItemTransferPlanner.planTransfer(
            itemID: session.itemID,
            from: docks[sourceIndex],
            to: docks[targetIndex],
            operation: effectiveOperation,
            destination: destination
        )

        switch plan.outcome {
        case .rejected:
            NSSound.beep()
            itemDragCoordinator.finish(sessionID: session.id)
            return false
        case .unchanged:
            itemDragCoordinator.finish(sessionID: session.id)
            return true
        case .moved, .copied, .removed:
            break
        }

        var changes: [(previous: DockConfig, updated: DockConfig)] = []
        if sourceIndex == targetIndex {
            let previous = docks[sourceIndex]
            var updated = previous
            updated.items = plan.sourceItems
            docks[sourceIndex] = updated
            changes.append((previous, updated))
        } else {
            let previousSource = docks[sourceIndex]
            let previousTarget = docks[targetIndex]
            var updatedSource = previousSource
            var updatedTarget = previousTarget
            updatedSource.items = plan.sourceItems
            updatedTarget.items = plan.targetItems
            docks[sourceIndex] = updatedSource
            docks[targetIndex] = updatedTarget
            if previousSource != updatedSource {
                changes.append((previousSource, updatedSource))
            }
            if previousTarget != updatedTarget {
                changes.append((previousTarget, updatedTarget))
            }
        }

        guard !changes.isEmpty else {
            itemDragCoordinator.finish(sessionID: session.id)
            return true
        }

        if case .removed = plan.outcome {
            let profileID = configManager.config.activeProfileID
            registerUndo("Remove Dock Item") { target in
                target.restoreProfileDocks(
                    originalDocks,
                    profileID: profileID
                )
            }
        }

        // Make both sides visible atomically before panels or Preferences
        // reconcile the transfer.
        configManager.config.docks = docks

        if let controller = folderStackController,
           changes.contains(where: {
               $0.updated.id == controller.dockID
           })
        {
            closeFolderStack()
        }

        for change in changes {
            preferencesStore?.replaceDock(change.updated)
            reconcileDockRuntime(
                from: change.previous,
                to: change.updated
            )
        }
        configManager.save()
        refreshPreferencesSnapshot()
        itemDragCoordinator.publishContentChange()
        itemDragCoordinator.finish(sessionID: session.id)
        if case .removed = plan.outcome {
            rebuildMenu()
        }
        return true
    }

    private func restoreProfileDocks(
        _ docks: [DockConfig],
        profileID: UUID
    ) {
        guard let profileIndex = configManager.config.profiles.firstIndex(where: {
            $0.id == profileID
        }) else { return }
        configManager.config.profiles[profileIndex].docks = docks
        if profileID == configManager.config.activeProfileID {
            closeAllDockPanels()
            restoreDocks()
        }
        configManager.save()
        rebuildMenu()
    }

    private func activateDockItem(
        _ item: DockItem,
        sourceRect: CGRect,
        in panel: DockPanel
    ) {
        guard item.kind != .separator else { return }

        windowPreviewController.close(resetNativeController: false)
        if item.kind == .trash {
            closeFolderStack()
            guard let trashURL = TrashController.trashURL,
                  NSWorkspace.shared.open(trashURL)
            else { NSSound.beep(); return }
            return
        }
        if item.kind == .folder {
            if let controller = folderStackController,
               controller.dockID == panel.dockID,
               controller.itemID == item.id
            {
                closeFolderStack()
                return
            }

            closeFolderStack()
            let dockID = panel.dockID
            let itemID = item.id
            let controller = FolderStackPanelController(
                dockID: dockID,
                item: item,
                sourceRect: sourceRect,
                sourceDock: panel,
                recentFiles: configManager.config.recentFiles,
                onOpenURL: { [weak self] url in
                    self?.openThroughFreeDock(url)
                },
                onClearRecentFiles: { [weak self] in
                    self?.confirmAndClearRecentFiles()
                },
                onOptionsChanged: { [weak self] options in
                    self?.updateFolderStackOptions(
                        options,
                        for: itemID,
                        in: dockID
                    )
                },
                onDidClose: { [weak self] in
                    guard let self,
                          self.folderStackController?.dockID == dockID,
                          self.folderStackController?.itemID == itemID
                    else {
                        return
                    }
                    self.folderStackController = nil
                    if self.hideRestoredDocksAfterFolderStack {
                        self.hideDocksRestoredForQuickLaunch()
                    }
                }
            )
            folderStackController = controller
            controller.show()
            return
        }

        closeFolderStack()
        guard FileManager.default.fileExists(atPath: item.path) else {
            NSSound.beep()
            return
        }
        openThroughFreeDock(
            URL(fileURLWithPath: item.path),
            knownKind: item.kind
        )
    }

    private func openThroughFreeDock(
        _ url: URL,
        knownKind: DockItemKind? = nil
    ) {
        guard url.isFileURL,
              FileManager.default.fileExists(atPath: url.path)
        else {
            NSSound.beep()
            return
        }

        guard NSWorkspace.shared.open(url) else {
            NSSound.beep()
            return
        }

        let resolvedKind = knownKind ?? DockItem.pinnedItem(at: url)?.kind
        guard resolvedKind == .document else { return }
        recordRecentDocument(url)
    }

    private func openThroughFreeDock(
        _ url: URL,
        withApplicationAt applicationURL: URL
    ) {
        _ = openFilesThroughFreeDock(
            [url],
            withApplicationAt: applicationURL
        )
    }

    @discardableResult
    private func openFilesThroughFreeDock(
        _ urls: [URL],
        withApplicationAt applicationURL: URL,
        applicationName: String? = nil,
        presentsValidationErrors: Bool = true
    ) -> Bool {
        let preparation = prepareApplicationFileOpen(
            urls,
            withApplicationAt: applicationURL,
            applicationName: applicationName
        )
        guard case let .ready(request) = preparation else {
            if case let .rejected(title, message) = preparation {
                if presentsValidationErrors {
                    showApplicationFileOpenError(
                        title: title,
                        message: message
                    )
                } else {
                    NSSound.beep()
                }
            }
            return false
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.allowsRunningApplicationSubstitution = false
        NSWorkspace.shared.open(
            request.fileURLs,
            withApplicationAt: request.applicationURL,
            configuration: configuration
        ) { [weak self] _, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let error {
                    self.showApplicationFileOpenError(
                        title: "Couldn’t Open with \(request.applicationName)",
                        message: error.localizedDescription
                    )
                    return
                }
                self.recordRecentDocuments(request.fileURLs)
            }
        }
        return true
    }

    private func canOpenFilesThroughFreeDock(
        _ urls: [URL],
        withApplicationAt applicationURL: URL,
        applicationName: String? = nil
    ) -> Bool {
        if case .ready = prepareApplicationFileOpen(
            urls,
            withApplicationAt: applicationURL,
            applicationName: applicationName
        ) {
            return true
        }
        return false
    }

    private func prepareApplicationFileOpen(
        _ urls: [URL],
        withApplicationAt applicationURL: URL,
        applicationName: String?
    ) -> ApplicationFileOpenPreparation {
        let outcome = DockApplicationFileDropPlanner.plan(
            applicationURL: applicationURL,
            droppedURLs: urls
        )
        guard let plan = outcome.plan,
              FileManager.default.fileExists(
                  atPath: plan.applicationURL.path
              ),
              DockItem.pinnedItem(at: plan.applicationURL)?.kind
                  == .application
        else {
            return .rejected(
                title: "Application Isn’t Available",
                message: "FreeDock could not find the selected application."
            )
        }

        let fileURLs = canonicalUniqueURLs(plan.fileURLs)
        guard !fileURLs.isEmpty,
              fileURLs.allSatisfy({
                  FileManager.default.fileExists(atPath: $0.path)
              })
        else {
            return .rejected(
                title: "Items Aren’t Available",
                message: "One or more selected items could not be found."
            )
        }

        let resolvedApplicationName = applicationName
            ?? applicationDisplayName(at: plan.applicationURL)
        guard fileURLs.allSatisfy({
            application(plan.applicationURL, canOpen: $0)
        }) else {
            let itemCount = fileURLs.count
            return .rejected(
                title: "\(resolvedApplicationName) Can’t Open \(itemCount == 1 ? "This Item" : "These Items")",
                message: "The entire selection was cancelled. Move the \(itemCount == 1 ? "item" : "items") to an empty area of the dock if you want to pin \(itemCount == 1 ? "it" : "them") instead."
            )
        }

        return .ready(
            ApplicationFileOpenRequest(
                applicationURL: plan.applicationURL,
                fileURLs: fileURLs,
                applicationName: resolvedApplicationName
            )
        )
    }

    private func application(
        _ applicationURL: URL,
        canOpen fileURL: URL
    ) -> Bool {
        let applicationIdentity = canonicalFileIdentity(
            applicationURL
        )
        return NSWorkspace.shared
            .urlsForApplications(toOpen: fileURL)
            .contains {
                canonicalFileIdentity($0) == applicationIdentity
            }
    }

    private func canonicalUniqueURLs(_ urls: [URL]) -> [URL] {
        var seenIdentities = Set<String>()
        return urls.filter {
            seenIdentities.insert(
                canonicalFileIdentity($0)
            ).inserted
        }
    }

    private func canonicalFileIdentity(_ url: URL) -> String {
        url.standardizedFileURL
            .resolvingSymlinksInPath()
            .path
    }

    private func applicationDisplayName(at applicationURL: URL) -> String {
        let displayName = FileManager.default.displayName(
            atPath: applicationURL.path
        )
        return displayName.hasSuffix(".app")
            ? (displayName as NSString).deletingPathExtension
            : displayName
    }

    private func showApplicationFileOpenError(
        title: String,
        message: String
    ) {
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func recordRecentDocument(_ url: URL) {
        recordRecentDocuments([url])
    }

    private func recordRecentDocuments(_ urls: [URL]) {
        var records = configManager.config.recentFiles
        var didRecord = false
        let openedAt = Date()

        for (index, url) in urls.enumerated() {
            let plan = RecentFileHistoryPlanner.planRecording(
                url: url,
                displayName: FileManager.default.displayName(
                    atPath: url.path
                ),
                openedAt: openedAt.addingTimeInterval(
                    -Double(index) / 1_000
                ),
                records: records
            )
            guard plan.didRecord else { continue }
            records = plan.records
            didRecord = true
        }

        guard didRecord else { return }
        configManager.config.recentFiles = records
        configManager.save()
    }

    private func chooseFilesToOpen(
        with item: DockItem,
        from sourceDock: DockPanel
    ) {
        guard item.kind == .application,
              let applicationURL = item.fileURL,
              FileManager.default.fileExists(
                  atPath: applicationURL.path
              )
        else {
            NSSound.beep()
            return
        }

        let interactionToken = sourceDock.beginTransientInteraction()
        let openPanel = NSOpenPanel()
        let applicationName = item.label
            ?? applicationDisplayName(at: applicationURL)
        openPanel.title = "Open with \(applicationName)"
        openPanel.message = "Choose files or folders for \(applicationName) to open."
        openPanel.prompt = "Open"
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = true
        openPanel.resolvesAliases = true
        openPanel.treatsFilePackagesAsDirectories = false
        openPanel.begin { [weak self, weak sourceDock] response in
            sourceDock?.endTransientInteraction(interactionToken)
            guard response == .OK, let self else { return }
            _ = self.openFilesThroughFreeDock(
                openPanel.urls,
                withApplicationAt: applicationURL,
                applicationName: applicationName
            )
        }
    }

    private func updateFolderStackOptions(
        _ options: FolderStackOptions,
        for itemID: UUID,
        in dockID: UUID
    ) {
        guard let dock = configManager.config.docks.first(where: {
            $0.id == dockID
        }),
        let itemIndex = dock.items.firstIndex(
            where: { $0.id == itemID && $0.kind == .folder }
        )
        else {
            return
        }

        guard dock.items[itemIndex].folderOptions != options else { return }
        var items = dock.items
        items[itemIndex].folderOptions = options
        replaceDockItems(
            items,
            for: dockID,
            preservingOpenFolderStack: true
        )
    }

    private func closeFolderStack(for dockID: UUID? = nil) {
        guard let controller = folderStackController,
              dockID == nil || controller.dockID == dockID
        else {
            return
        }
        let shouldHideRestoredDocks =
            hideRestoredDocksAfterFolderStack
        hideRestoredDocksAfterFolderStack = false
        folderStackController = nil
        controller.close()
        if shouldHideRestoredDocks {
            hideDocksRestoredForQuickLaunch()
        }
    }

    private func confirmAndClearRecentFiles() {
        guard !configManager.config.recentFiles.isEmpty else {
            let alert = NSAlert()
            alert.icon = NSApp.applicationIconImage
            alert.messageText = "No Recent Files"
            alert.informativeText = "Open a document through FreeDock and it will appear in the Recent Files stack."
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }

        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.alertStyle = .warning
        alert.messageText = "Clear Recent Files history?"
        alert.informativeText = "This clears FreeDock’s local history only. Your documents will not be deleted or changed."
        alert.addButton(withTitle: "Cancel")
        let clearButton = alert.addButton(withTitle: "Clear History")
        clearButton.hasDestructiveAction = true
        guard alert.runModal() == .alertSecondButtonReturn else { return }

        let recentFiles = configManager.config.recentFiles
        registerUndo("Clear Recent Files") { target in
            target.configManager.config.recentFiles = recentFiles
            target.configManager.save()
            target.refreshPreferencesSnapshot()
        }
        closeFolderStack()
        configManager.config.recentFiles.removeAll()
        configManager.save()
        rebuildMenu()
    }

    private func confirmAndImportSystemDockApps(into id: UUID) {
        guard let dockIndex = configManager.config.docks.firstIndex(where: { $0.id == id }) else {
            return
        }

        let loadResult: SystemDockLoadResult
        do {
            loadResult = try SystemDockImporter.loadPinnedApps()
        } catch {
            showSystemDockImportNotice(
                title: "Couldn’t Read the macOS Dock",
                message: error.localizedDescription
            )
            return
        }

        guard !loadResult.apps.isEmpty else {
            let unavailableDetail = loadResult.unavailableCount > 0
                ? " \(loadResult.unavailableCount) pinned app\(loadResult.unavailableCount == 1 ? " is" : "s are") no longer available."
                : ""
            showSystemDockImportNotice(
                title: "No Apps Found",
                message: "FreeDock couldn’t find any installed apps pinned in the macOS Dock.\(unavailableDetail)"
            )
            return
        }

        let dock = configManager.config.docks[dockIndex]
        let plan = SystemDockImporter.planImport(
            apps: loadResult.apps,
            existingItems: dock.items
        )
        guard !plan.items.isEmpty else {
            let unavailableDetail = loadResult.unavailableCount > 0
                ? " \(loadResult.unavailableCount) unavailable app\(loadResult.unavailableCount == 1 ? " was" : "s were") skipped."
                : ""
            showSystemDockImportNotice(
                title: "Already Up to Date",
                message: "Every available app from the macOS Dock is already in “\(dock.name)”.\(unavailableDetail)"
            )
            return
        }

        let count = plan.items.count
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.messageText = "Import \(count) app\(count == 1 ? "" : "s") into “\(dock.name)”?"
        var details = "The apps will be added after the dock’s existing items. Nothing will be replaced, and the macOS Dock will not be changed."
        if plan.skippedCount > 0 {
            details += " \(plan.skippedCount) app\(plan.skippedCount == 1 ? " was" : "s were") skipped because \(plan.skippedCount == 1 ? "it is" : "they are") already present."
        }
        if loadResult.unavailableCount > 0 {
            details += " \(loadResult.unavailableCount) unavailable app\(loadResult.unavailableCount == 1 ? " was" : "s were") skipped."
        }
        alert.informativeText = details
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Import")
        guard alert.runModal() == .alertSecondButtonReturn else { return }

        let previous = dock
        var updated = dock
        updated.items.append(contentsOf: plan.items)
        configManager.config.docks[dockIndex] = updated
        preferencesStore?.replaceDock(updated)
        reconcileDockRuntime(from: previous, to: updated)
        configManager.save()
        refreshPreferencesSnapshot()

        var resultMessage = "Added \(count) app\(count == 1 ? "" : "s") to “\(dock.name)”."
        if plan.skippedCount > 0 {
            resultMessage += " \(plan.skippedCount) app\(plan.skippedCount == 1 ? " was" : "s were") already present."
        }
        if loadResult.unavailableCount > 0 {
            resultMessage += " \(loadResult.unavailableCount) unavailable app\(loadResult.unavailableCount == 1 ? " was" : "s were") skipped."
        }
        let completedMessage = resultMessage
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            self?.showSystemDockImportNotice(
                title: "Import Complete",
                message: completedMessage
            )
        }
    }

    private func showSystemDockImportNotice(title: String, message: String) {
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func confirmAndResetDockSettings(_ id: UUID) {
        guard let dock = configManager.config.docks.first(where: { $0.id == id }) else { return }

        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.alertStyle = .warning
        alert.messageText = "Reset settings for “\(dock.name)”?"
        alert.informativeText = "Appearance, icon layout, orientation, indicators, and auto-hide will return to their defaults. The dock’s name, pinned items, and saved position will stay unchanged."
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
        alert.informativeText = "This replaces the visible settings on \(targetIDs.count) other dock\(targetIDs.count == 1 ? "" : "s") in the current profile. Dock names, pinned items, and saved positions will stay unchanged."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Copy")
        guard alert.runModal() == .alertSecondButtonReturn else { return }

        applyDockSettings(source.settings, to: Set(targetIDs))
    }

    private func promptToSaveDockTheme(from dockID: UUID) {
        guard let dock = configManager.config.docks.first(where: {
            $0.id == dockID
        }) else { return }
        var proposedValue = "\(dock.name) Style"

        while true {
            let alert = NSAlert()
            alert.icon = NSApp.applicationIconImage
            alert.messageText = "Save Appearance Theme"
            alert.informativeText = "Save this dock’s style, opacity, blur, corners, and shadow for reuse on any dock or profile."
            let field = NSTextField(
                frame: NSRect(x: 0, y: 0, width: 240, height: 24)
            )
            field.stringValue = proposedValue
            field.selectText(nil)
            alert.accessoryView = field
            alert.addButton(withTitle: "Save")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }

            proposedValue = field.stringValue.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            if proposedValue.isEmpty {
                showThemeError("Theme names cannot be empty.")
                continue
            }
            let duplicate = configManager.config.themes.contains {
                $0.name.compare(
                    proposedValue,
                    options: [.caseInsensitive, .diacriticInsensitive]
                ) == .orderedSame
            }
            if duplicate {
                showThemeError("A theme named “\(proposedValue)” already exists.")
                continue
            }

            configManager.config.themes.append(
                DockTheme(name: proposedValue, dock: dock)
            )
            configManager.save()
            refreshPreferencesSnapshot()
            return
        }
    }

    private func applyDockTheme(_ themeID: UUID, to dockID: UUID) {
        guard let theme = configManager.config.themes.first(where: {
            $0.id == themeID
        }),
        let index = configManager.config.docks.firstIndex(where: {
            $0.id == dockID
        }) else { return }

        let previous = configManager.config.docks[index]
        var updated = previous
        theme.apply(to: &updated)
        guard updated != previous else { return }
        configManager.config.docks[index] = updated
        preferencesStore?.replaceDock(updated)
        reconcileDockRuntime(from: previous, to: updated)
        configManager.save()
        refreshPreferencesSnapshot()
    }

    private func confirmAndDeleteDockTheme(_ themeID: UUID) {
        guard let index = configManager.config.themes.firstIndex(where: {
            $0.id == themeID
        }) else { return }
        let theme = configManager.config.themes[index]
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.alertStyle = .warning
        alert.messageText = "Delete “\(theme.name)”?"
        alert.informativeText = "Docks already using this appearance will not change."
        alert.addButton(withTitle: "Cancel")
        let deleteButton = alert.addButton(withTitle: "Delete")
        deleteButton.hasDestructiveAction = true
        guard alert.runModal() == .alertSecondButtonReturn else { return }

        registerUndo("Delete Theme") { target in
            let insertionIndex = min(index, target.configManager.config.themes.count)
            target.configManager.config.themes.insert(theme, at: insertionIndex)
            target.configManager.save()
            target.refreshPreferencesSnapshot()
        }
        configManager.config.themes.remove(at: index)
        configManager.save()
        rebuildMenu()
    }

    private func showThemeError(_ message: String) {
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.alertStyle = .warning
        alert.messageText = "Theme Not Saved"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
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
        case .orientation, .magnificationEnabled, .magnification,
             .itemSpacing, .appearance, .surfaceOpacity, .blurStyle,
             .cornerRadius, .shadowStrength, .showRunningIndicators,
             .showDynamicApplications, .dynamicApplicationLimit,
             .autoHideDelay:
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
            || previous.magnificationEnabled != updated.magnificationEnabled
            || previous.magnification != updated.magnification
            || previous.itemSpacing != updated.itemSpacing
            || previous.items != updated.items
            || previous.showDynamicApplications
                != updated.showDynamicApplications
            || previous.dynamicApplicationLimit
                != updated.dynamicApplicationLimit
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
                self.updateAutoHideGeometry(for: panel)
                if panel.autoHideWhenDocked {
                    panel.scheduleAutoHide()
                }
            }

            _ = self.persistPanelPlacement(panel, userInitiated: false)
            self.configManager.save()
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

    private func cancelDockResizeWork(for dockID: UUID) {
        dockResizeWorkItems[dockID]?.cancel()
        dockResizeWorkItems.removeValue(forKey: dockID)
        liveDockResizeWorkItems[dockID]?.cancel()
        liveDockResizeWorkItems.removeValue(forKey: dockID)
        dockResizeFinishWorkItems[dockID]?.cancel()
        dockResizeFinishWorkItems.removeValue(forKey: dockID)
        activeDockResizeIDs.remove(dockID)
    }

    private func updateAutoHideRuntime(
        for dockID: UUID,
        enabled: Bool,
        orientation: Orientation
    ) {
        guard let panel = dockPanels[dockID] else { return }

        if !enabled {
            panel.revealImmediately()
        }
        panel.autoHideWhenDocked = enabled
        guard enabled else {
            _ = persistPanelPlacement(panel, userInitiated: false)
            configManager.save()
            return
        }

        panel.revealImmediately()
        let screen = effectiveScreen(for: panel)
        let dockedFrame = frameDockedToNearestEdge(
            panel.frameForPersistence,
            orientation: orientation,
            on: screen
        )
        panel.setFrame(dockedFrame, display: true, animate: true)
        _ = persistPanelPlacement(panel, userInitiated: false)
        configManager.save()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            [weak self, weak panel] in
            guard let self, let panel else { return }
            self.updateAutoHideGeometry(for: panel)
            panel.scheduleAutoHide()
        }
    }

    private func rebuildVisibleDock(_ dockID: UUID, using config: DockConfig) {
        guard let panel = dockPanels[dockID] else { return }

        windowPreviewController.close(
            forDockID: dockID,
            resetNativeController: false
        )
        endQuickLaunch(
            ifDockID: dockID,
            reactivatePreviousApplication: false
        )
        closeFolderStack(for: dockID)
        cancelDockResizeWork(for: dockID)
        pendingAutoHideUpdates.removeValue(forKey: dockID)
        _ = persistPanelPlacement(panel, userInitiated: false)
        panel.revealImmediately()
        panel.tearDown()
        dockPanels.removeValue(forKey: dockID)
        dockStates.removeValue(forKey: dockID)
        runtimeDisplayStates.removeValue(forKey: dockID)

        let rebuiltConfig = configManager.config.docks.first(where: {
            $0.id == dockID
        }) ?? config
        showDock(rebuiltConfig)
    }

    private func showDock(_ config: DockConfig) {
        let rect = NSRect(origin: config.position,
                          size: NSSize(width: 400, height: 70))
        let panel = DockPanel(dockID: config.id, contentRect: rect)

        let dockID = config.id
        let state = DockState(config: config)
        dockStates[config.id] = state

        let content = DockContentView(
            panel: panel,
            profileID: configManager.config.activeProfileID,
            items: Binding(
                get: { self.configManager.config.docks.first(where: { $0.id == dockID })?.items ?? [] },
                set: { newItems in
                    self.replaceDockItems(newItems, for: dockID)
                }
            ),
            orientation: config.orientation,
            state: state,
            itemDragCoordinator: itemDragCoordinator,
            onItemActivation: { [weak self, weak panel] item, sourceRect in
                guard let self, let panel else { return }
                let restoredHiddenProfile = self.endQuickLaunch(
                    ifDockID: dockID,
                    reactivatePreviousApplication: false,
                    restoreHiddenProfile: false
                )
                if restoredHiddenProfile, item.kind == .folder {
                    self.hideRestoredDocksAfterFolderStack = true
                }
                self.activateDockItem(
                    item,
                    sourceRect: sourceRect,
                    in: panel
                )
                if restoredHiddenProfile
                    && (
                        item.kind != .folder
                            || self.folderStackController == nil
                    )
                {
                    self.hideDocksRestoredForQuickLaunch()
                }
            },
            onItemTransfer: { [weak self] session, destination, operation in
                guard let self else { return false }
                return self.transferDockItem(
                    session,
                    to: dockID,
                    destination: destination,
                    operation: operation
                )
            },
            onQuickLaunchDismiss: { [weak self] in
                self?.endQuickLaunch(
                    ifDockID: dockID,
                    reactivatePreviousApplication: true
                )
            },
            onAddItemsRequested: { [weak self] in
                self?.chooseDockItems(for: dockID)
            },
            onAddSmartStackRequested: { [weak self] source in
                self?.addSmartStack(source, to: dockID)
            },
            onFolderOptionsChanged: { [weak self] itemID, options in
                self?.updateFolderStackOptions(
                    options,
                    for: itemID,
                    in: dockID
                )
            },
            hasRecentFiles: { [weak self] in
                !(self?.configManager.config.recentFiles.isEmpty ?? true)
            },
            onClearRecentFilesRequested: { [weak self] in
                self?.confirmAndClearRecentFiles()
            },
            onOpenDocumentWithApplication: {
                [weak self] item, applicationURL in
                self?.openThroughFreeDock(
                    URL(fileURLWithPath: item.path),
                    withApplicationAt: applicationURL
                )
            },
            onOpenFilesWithApplication: {
                [weak self] item, fileURLs in
                guard let self,
                      let applicationURL = item.fileURL
                else {
                    return false
                }
                return self.openFilesThroughFreeDock(
                    fileURLs,
                    withApplicationAt: applicationURL,
                    applicationName: item.label,
                    presentsValidationErrors: false
                )
            },
            onCanOpenFilesWithApplication: {
                [weak self] item, fileURLs in
                guard let self,
                      let applicationURL = item.fileURL
                else {
                    return false
                }
                return self.canOpenFilesThroughFreeDock(
                    fileURLs,
                    withApplicationAt: applicationURL,
                    applicationName: item.label
                )
            },
            onChooseFilesForApplication: {
                [weak self, weak panel] item in
                guard let self, let panel else { return }
                self.chooseFilesToOpen(
                    with: item,
                    from: panel
                )
            },
            onCanMoveFilesToTrash: { urls in
                TrashController.canRecycle(urls)
            },
            onMoveFilesToTrash: { [weak self] urls in
                TrashController.recycle(urls) { errorMessage in
                    guard let errorMessage else { return }
                    self?.showTrashError(
                        title: "Some Items Couldn’t Be Moved to Trash",
                        message: errorMessage
                    )
                }
            },
            onEmptyTrashRequested: { [weak self] in
                self?.confirmAndEmptyTrash()
            },
            onRenameItemRequested: { [weak self] item in
                self?.promptToRenameDockItem(item, in: dockID)
            },
            onChooseCustomIconRequested: { [weak self] item in
                self?.chooseCustomIcon(for: item, in: dockID)
            },
            onRestoreOriginalIconRequested: { [weak self] item in
                self?.updateCustomIcon(nil, for: item.id, in: dockID)
            },
            onApplicationHoverChanged: {
                [weak self, weak panel] item, sourceRect, hovering in
                guard let self, let panel else { return }
                if hovering {
                    self.windowPreviewController.hoverBegan(
                        item: item,
                        presentation:
                            DockItemPresentation.resolve(item),
                        sourceRect: sourceRect,
                        sourceDock: panel
                    )
                } else {
                    self.windowPreviewController.hoverEnded(
                        itemID: item.id
                    )
                }
            },
            onShowApplicationWindows: {
                [weak self, weak panel] item, sourceRect in
                guard let self, let panel else { return }
                self.windowPreviewController.showExplicit(
                    item: item,
                    presentation:
                        DockItemPresentation.resolve(item),
                    sourceRect: sourceRect,
                    sourceDock: panel
                )
            },
            onEnableWindowThumbnails: { [weak self] in
                self?.windowPreviewController
                    .enableWindowThumbnails()
            },
            isWindowPreviewAccessibilityTrusted: {
                [weak self] in
                self?.windowPreviewController
                    .isAccessibilityTrusted ?? false
            },
            isWindowPreviewScreenCaptureTrusted: {
                [weak self] in
                self?.windowPreviewController
                    .isScreenCaptureTrusted ?? false
            },
            onDismissWindowPreview: { [weak self] in
                self?.windowPreviewController.close(
                    forDockID: dockID,
                    resetNativeController: false
                )
            }
        )

        panel.dockOrientation = config.orientation
        panel.autoHideDelay = config.autoHideDelay
        panel.autoHideWhenDocked = config.autoHideWhenDocked
        panel.setContentView(content)
        panel.dockDelegate = self
        panel.setPositionLocked(_lockPositions)
        dockPanels[config.id] = panel

        if let resolution = displayResolution(
            for: config,
            panelFrame: panel.frameForPersistence
        ) {
            placePanel(
                panel,
                using: config,
                on: resolution.screen,
                display: resolution.display,
                isFallback: resolution.isFallback,
                animate: false
            )
            if !resolution.isFallback {
                _ = mirrorPanelPosition(panel, on: resolution.display)
            }
        } else {
            panel.clampToVisibleFrame(on: DockDisplayManager.primaryScreen)
        }

        panel.orderFrontRegardless()
        configManager.save()
    }

    private func restoreDocks() {
        for dock in configManager.config.docks {
            showDock(dock)
        }
    }

    private func beginDockItemDragInteraction() {
        endDockItemDragInteraction()
        for (dockID, panel) in dockPanels {
            itemDragInteractionTokens[dockID] =
                panel.beginTransientInteraction()
        }
    }

    private func endDockItemDragInteraction() {
        let tokens = itemDragInteractionTokens
        itemDragInteractionTokens.removeAll()
        for (dockID, token) in tokens {
            dockPanels[dockID]?.endTransientInteraction(token)
        }
    }

    private func saveAllPositions() {
        endQuickLaunch(reactivatePreviousApplication: true)
        for panel in dockPanels.values {
            guard let display = DockDisplayGeometry.bestDisplay(
                for: panel.frameForPersistence,
                among: DockDisplayManager.connectedDisplays
            ) else {
                continue
            }
            _ = mirrorPanelPosition(panel, on: display)
        }
    }

    private func closeAllDockPanels() {
        TooltipManager.shared.hide()
        windowPreviewController.close(resetNativeController: true)
        itemDragCoordinator.cancel()
        hideRestoredDocksAfterFolderStack = false
        endQuickLaunch(reactivatePreviousApplication: false)
        closeFolderStack()
        for work in dockResizeWorkItems.values {
            work.cancel()
        }
        dockResizeWorkItems.removeAll()
        for work in liveDockResizeWorkItems.values {
            work.cancel()
        }
        liveDockResizeWorkItems.removeAll()
        for work in dockResizeFinishWorkItems.values {
            work.cancel()
        }
        dockResizeFinishWorkItems.removeAll()
        activeDockResizeIDs.removeAll()
        pendingAutoHideUpdates.removeAll()
        for panel in dockPanels.values {
            panel.tearDown()
        }
        dockPanels.removeAll()
        dockStates.removeAll()
        runtimeDisplayStates.removeAll()
    }
}

extension AppDelegate: DockPanelDelegate {
    var lockPositions: Bool {
        get { _lockPositions }
        set { _lockPositions = newValue }
    }

    func dockPanelDidMove(_ panel: DockPanel) {
        windowPreviewController.close(
            forDockID: panel.dockID,
            resetNativeController: false
        )
        closeFolderStack(for: panel.dockID)
        let screen = DockDisplayManager.screen(containing: panel.frame)
        let snapped = panel.autoHideWhenDocked
            ? frameDockedToNearestEdge(
                panel.frame,
                orientation: panel.dockOrientation,
                on: screen
            )
            : snapFrame(panel.frame, on: screen)

        if snapped.origin != panel.frame.origin {
            panel.setFrame(snapped, display: true, animate: true)
        }

        if let screen,
           let display = DockDisplayManager.descriptor(for: screen)
        {
            runtimeDisplayStates[panel.dockID] = RuntimeDisplayState(
                effectiveDisplayID: display.id,
                isUsingFallback: false
            )
            updateAutoHideGeometry(for: panel, on: display)
        } else {
            updateAutoHideGeometry(for: panel)
        }
        _ = persistPanelPlacement(panel, userInitiated: true)
        configManager.save()
        refreshPreferencesSnapshot()
    }

    func dockPanelDidResignKey(_ panel: DockPanel) {
        endQuickLaunch(
            ifDockID: panel.dockID,
            reactivatePreviousApplication: false
        )
    }

    func dockPanelMenuDidBeginTracking(_ panel: DockPanel) {
        windowPreviewController.close(
            forDockID: panel.dockID,
            resetNativeController: false
        )
    }

    func currentIconSize(for panel: DockPanel) -> Double {
        dockStates[panel.dockID]?.iconSize ?? 48
    }

    func dockPanelDidResize(_ panel: DockPanel, proposedIconSize: Double) {
        let dockID = panel.dockID
        guard configManager.config.docks.contains(where: {
            $0.id == dockID
        }),
        let state = dockStates[dockID]
        else {
            return
        }

        if activeDockResizeIDs.insert(dockID).inserted {
            windowPreviewController.close(
                forDockID: dockID,
                resetNativeController: false
            )
            closeFolderStack(for: dockID)
            panel.revealImmediately()

            // A handle drag owns geometry until mouse-up. Letting a delayed
            // Preferences resize fire in the middle of it makes the panel jump
            // and can persist a transient origin.
            dockResizeWorkItems[dockID]?.cancel()
            dockResizeWorkItems.removeValue(forKey: dockID)
            dockResizeFinishWorkItems[dockID]?.cancel()
            dockResizeFinishWorkItems.removeValue(forKey: dockID)
        }

        let liveIconSize = DockConfig.clamp(
            proposedIconSize,
            to: DockConfig.iconSizeRange
        )
        guard state.iconSize != liveIconSize else { return }

        // Only publish the property which drives the live layout. The normal
        // preference pipeline republishes every DockState property, refreshes
        // Preferences, schedules persistence, and starts a competing 35 ms
        // resize for every pointer event.
        state.iconSize = liveIconSize
        scheduleLiveDockResize(panel)
    }

    func dockPanelDidFinishResize(_ panel: DockPanel) {
        let dockID = panel.dockID
        let wasLiveResize = activeDockResizeIDs.remove(dockID) != nil
        liveDockResizeWorkItems[dockID]?.cancel()
        liveDockResizeWorkItems.removeValue(forKey: dockID)

        guard wasLiveResize else {
            finishDockResize(panel)
            return
        }

        commitLiveDockResizeIconSize(for: dockID)

        // Give SwiftUI one display tick to commit the final icon size before
        // measuring the hosting view, then persist exactly once.
        let work = DispatchWorkItem { [weak self, weak panel] in
            guard let self, let panel,
                  !self.activeDockResizeIDs.contains(dockID)
            else {
                return
            }
            self.dockResizeFinishWorkItems.removeValue(forKey: dockID)
            panel.resizeToFitContent()
            self.finishDockResize(panel)
        }
        dockResizeFinishWorkItems[dockID] = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + (1.0 / 60.0),
            execute: work
        )
    }

    private func commitLiveDockResizeIconSize(for dockID: UUID) {
        guard let index = configManager.config.docks.firstIndex(where: {
            $0.id == dockID
        }),
        let state = dockStates[dockID]
        else {
            return
        }

        var updated = configManager.config.docks[index]
        updated.apply(.iconSize(
            DockResizeGestureMath.committedIconSize(state.iconSize)
        ))
        configManager.config.docks[index] = updated
        state.iconSize = updated.iconSize
    }

    private func scheduleLiveDockResize(_ panel: DockPanel) {
        let dockID = panel.dockID
        guard liveDockResizeWorkItems[dockID] == nil else { return }

        let work = DispatchWorkItem { [weak self, weak panel] in
            guard let self else { return }
            self.liveDockResizeWorkItems.removeValue(forKey: dockID)
            guard self.activeDockResizeIDs.contains(dockID),
                  let panel
            else {
                return
            }
            panel.resizeToFitContent()
        }
        liveDockResizeWorkItems[dockID] = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + (1.0 / 60.0),
            execute: work
        )
    }

    private func finishDockResize(_ panel: DockPanel) {
        let dockID = panel.dockID
        closeFolderStack(for: dockID)
        let snapped = snapFrame(
            panel.frame,
            on: effectiveScreen(for: panel)
        )
        if snapped.origin != panel.frame.origin {
            panel.setFrame(snapped, display: true, animate: true)
        }
        updateAutoHideGeometry(for: panel)
        _ = persistPanelPlacement(panel, userInitiated: false)
        configManager.save()
        refreshPreferencesSnapshot()
        scheduleMenuRefresh()

        if let pending = pendingAutoHideUpdates.removeValue(forKey: dockID) {
            updateAutoHideRuntime(
                for: dockID,
                enabled: pending.enabled,
                orientation: pending.orientation
            )
        } else if panel.autoHideWhenDocked {
            panel.scheduleAutoHide()
        }
    }
}
