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
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.didBecomeActiveNotification
            )
        ) { _ in
            store.refreshPermissions()
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

                    permissionsSection

                    settingsSection(
                        title: "Appearance",
                        symbol: "paintbrush.fill"
                    ) {
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

                    permissionsSection
                }
                .padding(28)
                .frame(maxWidth: 760, alignment: .leading)
            }
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
