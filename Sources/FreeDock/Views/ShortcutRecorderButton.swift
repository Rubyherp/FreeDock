import AppKit
import Carbon.HIToolbox
import SwiftUI

struct ShortcutRecorderButton: NSViewRepresentable {
    let shortcut: GlobalShortcut
    let onChange: (GlobalShortcut) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onChange: onChange)
    }

    func makeNSView(context: Context) -> ShortcutRecorderNSButton {
        let button = ShortcutRecorderNSButton()
        button.onChange = context.coordinator.onChange
        button.shortcut = shortcut
        return button
    }

    func updateNSView(
        _ button: ShortcutRecorderNSButton,
        context: Context
    ) {
        context.coordinator.onChange = onChange
        button.onChange = context.coordinator.onChange
        button.shortcut = shortcut
    }

    final class Coordinator {
        var onChange: (GlobalShortcut) -> Void

        init(onChange: @escaping (GlobalShortcut) -> Void) {
            self.onChange = onChange
        }
    }
}

final class ShortcutRecorderNSButton: NSButton {
    var onChange: ((GlobalShortcut) -> Void)?
    var shortcut: GlobalShortcut = .defaultShowHide {
        didSet { updateTitle() }
    }
    private var isRecording = false
    private var keyMonitor: Any?

    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(beginRecording)
        setAccessibilityRole(.button)
        updateTitle()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    @objc private func beginRecording() {
        isRecording = true
        title = "Type Shortcut…"
        setAccessibilityValue("Recording")
        window?.makeFirstResponder(self)
        installKeyMonitor()
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        capture(event)
    }

    private func capture(_ event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            finishRecording()
            return
        }

        let candidate = GlobalShortcut(
            keyCode: UInt32(event.keyCode),
            modifiers: Self.carbonModifiers(from: event.modifierFlags)
        )
        guard candidate.isValid else {
            NSSound.beep()
            return
        }
        onChange?(candidate)
        finishRecording()
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result { finishRecording() }
        return result
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { finishRecording() }
    }

    private func finishRecording() {
        isRecording = false
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        updateTitle()
    }

    private func installKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(
            matching: .keyDown
        ) { [weak self] event in
            guard let self, self.isRecording else { return event }
            self.capture(event)
            return nil
        }
    }

    private func updateTitle() {
        guard !isRecording else { return }
        title = shortcut.displayName
        setAccessibilityLabel("Record keyboard shortcut")
        setAccessibilityValue(shortcut.displayName)
    }

    private static func carbonModifiers(
        from flags: NSEvent.ModifierFlags
    ) -> UInt32 {
        let flags = flags.intersection(.deviceIndependentFlagsMask)
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }
}
