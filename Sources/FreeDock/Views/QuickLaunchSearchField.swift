import AppKit
import SwiftUI

/// A native search field for Quick Launch that keeps text entry and input
/// methods under AppKit while forwarding launcher-specific key commands.
struct QuickLaunchSearchField: NSViewRepresentable {
    enum Command: Equatable, Sendable {
        case moveLeft
        case moveRight
        case moveUp
        case moveDown
        case next
        case previous
        case activate
        case dismiss
    }

    @Binding var text: String
    let focusGeneration: Int
    let placeholder: String
    let accessibilityLabel: String
    let accessibilityHelp: String
    let accessibilityStatus: String
    let onCommand: @MainActor (Command) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> QuickLaunchNativeSearchField {
        let searchField = QuickLaunchNativeSearchField()
        searchField.delegate = context.coordinator
        searchField.sendsSearchStringImmediately = true
        searchField.sendsWholeSearchString = false
        searchField.font = .systemFont(ofSize: 13, weight: .medium)
        searchField.focusRingType = .none
        searchField.isBezeled = false
        searchField.isBordered = false
        searchField.drawsBackground = false
        searchField.usesSingleLineMode = true
        searchField.lineBreakMode = .byTruncatingTail
        searchField.placeholderString = placeholder
        searchField.setAccessibilityLabel(accessibilityLabel)
        searchField.setAccessibilityHelp(combinedAccessibilityHelp)
        return searchField
    }

    func updateNSView(
        _ searchField: QuickLaunchNativeSearchField,
        context: Context
    ) {
        context.coordinator.parent = self

        let isComposingText =
            (searchField.currentEditor() as? NSTextView)?.hasMarkedText()
            ?? false
        if searchField.stringValue != text, !isComposingText {
            searchField.stringValue = text
        }

        if searchField.placeholderString != placeholder {
            searchField.placeholderString = placeholder
        }
        searchField.setAccessibilityLabel(accessibilityLabel)
        searchField.setAccessibilityHelp(combinedAccessibilityHelp)

        if context.coordinator.lastHandledFocusGeneration != focusGeneration {
            context.coordinator.lastHandledFocusGeneration = focusGeneration
            searchField.requestFocus()
        }
    }

    private var combinedAccessibilityHelp: String {
        "\(accessibilityHelp) \(accessibilityStatus)"
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: QuickLaunchSearchField
        var lastHandledFocusGeneration: Int?

        init(_ parent: QuickLaunchSearchField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let searchField = notification.object as? NSSearchField else {
                return
            }
            let newValue = searchField.stringValue
            if parent.text != newValue {
                parent.text = newValue
            }
        }

        func control(
            _: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            // Arrow, Return, Tab, and Escape may be part of an active input
            // method composition. Let AppKit finish or cancel that composition
            // before treating the same key as a launcher command.
            guard !textView.hasMarkedText() else { return false }

            let command: Command?
            switch NSStringFromSelector(commandSelector) {
            case "moveLeft:":
                command = .moveLeft
            case "moveRight:":
                command = .moveRight
            case "moveUp:":
                command = .moveUp
            case "moveDown:":
                command = .moveDown
            case "insertTab:":
                command = .next
            case "insertBacktab:":
                command = .previous
            case "insertNewline:", "insertNewlineIgnoringFieldEditor:":
                command = .activate
            case "cancelOperation:":
                command = .dismiss
            default:
                command = nil
            }

            guard let command else { return false }
            parent.onCommand(command)
            return true
        }
    }
}

final class QuickLaunchNativeSearchField: NSSearchField {
    private var hasPendingFocusRequest = false

    override var mouseDownCanMoveWindow: Bool { false }

    func requestFocus() {
        hasPendingFocusRequest = true
        fulfillFocusRequestIfPossible()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        fulfillFocusRequestIfPossible()
    }

    private func fulfillFocusRequestIfPossible() {
        guard hasPendingFocusRequest, let window else { return }
        guard window.makeFirstResponder(self) else { return }
        hasPendingFocusRequest = false
    }
}
