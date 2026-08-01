import AppKit
import SwiftUI

struct OnboardingView: View {
    let requestAccessibility: @MainActor () -> Bool
    let requestScreenRecording: @MainActor () -> Bool
    let onFinish: @MainActor (Bool) -> Void

    @State private var progress = OnboardingProgress()
    @State private var accessibilityGranted = false
    @State private var screenRecordingGranted = false

    var body: some View {
        ZStack {
            atmosphericBackground

            VStack(spacing: 0) {
                header

                stepContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 42)
                    .padding(.bottom, 24)

                footer
            }
        }
        .frame(minWidth: 680, minHeight: 520)
        .animation(.easeInOut(duration: 0.24), value: progress.step)
    }

    private var accent: Color {
        switch progress.step {
        case .welcome: return Color(red: 0.22, green: 0.52, blue: 1)
        case .organize: return Color(red: 0.55, green: 0.34, blue: 0.96)
        case .integrate: return Color(red: 0.10, green: 0.68, blue: 0.58)
        }
    }

    private var atmosphericBackground: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)

            LinearGradient(
                colors: [
                    accent.opacity(0.16),
                    Color.clear,
                    Color(nsColor: .windowBackgroundColor),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(accent.opacity(0.14))
                .frame(width: 330, height: 330)
                .blur(radius: 80)
                .offset(x: 260, y: -210)

            Circle()
                .fill(Color.purple.opacity(0.08))
                .frame(width: 280, height: 280)
                .blur(radius: 90)
                .offset(x: -290, y: 230)
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        VStack(spacing: 20) {
            HStack(spacing: 9) {
                Image(systemName: "square.grid.3x3.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(accent)
                Text("FreeDock")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("GETTING STARTED")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                ForEach(OnboardingStep.allCases, id: \.rawValue) { step in
                    let isCurrent = step == progress.step
                    let isComplete = step.rawValue < progress.step.rawValue
                    HStack(spacing: 6) {
                        ZStack {
                            Circle()
                                .fill(
                                    isCurrent || isComplete
                                        ? accent
                                        : Color.secondary.opacity(0.16)
                                )
                                .frame(width: 22, height: 22)
                            if isComplete {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                            } else {
                                Text("\(step.rawValue + 1)")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(
                                        isCurrent ? .white : .secondary
                                    )
                            }
                        }
                        Text(step.label)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(
                                isCurrent ? Color.primary : Color.secondary
                            )
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(isCurrent ? .isSelected : [])

                    if step != OnboardingStep.allCases.last {
                        Capsule()
                            .fill(
                                isComplete
                                    ? accent.opacity(0.72)
                                    : Color.secondary.opacity(0.14)
                            )
                            .frame(maxWidth: 52, maxHeight: 2)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.6)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 22)
        .padding(.bottom, 20)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch progress.step {
        case .welcome:
            welcomeStep.transition(stepTransition)
        case .organize:
            organizeStep.transition(stepTransition)
        case .integrate:
            integrateStep.transition(stepTransition)
        }
    }

    private var stepTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .move(edge: .trailing)),
            removal: .opacity.combined(with: .move(edge: .leading))
        )
    }

    private var welcomeStep: some View {
        VStack(spacing: 18) {
            VStack(spacing: 7) {
                Text("Your desktop, organized your way.")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                Text("A free, native macOS dock built around how you work.")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }

            dockPreview
                .padding(.vertical, 7)

            HStack(spacing: 20) {
                compactBenefit(symbol: "rectangle.3.group", text: "Multiple docks")
                compactBenefit(symbol: "display.2", text: "Every display")
                compactBenefit(symbol: "lock.open.fill", text: "Free & open source")
            }

            Text("Your first dock is already waiting. Move it, resize it, or snap it to any screen edge.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 500)
        }
    }

    private var dockPreview: some View {
        HStack(spacing: 13) {
            previewIcon("terminal.fill", colors: [.black, .gray])
            previewIcon("safari.fill", colors: [.blue, .cyan])
            previewIcon("message.fill", colors: [.green, .mint])
            previewIcon("folder.fill", colors: [.cyan, .blue])
            Divider()
                .frame(height: 38)
                .overlay(Color.white.opacity(0.2))
            previewIcon("trash.fill", colors: [.gray, .black])
        }
        .padding(.horizontal, 17)
        .padding(.vertical, 13)
        .background(.ultraThinMaterial, in: RoundedRectangle(
            cornerRadius: 21,
            style: .continuous
        ))
        .overlay {
            RoundedRectangle(cornerRadius: 21, style: .continuous)
                .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.8)
        }
        .shadow(color: .black.opacity(0.18), radius: 20, y: 12)
        .shadow(color: accent.opacity(0.18), radius: 28)
        .accessibilityLabel("Example FreeDock with applications, a folder, and Trash")
    }

    private func previewIcon(_ symbol: String, colors: [Color]) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 23, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 48, height: 48)
            .background(
                LinearGradient(
                    colors: colors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.24), lineWidth: 0.7)
            }
            .shadow(color: .black.opacity(0.22), radius: 5, y: 3)
    }

    private func compactBenefit(symbol: String, text: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
    }

    private var organizeStep: some View {
        VStack(spacing: 21) {
            stepTitle(
                "Make it unmistakably yours.",
                subtitle: "Everything important is one gesture or right-click away."
            )
            HStack(alignment: .top, spacing: 14) {
                featureCard(
                    number: "01",
                    symbol: "plus.square.on.square",
                    title: "Drop anything",
                    text: "Drag apps, files, and folders straight from Finder."
                )
                featureCard(
                    number: "02",
                    symbol: "arrow.left.arrow.right",
                    title: "Arrange naturally",
                    text: "Reorder icons or move them between project docks."
                )
                featureCard(
                    number: "03",
                    symbol: "paintbrush.fill",
                    title: "Make it personal",
                    text: "Rename items, use custom icons, and save visual themes."
                )
            }

            Label(
                "Drop a pinned icon onto FreeDock’s Trash to remove the pin—the original stays safe.",
                systemImage: "checkmark.shield.fill"
            )
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 15)
            .padding(.vertical, 9)
            .background(accent.opacity(0.09), in: Capsule())
        }
    }

    private var integrateStep: some View {
        VStack(spacing: 18) {
            stepTitle(
                "Powerful when you want it.",
                subtitle: "The core dock needs no special access. These extras are optional."
            )
            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 12) {
                    permissionRow(
                        symbol: "macwindow.on.rectangle",
                        title: "Window switching",
                        text: "Accessibility lets FreeDock discover and focus an app’s windows.",
                        granted: accessibilityGranted,
                        action: {
                            accessibilityGranted = requestAccessibility()
                        }
                    )
                    permissionRow(
                        symbol: "rectangle.inset.filled.and.person.filled",
                        title: "Live window thumbnails",
                        text: "Screen Recording adds previews. Titles still work without it.",
                        granted: screenRecordingGranted,
                        action: {
                            screenRecordingGranted = requestScreenRecording()
                        }
                    )
                }
                .frame(maxWidth: .infinity)

                supportCard
                    .frame(width: 178)
            }
            HStack(spacing: 7) {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(accent)
                Text("Permissions stay under macOS control and can be revoked anytime.")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var supportCard: some View {
        VStack(spacing: 8) {
            if let supportQRCode {
                Image(nsImage: supportQRCode)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: 100, height: 100)
                    .padding(7)
                    .background(.white, in: RoundedRectangle(
                        cornerRadius: 12,
                        style: .continuous
                    ))
                    .accessibilityLabel("Buy Me a Coffee QR code")
            } else {
                Image(systemName: "cup.and.saucer.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(accent)
                    .frame(width: 114, height: 114)
            }

            Text("Support FreeDock")
                .font(.system(size: 13, weight: .semibold))
            Text("Free forever. Tips support continued development.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Link(
                "Buy Me a Coffee",
                destination: Self.supportURL
            )
            .font(.system(size: 11, weight: .semibold))
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(
            cornerRadius: 15,
            style: .continuous
        ))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.7)
        }
        .accessibilityElement(children: .contain)
    }

    private var supportQRCode: NSImage? {
        guard let url = Bundle.main.url(
            forResource: "SupportQR",
            withExtension: "png"
        ) else { return nil }
        return NSImage(contentsOf: url)
    }

    private static let supportURL = URL(
        string: "https://www.buymeacoffee.com/thksalot"
    )!

    private func stepTitle(_ title: String, subtitle: String) -> some View {
        VStack(spacing: 7) {
            Text(title)
                .font(.system(size: 27, weight: .bold, design: .rounded))
            Text(subtitle)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private func featureCard(
        number: String,
        symbol: String,
        title: String,
        text: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Image(systemName: symbol)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(accent)
                Spacer()
                Text(number)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            Text(title).font(.system(size: 15, weight: .semibold))
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(
            cornerRadius: 16,
            style: .continuous
        ))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.7)
        }
        .shadow(color: .black.opacity(0.07), radius: 10, y: 5)
    }

    private func permissionRow(
        symbol: String,
        title: String,
        text: String,
        granted: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 15) {
            Image(systemName: symbol)
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(granted ? Color.green : accent)
                .frame(width: 42, height: 42)
                .background(
                    (granted ? Color.green : accent).opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                )
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(title).font(.headline)
                    if granted {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
                Text(text)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 14)
            Button(granted ? "Enabled" : "Enable", action: action)
                .buttonStyle(.borderedProminent)
                .tint(granted ? Color.gray : accent)
                .disabled(granted)
                .frame(minWidth: 78)
        }
        .padding(15)
        .background(.thinMaterial, in: RoundedRectangle(
            cornerRadius: 15,
            style: .continuous
        ))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.7)
        }
    }

    private var footer: some View {
        HStack(spacing: 11) {
            Button {
                progress.goBack()
            } label: {
                Label("Back", systemImage: "chevron.left")
            }
            .buttonStyle(.borderless)
            .disabled(!progress.canGoBack)

            Spacer()

            if progress.isLastStep {
                Button("Open Preferences") { onFinish(true) }
                    .buttonStyle(.bordered)
                Button("Start Using FreeDock") { onFinish(false) }
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button {
                    progress.advance()
                } label: {
                    Label("Continue", systemImage: "arrow.right")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .controlSize(.large)
        .padding(.horizontal, 26)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.10))
                .frame(height: 0.5)
        }
    }
}

private extension OnboardingStep {
    var label: String {
        switch self {
        case .welcome: return "Welcome"
        case .organize: return "Customize"
        case .integrate: return "Connect"
        }
    }
}
