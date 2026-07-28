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
                            Text(dock.orientation == .horizontal ? "Horizontal" : "Vertical")
                                .font(.caption)
                                .foregroundStyle(.secondary)
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
                            title: "Corner radius",
                            value: cornerRadiusBinding,
                            range: DockConfig.cornerRadiusRange,
                            step: 1,
                            valueText: "\(Int(dock.cornerRadius)) px"
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

                        sliderRow(
                            title: "Magnification",
                            value: magnificationBinding,
                            range: DockConfig.magnificationRange,
                            step: 0.05,
                            valueText: String(format: "%.2f×", dock.magnification)
                        )

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
                        title: "Behavior",
                        symbol: "cursorarrow.motionlines"
                    ) {
                        settingRow("Orientation") {
                            Picker("Orientation", selection: orientationBinding) {
                                Label("Horizontal", systemImage: "rectangle.split.3x1").tag(Orientation.horizontal)
                                Label("Vertical", systemImage: "rectangle.split.1x2").tag(Orientation.vertical)
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(width: 250)
                        }

                        Divider()

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
                }
                .padding(28)
                .frame(maxWidth: 760, alignment: .leading)
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(.secondary)
                Text("Select a Dock")
                    .font(.title2.weight(.semibold))
                Text("Choose a dock in the sidebar to customize it.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    private var orientationBinding: Binding<Orientation> {
        Binding(
            get: { store.selectedDock?.orientation ?? .horizontal },
            set: { store.updateSelected(.orientation($0)) }
        )
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

    private var cornerRadiusBinding: Binding<Double> {
        Binding(
            get: { store.selectedDock?.cornerRadius ?? 18 },
            set: { store.updateSelected(.cornerRadius($0)) }
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
