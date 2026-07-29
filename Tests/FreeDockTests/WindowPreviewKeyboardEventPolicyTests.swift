import AppKit
import Carbon.HIToolbox
import Testing

@testable import FreeDock

@Suite("Window preview keyboard event policy")
struct WindowPreviewKeyboardEventPolicyTests {
    @Test("Arrow and Tab keys navigate in both directions")
    func navigationKeys() {
        #expect(action(kVK_LeftArrow) == .previous)
        #expect(action(kVK_UpArrow) == .previous)
        #expect(action(kVK_RightArrow) == .next)
        #expect(action(kVK_DownArrow) == .next)
        #expect(action(kVK_Tab) == .next)
        #expect(
            action(kVK_Tab, modifiers: [.shift])
                == .previous
        )
    }

    @Test("Return, keypad Enter, and Space activate")
    func activationKeys() {
        #expect(action(kVK_Return) == .activate)
        #expect(action(kVK_ANSI_KeypadEnter) == .activate)
        #expect(action(kVK_Space) == .activate)
    }

    @Test("Escape closes even when a modifier is held")
    func escapeCloses() {
        #expect(action(kVK_Escape) == .close)
        #expect(
            action(kVK_Escape, modifiers: [.command])
                == .close
        )
    }

    @Test("Command, Control, and Option shortcuts pass through")
    func systemShortcutsPassThrough() {
        for modifiers: NSEvent.ModifierFlags in [
            [.command],
            [.control],
            [.option],
            [.control, .option],
        ] {
            #expect(
                action(kVK_RightArrow, modifiers: modifiers)
                    == nil
            )
            #expect(
                action(kVK_Return, modifiers: modifiers)
                    == nil
            )
        }
    }

    @Test("Unrelated keys pass through")
    func unrelatedKeysPassThrough() {
        #expect(action(kVK_ANSI_A) == nil)
    }

    private func action(
        _ keyCode: Int,
        modifiers: NSEvent.ModifierFlags = []
    ) -> WindowPreviewKeyboardAction? {
        WindowPreviewKeyboardEventPolicy.action(
            keyCode: UInt16(keyCode),
            modifierFlags: modifiers
        )
    }
}
