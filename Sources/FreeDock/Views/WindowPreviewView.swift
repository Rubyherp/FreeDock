import AppKit
import SwiftUI

enum WindowPreviewThumbnailState: Equatable, Sendable {
    case permissionRequired
    case loading
    case available
    case unavailable

    static func resolve(
        hasThumbnail: Bool,
        isCaptureEnabled: Bool,
        isLoading: Bool,
        isUnavailable: Bool,
        hasCaptureWindow: Bool
    ) -> WindowPreviewThumbnailState {
        guard isCaptureEnabled else {
            return .permissionRequired
        }
        if hasThumbnail {
            return .available
        }
        if isLoading {
            return .loading
        }
        if isUnavailable || !hasCaptureWindow {
            return .unavailable
        }
        // Capture begins immediately after the panel is presented. Treat the
        // brief interval before its task is registered as loading rather than
        // showing an unexplained app-icon placeholder.
        return .loading
    }
}

struct WindowPreviewView: View {
    let applicationName: String
    let applicationIcon: NSImage
    let windows: [DockApplicationWindow]
    let thumbnails: [DockApplicationWindow.ID: NSImage]
    let thumbnailLoadingIDs: Set<DockApplicationWindow.ID>
    let thumbnailUnavailableIDs: Set<DockApplicationWindow.ID>
    let isThumbnailCaptureEnabled: Bool
    let keyboardSelectedWindowID: DockApplicationWindow.ID?
    let onWindowSelected: (DockApplicationWindow.ID) -> Void
    let onEnableWindowThumbnails: () -> Void
    let onHoverChanged: (Bool) -> Void
    let onClose: () -> Void

    @Environment(\.accessibilityReduceTransparency)
    private var reduceTransparency
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            header

            ScrollViewReader { scrollProxy in
                ScrollView(
                    .horizontal,
                    showsIndicators: windows.count > 3
                ) {
                    HStack(spacing: 8) {
                        ForEach(windows) { window in
                            windowCard(window)
                                .id(window.id)
                        }
                    }
                    .padding(.bottom, windows.count > 3 ? 5 : 0)
                }
                .onAppear {
                    scrollToKeyboardSelection(
                        with: scrollProxy
                    )
                }
                .onChange(of: keyboardSelectedWindowID) { _ in
                    scrollToKeyboardSelection(
                        with: scrollProxy
                    )
                }
                .onChange(of: windows.map(\.id)) { _ in
                    scrollToKeyboardSelection(
                        with: scrollProxy
                    )
                }
            }
        }
        .padding(10)
        .background(panelBackground)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 14,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 14,
                style: .continuous
            )
            .strokeBorder(.white.opacity(0.22), lineWidth: 0.75)
        }
        .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
        .contentShape(Rectangle())
        .onHover(perform: onHoverChanged)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(applicationName) windows")
    }

    private var header: some View {
        HStack(spacing: 7) {
            Image(nsImage: applicationIcon)
                .resizable()
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)

            Text(applicationName)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .help(applicationName)

            Text("\(windows.count)")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.primary.opacity(0.07), in: Capsule())
                .accessibilityLabel(
                    "\(windows.count) \(windows.count == 1 ? "window" : "windows")"
                )

            Spacer(minLength: 8)

            if !isThumbnailCaptureEnabled {
                Button(action: onEnableWindowThumbnails) {
                    Image(systemName: "rectangle.on.rectangle")
                        .font(.system(size: 10, weight: .medium))
                        .frame(width: 20, height: 20)
                        .background(
                            Color.accentColor.opacity(0.14),
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                .help(
                    "Enable Window Thumbnails using Screen Recording. Each thumbnail shows the window’s current content."
                )
                .accessibilityLabel("Enable Window Thumbnails")
                .accessibilityHint(
                    "Requests macOS Screen Recording permission."
                )
            }

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 18, height: 18)
                    .background(.primary.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Close window previews")
            .accessibilityLabel("Close window previews")
        }
        .foregroundStyle(.primary)
    }

    private func windowCard(
        _ window: DockApplicationWindow
    ) -> some View {
        let thumbnailState = thumbnailState(for: window)
        return Button {
            onWindowSelected(window.id)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(.black.opacity(0.18))

                    if thumbnailState == .available,
                       let thumbnail = thumbnails[window.id]
                    {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(
                                maxWidth: .infinity,
                                maxHeight: .infinity
                            )
                            .background(.black.opacity(0.2))
                            .accessibilityHidden(true)
                    } else {
                        placeholder(for: thumbnailState)
                    }

                    if window.isMinimized
                        || window.isApplicationHidden
                        || window.isOnScreen == false
                    {
                        statusBadge(for: window)
                            .frame(
                                maxWidth: .infinity,
                                maxHeight: .infinity,
                                alignment: .bottomTrailing
                            )
                            .padding(7)
                    }

                    if window.isFocused || window.isMain {
                        currentWindowBadge
                            .frame(
                                maxWidth: .infinity,
                                maxHeight: .infinity,
                                alignment: .topLeading
                            )
                            .padding(7)
                    }

                    if !window.canFocusExactly {
                        fallbackFocusBadge
                            .frame(
                                maxWidth: .infinity,
                                maxHeight: .infinity,
                                alignment: .bottomLeading
                            )
                            .padding(7)
                    }
                }
                .frame(width: 166, height: 96)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 9,
                        style: .continuous
                    )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: 9,
                        style: .continuous
                    )
                    .strokeBorder(
                        Color.primary.opacity(0.12),
                        lineWidth: 0.75
                    )
                }

                Text(window.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(width: 166, alignment: .leading)
            }
            .padding(4)
            .contentShape(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
            )
            .background {
                RoundedRectangle(
                    cornerRadius: 11,
                    style: .continuous
                )
                .fill(
                    isKeyboardSelected(window)
                        ? Color.primary.opacity(0.09)
                        : .clear
                )
            }
            .overlay {
                RoundedRectangle(
                    cornerRadius: 11,
                    style: .continuous
                )
                .strokeBorder(
                    isKeyboardSelected(window)
                        ? Color.primary.opacity(0.30)
                        : .clear,
                    lineWidth: 1
                )
            }
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(windowHelp(window))
        .accessibilityLabel(window.title)
        .accessibilityValue(windowAccessibilityValue(window))
        .accessibilityHint(windowAccessibilityHint(window))
        .accessibilityAddTraits(
            isKeyboardSelected(window) ? .isSelected : []
        )
    }

    private func statusBadge(
        for window: DockApplicationWindow
    ) -> some View {
        Label(
            windowStatusLabel(window),
            systemImage: windowStatusIcon(window)
        )
        .font(.system(size: 9, weight: .semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(.black.opacity(0.72), in: Capsule())
        .accessibilityHidden(true)
    }

    private var currentWindowBadge: some View {
        Label("Current", systemImage: "checkmark")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(.black.opacity(0.72), in: Capsule())
            .accessibilityHidden(true)
    }

    private var fallbackFocusBadge: some View {
        Text("App only")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(.black.opacity(0.72), in: Capsule())
            .accessibilityHidden(true)
    }

    private func placeholder(
        for state: WindowPreviewThumbnailState
    ) -> some View {
        ZStack {
            LinearGradient(
                colors: [
                    .primary.opacity(0.10),
                    .primary.opacity(0.035),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(spacing: 7) {
                Image(nsImage: applicationIcon)
                    .resizable()
                    .frame(width: 38, height: 38)
                    .shadow(
                        color: .black.opacity(0.15),
                        radius: 4,
                        y: 2
                    )

                placeholderStatus(for: state)
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func placeholderStatus(
        for state: WindowPreviewThumbnailState
    ) -> some View {
        switch state {
        case .permissionRequired:
            Label(
                "Thumbnail not enabled",
                systemImage: "eye.slash"
            )
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.secondary)
        case .loading:
            HStack(spacing: 5) {
                ProgressView()
                    .controlSize(.mini)
                Text("Loading thumbnail…")
            }
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.secondary)
        case .unavailable:
            Label(
                "Thumbnail unavailable",
                systemImage: "eye.slash"
            )
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.secondary)
        case .available:
            EmptyView()
        }
    }

    private func thumbnailState(
        for window: DockApplicationWindow
    ) -> WindowPreviewThumbnailState {
        WindowPreviewThumbnailState.resolve(
            hasThumbnail: thumbnails[window.id] != nil,
            isCaptureEnabled: isThumbnailCaptureEnabled,
            isLoading: thumbnailLoadingIDs.contains(window.id),
            isUnavailable:
                thumbnailUnavailableIDs.contains(window.id),
            hasCaptureWindow: window.captureWindowID != nil
        )
    }

    private func windowStatusLabel(
        _ window: DockApplicationWindow
    ) -> String {
        if window.isMinimized {
            return "Minimized"
        }
        if window.isApplicationHidden {
            return "Hidden"
        }
        return "Not visible"
    }

    private func windowStatusIcon(
        _ window: DockApplicationWindow
    ) -> String {
        if window.isMinimized {
            return "minus"
        }
        if window.isApplicationHidden {
            return "eye.slash.fill"
        }
        return "rectangle.on.rectangle"
    }

    private func windowHelp(
        _ window: DockApplicationWindow
    ) -> String {
        if window.canFocusExactly {
            return "Bring “\(window.title)” to front"
        }
        return "Activate \(window.applicationName). macOS did not expose this window for exact switching."
    }

    private func windowAccessibilityHint(
        _ window: DockApplicationWindow
    ) -> String {
        if isKeyboardSelected(window) {
            return window.canFocusExactly
                ? "Press Return to bring this window to front."
                : "Press Return to activate the application."
        }
        return window.canFocusExactly
            ? "Brings this window to front."
            : "Activates the application; exact window switching is unavailable."
    }

    private func windowAccessibilityValue(
        _ window: DockApplicationWindow
    ) -> String {
        var values: [String] = []
        if window.isFocused {
            values.append("focused")
        } else if window.isMain {
            values.append("main")
        }
        if isKeyboardSelected(window) {
            values.append("keyboard selected")
        }
        if window.isMinimized {
            values.append("minimized")
        }
        if window.isApplicationHidden {
            values.append("application hidden")
        }
        if window.isOnScreen == false,
           !window.isMinimized,
           !window.isApplicationHidden
        {
            values.append("another Desktop or off-screen")
        }
        switch thumbnailState(for: window) {
        case .available:
            values.append("window thumbnail")
        case .permissionRequired:
            values.append("preview permission not enabled")
        case .loading:
            values.append("window thumbnail loading")
        case .unavailable:
            values.append("window thumbnail unavailable")
        }
        if !window.canFocusExactly {
            values.append("application activation only")
        }
        return values.joined(separator: ", ")
    }

    private func isKeyboardSelected(
        _ window: DockApplicationWindow
    ) -> Bool {
        keyboardSelectedWindowID == window.id
    }

    private func scrollToKeyboardSelection(
        with proxy: ScrollViewProxy
    ) {
        guard let keyboardSelectedWindowID,
              windows.contains(where: {
                  $0.id == keyboardSelectedWindowID
              })
        else {
            return
        }
        if reduceMotion {
            proxy.scrollTo(
                keyboardSelectedWindowID,
                anchor: .center
            )
        } else {
            withAnimation(.easeOut(duration: 0.12)) {
                proxy.scrollTo(
                    keyboardSelectedWindowID,
                    anchor: .center
                )
            }
        }
    }

    @ViewBuilder
    private var panelBackground: some View {
        if reduceTransparency {
            Color(nsColor: .windowBackgroundColor)
        } else {
            Rectangle().fill(.ultraThinMaterial)
        }
    }
}
