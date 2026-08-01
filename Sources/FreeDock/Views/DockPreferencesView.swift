import AppKit
import SwiftUI

struct DockPreferencesView: View {
    @ObservedObject var store: DockPreferencesStore

    var body: some View {
        HSplitView {
            sidebar
                .frame(minWidth: 205, idealWidth: 225, maxWidth: 265)

            detail
                .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 700, minHeight: 500)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            store.refreshPermissions()
            store.refreshLaunchAtLogin()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.didBecomeActiveNotification
            )
        ) { _ in
            store.refreshPermissions()
            store.refreshLaunchAtLogin()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            profileHeader

            Divider()

            dockBrowser

            Divider()

            sidebarToolbar
        }
    }

    private var profileHeader: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("PROFILE")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 7) {
                Menu {
                    ForEach(store.profiles) { profile in
                        Button {
                            store.perform(.activateProfile(profile.id))
                        } label: {
                            if profile.id == store.activeProfileID {
                                Label(profile.name, systemImage: "checkmark")
                            } else {
                                Text(profile.name)
                            }
                        }
                    }

                    Divider()

                    Button {
                        store.perform(.createProfile)
                    } label: {
                        Label("New Profile…", systemImage: "plus")
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "person.2.fill")
                            .foregroundStyle(.secondary)
                        Text(store.activeProfileName)
                            .font(.headline)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .accessibilityLabel("Choose Profile")

                Menu {
                    Button {
                        store.perform(.renameActiveProfile)
                    } label: {
                        Label("Rename Profile…", systemImage: "pencil")
                    }

                    Divider()

                    Button(role: .destructive) {
                        store.perform(.deleteActiveProfile)
                    } label: {
                        Label("Delete Profile…", systemImage: "trash")
                    }
                    .disabled(!store.canDeleteActiveProfile)

                    Divider()

                    Button {
                        store.perform(.exportConfiguration)
                    } label: {
                        Label("Export Configuration…", systemImage: "square.and.arrow.up")
                    }

                    Button {
                        store.perform(.importConfiguration)
                    } label: {
                        Label("Import Configuration…", systemImage: "square.and.arrow.down")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 15))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Manage Current Profile")
                .accessibilityLabel("Manage Current Profile")
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 15)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var dockBrowser: some View {
        if store.docks.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "dock.rectangle")
                    .font(.system(size: 24))
                    .foregroundStyle(.secondary)
                Text("No docks in this profile")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Text("Use + below to create one.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        } else {
            List(selection: $store.selectedDockID) {
                ForEach(store.docks) { dock in
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(dock.name)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .help(dock.name)
                            Text(dockSubtitle(for: dock))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .help(dockSubtitle(for: dock))
                        }
                    } icon: {
                        Image(systemName: dock.orientation == .horizontal
                            ? "rectangle.bottomthird.inset.filled"
                            : "rectangle.leadingthird.inset.filled")
                    }
                    .tag(dock.id)
                    .contextMenu {
                        dockActions(for: dock.id)
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }

    private var sidebarToolbar: some View {
        HStack(spacing: 4) {
            Menu {
                Button {
                    store.perform(.createDock(.horizontal))
                } label: {
                    Label("Horizontal Dock", systemImage: "rectangle.split.3x1")
                }

                Button {
                    store.perform(.createDock(.vertical))
                } label: {
                    Label("Vertical Dock", systemImage: "rectangle.split.1x2")
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 24, height: 22)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("New Dock")
            .accessibilityLabel("New Dock")

            Spacer()

            if let dockID = store.selectedDockID {
                Menu {
                    dockActions(for: dockID)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 24, height: 22)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Manage Selected Dock")
                .accessibilityLabel("Manage Selected Dock")
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func dockActions(for dockID: UUID) -> some View {
        Button {
            store.perform(.renameDock(dockID))
        } label: {
            Label("Rename Dock…", systemImage: "pencil")
        }

        Button {
            store.perform(.duplicateDock(dockID))
        } label: {
            Label("Duplicate Dock", systemImage: "plus.square.on.square")
        }

        Divider()

        Button(role: .destructive) {
            store.perform(.deleteDock(dockID))
        } label: {
            Label("Delete Dock…", systemImage: "trash")
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let dock = store.selectedDock {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(dock.name)
                            .font(.system(size: 25, weight: .semibold))
                        Text("Changes apply to this dock immediately.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    generalSection

                    profileAutomationSection

                    permissionsSection

                    configurationSection

                    settingsSection(
                        title: "Appearance",
                        symbol: "paintbrush.fill"
                    ) {
                        VStack(alignment: .leading, spacing: 5) {
                            settingRow("Saved themes") {
                                Menu {
                                    ForEach(store.themes) { theme in
                                        Button(theme.name) {
                                            store.perform(
                                                .applyDockTheme(
                                                    themeID: theme.id,
                                                    dockID: dock.id
                                                )
                                            )
                                        }
                                    }
                                } label: {
                                    Text(
                                        store.themes.isEmpty
                                            ? "No Saved Themes"
                                            : "Apply Theme"
                                    )
                                    .frame(minWidth: 108)
                                }
                                .disabled(store.themes.isEmpty)

                                Button {
                                    store.perform(.saveDockTheme(dock.id))
                                } label: {
                                    Image(systemName: "plus")
                                }
                                .help("Save the current appearance as a theme")
                                .accessibilityLabel("Save current appearance theme")

                                if !store.themes.isEmpty {
                                    Menu {
                                        ForEach(store.themes) { theme in
                                            Button(
                                                "Delete \(theme.name)…",
                                                role: .destructive
                                            ) {
                                                store.perform(
                                                    .deleteDockTheme(theme.id)
                                                )
                                            }
                                        }
                                    } label: {
                                        Image(systemName: "ellipsis.circle")
                                    }
                                    .help("Manage saved themes")
                                    .accessibilityLabel("Manage saved themes")
                                }
                            }
                            Text(
                                "Themes reuse style, opacity, blur, corners, and shadow without changing dock contents or behavior."
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        }

                        Divider()

                        settingRow("Style") {
                            Picker("Style", selection: appearanceBinding) {
                                ForEach(DockAppearance.allCases, id: \.self) { appearance in
                                    Text(appearance.displayName).tag(appearance)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(width: 250)
                        }

                        Divider()

                        sliderRow(
                            title: "Opacity",
                            value: surfaceOpacityBinding,
                            range: DockConfig.surfaceOpacityRange,
                            step: 0.05,
                            valueText: String(format: "%.0f%%", dock.surfaceOpacity * 100)
                        )

                        Divider()

                        settingRow("Glass blur") {
                            Picker("Glass blur", selection: blurStyleBinding) {
                                ForEach(DockBlurStyle.allCases, id: \.self) { style in
                                    Text(style.displayName).tag(style)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(width: 250)
                        }
                        .disabled(dock.appearance != .glass)
                        .opacity(dock.appearance == .glass ? 1 : 0.48)

                        Divider()

                        sliderRow(
                            title: "Corner radius",
                            value: cornerRadiusBinding,
                            range: DockConfig.cornerRadiusRange,
                            step: 1,
                            valueText: "\(Int(dock.cornerRadius)) px"
                        )

                        Divider()

                        sliderRow(
                            title: "Shadow",
                            value: shadowStrengthBinding,
                            range: DockConfig.shadowStrengthRange,
                            step: 0.05,
                            valueText: String(format: "%.0f%%", dock.shadowStrength * 100)
                        )
                    }

                    settingsSection(
                        title: "Icons & Layout",
                        symbol: "square.grid.3x3.fill"
                    ) {
                        sliderRow(
                            title: "Icon size",
                            value: iconSizeBinding,
                            range: DockConfig.iconSizeRange,
                            step: 1,
                            valueText: "\(Int(dock.iconSize)) px"
                        )

                        Divider()

                        settingRow("Magnification") {
                            Toggle("", isOn: magnificationEnabledBinding)
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .accessibilityLabel("Magnification")
                        }

                        Divider()

                        sliderRow(
                            title: "Magnification scale",
                            value: magnificationBinding,
                            range: DockConfig.magnificationRange,
                            step: 0.05,
                            valueText: String(format: "%.2f×", dock.magnification)
                        )
                        .disabled(!dock.magnificationEnabled)
                        .opacity(dock.magnificationEnabled ? 1 : 0.48)

                        Divider()

                        sliderRow(
                            title: "Item spacing",
                            value: itemSpacingBinding,
                            range: DockConfig.itemSpacingRange,
                            step: 1,
                            valueText: "\(Int(dock.itemSpacing)) px"
                        )

                        Divider()

                        settingRow("Running indicators") {
                            Toggle("", isOn: runningIndicatorsBinding)
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .accessibilityLabel("Running indicators")
                        }
                    }

                    settingsSection(
                        title: "Placement",
                        symbol: "display.2"
                    ) {
                        VStack(alignment: .leading, spacing: 5) {
                            settingRow("Display") {
                                Picker(
                                    "Display",
                                    selection: displaySelectionBinding(for: dock)
                                ) {
                                    Text("Automatic").tag(UUID?.none)

                                    ForEach(store.displays) { display in
                                        Text(store.displayLabel(for: display))
                                        .tag(Optional(display.id))
                                    }

                                    if let placement = dock.displayPlacement,
                                       !store.isDisplayConnected(placement.displayID)
                                    {
                                        Label(
                                            "\(placement.displayName ?? "Display") — Not Connected",
                                            systemImage: "exclamationmark.triangle.fill"
                                        )
                                        .tag(Optional(placement.displayID))
                                        .disabled(true)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .frame(width: 250)
                            }

                            Text(displayHelpText(for: dock))
                                .font(.caption)
                                .foregroundStyle(
                                    isPreferredDisplayUnavailable(for: dock)
                                        ? Color.orange
                                        : Color.secondary
                                )
                        }

                        Divider()

                        settingRow("Orientation") {
                            Picker("Orientation", selection: orientationBinding) {
                                Label("Horizontal", systemImage: "rectangle.split.3x1").tag(Orientation.horizontal)
                                Label("Vertical", systemImage: "rectangle.split.1x2").tag(Orientation.vertical)
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(width: 250)
                        }
                    }

                    settingsSection(
                        title: "Behavior",
                        symbol: "cursorarrow.motionlines"
                    ) {
                        settingRow("Auto-hide at screen edge") {
                            Toggle("", isOn: autoHideBinding)
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .accessibilityLabel("Auto-hide at screen edge")
                        }

                        Divider()

                        sliderRow(
                            title: "Hide delay",
                            value: autoHideDelayBinding,
                            range: DockConfig.autoHideDelayRange,
                            step: 0.1,
                            valueText: String(format: "%.1f s", dock.autoHideDelay)
                        )
                        .disabled(!dock.autoHideWhenDocked)
                        .opacity(dock.autoHideWhenDocked ? 1 : 0.48)
                    }

                    settingsSection(
                        title: "Content",
                        symbol: "square.grid.3x3.fill"
                    ) {
                        let canAddRecentFilesStack =
                            DockItemPlanner.planAdding(
                                smartStack: .recentFiles,
                                to: dock.items
                            ).addedCount > 0
                        let canAddDownloadsStack =
                            DockItemPlanner.planAdding(
                                smartStack: .downloads,
                                to: dock.items
                            ).addedCount > 0
                        let canAddTrash = DockItemPlanner.planAddingTrash(
                            to: dock.items
                        ).addedCount > 0

                        VStack(alignment: .leading, spacing: 5) {
                            settingRow("Recent & running apps") {
                                Toggle("", isOn: dynamicApplicationsBinding)
                                    .labelsHidden()
                                    .toggleStyle(.switch)
                                    .accessibilityLabel("Recent and running apps")
                            }
                            Text(
                                "Adds unpinned running apps first, followed by apps recently observed by FreeDock. History stays local."
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        }

                        Divider()

                        settingRow("Maximum apps") {
                            Stepper(
                                "\(dock.dynamicApplicationLimit)",
                                value: dynamicApplicationLimitBinding,
                                in: 1 ... 10
                            )
                            .frame(width: 90)
                        }
                        .disabled(!dock.showDynamicApplications)
                        .opacity(dock.showDynamicApplications ? 1 : 0.48)

                        Divider()

                        actionRow(
                            title: "Trash",
                            description: "Open Trash, move dropped files into it, or empty it after confirmation.",
                            buttonTitle: canAddTrash ? "Add" : "Added",
                            isDisabled: !canAddTrash
                        ) {
                            store.perform(.addTrash(dock.id))
                        }

                        Divider()

                        actionRow(
                            title: "Recent Files stack",
                            description: "Shows documents opened through FreeDock. History stays local on this Mac.",
                            buttonTitle: canAddRecentFilesStack ? "Add" : "Added",
                            isDisabled: !canAddRecentFilesStack
                        ) {
                            store.perform(
                                .addSmartStack(dock.id, .recentFiles)
                            )
                        }

                        Divider()

                        actionRow(
                            title: "Downloads stack",
                            description: "Keeps your current Downloads folder one click away and updates automatically.",
                            buttonTitle: canAddDownloadsStack ? "Add" : "Added",
                            isDisabled: !canAddDownloadsStack
                        ) {
                            store.perform(
                                .addSmartStack(dock.id, .downloads)
                            )
                        }

                        Divider()

                        actionRow(
                            title: "Add files or folders",
                            description: "Pin applications and documents, or add a folder stack that stays in sync with Finder.",
                            buttonTitle: "Add…"
                        ) {
                            store.perform(.addDockItems(dock.id))
                        }

                        Divider()

                        actionRow(
                            title: "Import from macOS Dock",
                            description: "Append pinned apps that aren’t already here. Existing apps and separators stay unchanged.",
                            buttonTitle: "Import…"
                        ) {
                            store.perform(.importSystemDockApps(dock.id))
                        }

                        Divider()

                        actionRow(
                            title: "Clear Recent Files history",
                            description: "Removes FreeDock’s local recent-file list without deleting any files.",
                            buttonTitle: "Clear…"
                        ) {
                            store.perform(.clearRecentFiles)
                        }
                    }

                    settingsSection(
                        title: "Reuse & Reset",
                        symbol: "arrow.triangle.2.circlepath"
                    ) {
                        actionRow(
                            title: "Reset to defaults",
                            description: "Restore this dock’s standard appearance and behavior.",
                            buttonTitle: "Reset…"
                        ) {
                            store.perform(.resetDockSettings(dock.id))
                        }

                        Divider()

                        actionRow(
                            title: "Copy to other docks",
                            description: "Apply these settings to every other dock in this profile.",
                            buttonTitle: "Copy…",
                            isDisabled: !store.canCopySelectedDockSettings
                        ) {
                            store.perform(.copyDockSettingsToAll(dock.id))
                        }
                    }
                }
                .padding(28)
                .frame(maxWidth: 760, alignment: .leading)
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(spacing: 12) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 38, weight: .light))
                            .foregroundStyle(.secondary)
                        Text("Select a Dock")
                            .font(.title2.weight(.semibold))
                        Text(
                            "Choose a dock in the sidebar to customize it."
                        )
                        .foregroundStyle(.secondary)
                    }
                    .frame(
                        maxWidth: .infinity,
                        minHeight: 210,
                        alignment: .center
                    )

                    generalSection

                    profileAutomationSection

                    permissionsSection

                    configurationSection
                }
                .padding(28)
                .frame(maxWidth: 760, alignment: .leading)
            }
        }
    }

    private var profileAutomationSection: some View {
        settingsSection(
            title: "Profile Automation",
            symbol: "bolt.fill"
        ) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Activate “\(store.activeProfileName)” automatically")
                Text("Rules use public macOS app and display events and remain entirely on this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if store.activeProfileAutomationRules.isEmpty {
                Text("No automation rules for this profile.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(store.activeProfileAutomationRules) { rule in
                    Divider()
                    HStack(spacing: 10) {
                        Image(systemName: rule.triggerKind == .application
                            ? "app.fill"
                            : "display")
                            .foregroundStyle(.secondary)
                            .frame(width: 18)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(rule.label)
                                .lineLimit(1)
                            Text(rule.triggerKind == .application
                                ? "When this app becomes active"
                                : "When this display connects")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Toggle("Enable \(rule.label)", isOn: Binding(
                            get: { rule.isEnabled },
                            set: { enabled in
                                store.perform(.setProfileAutomationEnabled(
                                    profileID: store.activeProfileID,
                                    ruleID: rule.id,
                                    enabled: enabled
                                ))
                            }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)

                        Button(role: .destructive) {
                            store.perform(.deleteProfileAutomation(
                                profileID: store.activeProfileID,
                                ruleID: rule.id
                            ))
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Delete automation for \(rule.label)")
                    }
                }
            }

            Divider()

            HStack {
                Button("Add Application…") {
                    store.perform(.addProfileApplicationAutomation(
                        store.activeProfileID
                    ))
                }

                Menu("Add Display") {
                    ForEach(store.displays) { display in
                        Button(display.label) {
                            store.perform(.addProfileDisplayAutomation(
                                profileID: store.activeProfileID,
                                displayID: display.id
                            ))
                        }
                    }
                }
                .disabled(store.displays.isEmpty)

                Spacer()
            }
            .controlSize(.small)
        }
    }

    private var permissionsSection: some View {
        settingsSection(
            title: "Permissions",
            symbol: "lock.shield.fill"
        ) {
            Text(
                "Window discovery and thumbnails stay on this Mac. FreeDock never uploads window titles or images, and thumbnail images are cleared from memory when the preview closes."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            let presentations =
                store.permissionState.presentations
            ForEach(presentations) { presentation in
                permissionRow(presentation)

                if presentation.id != presentations.last?.id {
                    Divider()
                }
            }
        }
    }

    private var generalSection: some View {
        settingsSection(
            title: "General",
            symbol: "gearshape.fill"
        ) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Launch at login")
                    Text(
                        "Start FreeDock automatically after you sign in to this Mac."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                    if let error = store.launchAtLoginState.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if store.launchAtLoginState.needsApproval {
                        Button("Open Login Items Settings…") {
                            store.openLoginItemsSettings()
                        }
                        .buttonStyle(.link)
                        .controlSize(.small)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 5) {
                    Toggle("Launch at login", isOn: launchAtLoginBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .disabled(!store.launchAtLoginState.canChange)
                    Text(store.launchAtLoginState.statusLabel)
                        .font(.caption2)
                        .foregroundStyle(
                            store.launchAtLoginState.needsApproval
                                ? Color.orange
                                : Color.secondary
                        )
                }
            }

            Divider()

            shortcutRow(for: .showHideDocks)

            Divider()

            shortcutRow(for: .quickLaunch)

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Switch profiles")
                    Text("Assign a global shortcut to each workflow. Press Delete while recording to clear one.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ForEach(store.profiles) { profile in
                    profileShortcutRow(profile)
                }
            }

            if let error = store.shortcutError {
                Divider()

                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            HStack {
                Text("Click a shortcut, then type a new key combination.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Restore Defaults") {
                    store.resetGlobalShortcuts()
                }
                .controlSize(.small)
            }
        }
    }

    private func shortcutRow(for action: GlobalShortcutAction) -> some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text(action.title)
                Text(shortcutDescription(for: action))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ShortcutRecorderButton(
                shortcut: store.globalShortcuts.shortcut(for: action)
            ) { shortcut in
                store.updateGlobalShortcut(shortcut, for: action)
            }
            .frame(width: 135, height: 26)
        }
    }

    private func shortcutDescription(
        for action: GlobalShortcutAction
    ) -> String {
        switch action {
        case .showHideDocks:
            return "Toggle every dock in the active profile."
        case .quickLaunch:
            return "Search and open items from the nearest dock."
        }
    }

    private func profileShortcutRow(_ profile: DockProfile) -> some View {
        HStack(spacing: 18) {
            HStack(spacing: 7) {
                Image(systemName: profile.id == store.activeProfileID
                    ? "checkmark.circle.fill"
                    : "circle")
                    .foregroundStyle(profile.id == store.activeProfileID
                        ? Color.accentColor
                        : Color.secondary)
                Text(profile.name)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ShortcutRecorderButton(
                optionalShortcut: store.globalShortcuts.shortcut(
                    forProfile: profile.id
                )
            ) { shortcut in
                store.updateProfileShortcut(shortcut, for: profile.id)
            }
            .frame(width: 135, height: 26)
        }
        .padding(.leading, 10)
    }

    private var configurationSection: some View {
        settingsSection(
            title: "Backup & Restore",
            symbol: "externaldrive.fill"
        ) {
            actionRow(
                title: "Export configuration",
                description: "Save every profile, dock, pinned item, and recent-file entry as a portable JSON backup.",
                buttonTitle: "Export…"
            ) {
                store.perform(.exportConfiguration)
            }

            Divider()

            actionRow(
                title: "Import configuration",
                description: "Replace the current setup from a FreeDock JSON backup. Your existing setup is preserved in the automatic backup file.",
                buttonTitle: "Import…"
            ) {
                store.perform(.importConfiguration)
            }
        }
    }

    private func permissionRow(
        _ presentation: PreferencesPermissionPresentation
    ) -> some View {
        HStack(alignment: .top, spacing: 13) {
            Image(
                systemName: permissionSymbol(
                    for: presentation.permission
                )
            )
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(
                    Color.primary.opacity(0.055),
                    in: RoundedRectangle(
                        cornerRadius: 7,
                        style: .continuous
                    )
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(
                    permissionFeatureTitle(
                        for: presentation.permission
                    )
                )
                    .fontWeight(.medium)

                Text("macOS permission: \(presentation.title)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text(
                    permissionDescription(
                        for: presentation.permission
                    )
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 8) {
                permissionStatus(
                    presentation
                )

                Button(presentation.actionTitle) {
                    store.performPermissionAction(
                        presentation.permission
                    )
                }
                .controlSize(.small)
                .disabled(!presentation.isActionEnabled)
                .accessibilityLabel(
                    "\(presentation.actionTitle) for FreeDock"
                )

                if presentation.status == .notGranted {
                    Button("Open System Settings…") {
                        store.openPermissionSettings(
                            presentation.permission
                        )
                    }
                    .buttonStyle(.link)
                    .controlSize(.small)
                    .accessibilityLabel(
                        "Open \(presentation.title) settings"
                    )
                }
            }
            .frame(minWidth: 190, alignment: .trailing)
        }
    }

    private func permissionStatus(
        _ presentation: PreferencesPermissionPresentation
    ) -> some View {
        let color = permissionStatusColor(
            presentation.status
        )
        return Label(
            permissionStatusLabel(presentation.status),
            systemImage: permissionStatusSymbol(
                presentation.status
            )
        )
        .font(.caption.weight(.semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.11), in: Capsule())
        .accessibilityLabel(
            "\(presentation.title): \(permissionStatusLabel(presentation.status))"
        )
    }

    private func permissionFeatureTitle(
        for permission: PreferencesPermissionKind
    ) -> String {
        switch permission {
        case .accessibility:
            return "Window switching"
        case .screenRecording:
            return "Window thumbnails"
        }
    }

    private func permissionSymbol(
        for permission: PreferencesPermissionKind
    ) -> String {
        switch permission {
        case .accessibility:
            return "rectangle.stack.fill"
        case .screenRecording:
            return "rectangle.on.rectangle"
        }
    }

    private func permissionDescription(
        for permission: PreferencesPermissionKind
    ) -> String {
        switch permission {
        case .accessibility:
            return "Required for window switching. Lets FreeDock find and bring forward an app’s windows across Desktops. It does not read what you type."
        case .screenRecording:
            return "Optional. Shows the current content of each window, including windows on other Desktops. Window switching still works without it. Each browser window reflects its selected tab; inactive tabs are not captured separately. macOS may require FreeDock to reopen after approval."
        }
    }

    private func permissionStatusLabel(
        _ status: PreferencesPermissionStatus
    ) -> String {
        switch status {
        case .checking:
            return "Checking…"
        case .notGranted:
            return "Needs Access"
        case .granted:
            return "Granted"
        }
    }

    private func permissionStatusSymbol(
        _ status: PreferencesPermissionStatus
    ) -> String {
        switch status {
        case .checking:
            return "ellipsis.circle.fill"
        case .notGranted:
            return "exclamationmark.circle.fill"
        case .granted:
            return "checkmark.circle.fill"
        }
    }

    private func permissionStatusColor(
        _ status: PreferencesPermissionStatus
    ) -> Color {
        switch status {
        case .checking:
            return .secondary
        case .notGranted:
            return .orange
        case .granted:
            return .green
        }
    }

    private func settingsSection<Content: View>(
        title: String,
        symbol: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol)
                .font(.headline)
                .foregroundStyle(.primary)

            VStack(spacing: 13) {
                content()
            }
            .padding(15)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.09), lineWidth: 1)
            )
        }
    }

    private func settingRow<Content: View>(
        _ title: String,
        @ViewBuilder control: () -> Content
    ) -> some View {
        HStack(spacing: 20) {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
            control()
        }
    }

    private func sliderRow(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        valueText: String
    ) -> some View {
        HStack(spacing: 14) {
            Text(title)
                .frame(width: 115, alignment: .leading)
            Slider(value: value, in: range, step: step)
                .accessibilityLabel(title)
                .accessibilityValue(valueText)
            Text(valueText)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .trailing)
        }
    }

    private func actionRow(
        title: String,
        description: String,
        buttonTitle: String,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(buttonTitle, action: action)
                .frame(width: 76)
                .disabled(isDisabled)
        }
    }

    private var orientationBinding: Binding<Orientation> {
        Binding(
            get: { store.selectedDock?.orientation ?? .horizontal },
            set: { store.updateSelected(.orientation($0)) }
        )
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { store.launchAtLoginState.isEnabled },
            set: { store.setLaunchAtLoginEnabled($0) }
        )
    }

    private var dynamicApplicationsBinding: Binding<Bool> {
        Binding(
            get: { store.selectedDock?.showDynamicApplications ?? false },
            set: { store.updateSelected(.showDynamicApplications($0)) }
        )
    }

    private var dynamicApplicationLimitBinding: Binding<Int> {
        Binding(
            get: { store.selectedDock?.dynamicApplicationLimit ?? 5 },
            set: { store.updateSelected(.dynamicApplicationLimit($0)) }
        )
    }

    private func displaySelectionBinding(for dock: DockConfig) -> Binding<UUID?> {
        Binding(
            get: { store.selectedDock?.displayPlacement?.displayID },
            set: { store.perform(.setDockDisplay(dock.id, $0)) }
        )
    }

    private func isPreferredDisplayUnavailable(for dock: DockConfig) -> Bool {
        guard let displayID = dock.displayPlacement?.displayID else { return false }
        return !store.isDisplayConnected(displayID)
    }

    private func dockSubtitle(for dock: DockConfig) -> String {
        let orientation = dock.orientation == .horizontal
            ? "Horizontal"
            : "Vertical"
        return "\(orientation) · \(store.displayLabel(for: dock))"
    }

    private func displayHelpText(for dock: DockConfig) -> String {
        if isPreferredDisplayUnavailable(for: dock) {
            return "Temporarily shown on the main display. It will return when this display reconnects."
        }
        if dock.displayPlacement == nil {
            return "Uses the display where this dock is currently positioned."
        }
        return "Keeps this dock on the selected display."
    }

    private var iconSizeBinding: Binding<Double> {
        Binding(
            get: { store.selectedDock?.iconSize ?? 48 },
            set: { store.updateSelected(.iconSize($0)) }
        )
    }

    private var magnificationBinding: Binding<Double> {
        Binding(
            get: { store.selectedDock?.magnification ?? 1.30 },
            set: { store.updateSelected(.magnification($0)) }
        )
    }

    private var magnificationEnabledBinding: Binding<Bool> {
        Binding(
            get: { store.selectedDock?.magnificationEnabled ?? true },
            set: { store.updateSelected(.magnificationEnabled($0)) }
        )
    }

    private var itemSpacingBinding: Binding<Double> {
        Binding(
            get: { store.selectedDock?.itemSpacing ?? 3 },
            set: { store.updateSelected(.itemSpacing($0)) }
        )
    }

    private var appearanceBinding: Binding<DockAppearance> {
        Binding(
            get: { store.selectedDock?.appearance ?? .glass },
            set: { store.updateSelected(.appearance($0)) }
        )
    }

    private var surfaceOpacityBinding: Binding<Double> {
        Binding(
            get: { store.selectedDock?.surfaceOpacity ?? 1 },
            set: { store.updateSelected(.surfaceOpacity($0)) }
        )
    }

    private var blurStyleBinding: Binding<DockBlurStyle> {
        Binding(
            get: { store.selectedDock?.blurStyle ?? .regular },
            set: { store.updateSelected(.blurStyle($0)) }
        )
    }

    private var cornerRadiusBinding: Binding<Double> {
        Binding(
            get: { store.selectedDock?.cornerRadius ?? 18 },
            set: { store.updateSelected(.cornerRadius($0)) }
        )
    }

    private var shadowStrengthBinding: Binding<Double> {
        Binding(
            get: { store.selectedDock?.shadowStrength ?? 1 },
            set: { store.updateSelected(.shadowStrength($0)) }
        )
    }

    private var runningIndicatorsBinding: Binding<Bool> {
        Binding(
            get: { store.selectedDock?.showRunningIndicators ?? true },
            set: { store.updateSelected(.showRunningIndicators($0)) }
        )
    }

    private var autoHideBinding: Binding<Bool> {
        Binding(
            get: { store.selectedDock?.autoHideWhenDocked ?? true },
            set: { store.updateSelected(.autoHideWhenDocked($0)) }
        )
    }

    private var autoHideDelayBinding: Binding<Double> {
        Binding(
            get: { store.selectedDock?.autoHideDelay ?? 1 },
            set: { store.updateSelected(.autoHideDelay($0)) }
        )
    }
}
