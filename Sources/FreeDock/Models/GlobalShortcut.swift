import Carbon.HIToolbox
import Foundation

enum GlobalShortcutAction: String, Codable, CaseIterable, Sendable {
    case showHideDocks
    case quickLaunch

    var title: String {
        switch self {
        case .showHideDocks:
            return "Show or hide docks"
        case .quickLaunch:
            return "Quick Launch"
        }
    }
}

struct GlobalShortcut: Codable, Equatable, Hashable, Sendable {
    static let supportedModifierMask =
        UInt32(cmdKey) | UInt32(optionKey) | UInt32(controlKey) | UInt32(shiftKey)

    static let defaultShowHide = GlobalShortcut(
        keyCode: UInt32(kVK_Space),
        modifiers: UInt32(controlKey) | UInt32(optionKey)
    )
    static let defaultQuickLaunch = GlobalShortcut(
        keyCode: UInt32(kVK_Space),
        modifiers: UInt32(cmdKey) | UInt32(shiftKey)
    )

    var keyCode: UInt32
    var modifiers: UInt32

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers & Self.supportedModifierMask
    }

    var isValid: Bool {
        modifiers != 0 && Self.keyName(for: keyCode) != nil
    }

    var displayName: String {
        var result = ""
        if modifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        result += Self.keyName(for: keyCode) ?? "Key \(keyCode)"
        return result
    }

    static func keyName(for keyCode: UInt32) -> String? {
        keyNames[keyCode]
    }

    private static let keyNames: [UInt32: String] = [
        UInt32(kVK_Space): "Space",
        UInt32(kVK_Return): "Return",
        UInt32(kVK_Tab): "Tab",
        UInt32(kVK_Delete): "Delete",
        UInt32(kVK_ForwardDelete): "Forward Delete",
        UInt32(kVK_Escape): "Escape",
        UInt32(kVK_LeftArrow): "←",
        UInt32(kVK_RightArrow): "→",
        UInt32(kVK_UpArrow): "↑",
        UInt32(kVK_DownArrow): "↓",
        UInt32(kVK_Home): "Home",
        UInt32(kVK_End): "End",
        UInt32(kVK_PageUp): "Page Up",
        UInt32(kVK_PageDown): "Page Down",
        UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2",
        UInt32(kVK_F3): "F3", UInt32(kVK_F4): "F4",
        UInt32(kVK_F5): "F5", UInt32(kVK_F6): "F6",
        UInt32(kVK_F7): "F7", UInt32(kVK_F8): "F8",
        UInt32(kVK_F9): "F9", UInt32(kVK_F10): "F10",
        UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12",
        UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B",
        UInt32(kVK_ANSI_C): "C", UInt32(kVK_ANSI_D): "D",
        UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F",
        UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H",
        UInt32(kVK_ANSI_I): "I", UInt32(kVK_ANSI_J): "J",
        UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
        UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N",
        UInt32(kVK_ANSI_O): "O", UInt32(kVK_ANSI_P): "P",
        UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R",
        UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T",
        UInt32(kVK_ANSI_U): "U", UInt32(kVK_ANSI_V): "V",
        UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
        UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z",
        UInt32(kVK_ANSI_0): "0", UInt32(kVK_ANSI_1): "1",
        UInt32(kVK_ANSI_2): "2", UInt32(kVK_ANSI_3): "3",
        UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5",
        UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7",
        UInt32(kVK_ANSI_8): "8", UInt32(kVK_ANSI_9): "9",
        UInt32(kVK_ANSI_Minus): "-", UInt32(kVK_ANSI_Equal): "=",
        UInt32(kVK_ANSI_LeftBracket): "[",
        UInt32(kVK_ANSI_RightBracket): "]",
        UInt32(kVK_ANSI_Backslash): "\\",
        UInt32(kVK_ANSI_Semicolon): ";",
        UInt32(kVK_ANSI_Quote): "'",
        UInt32(kVK_ANSI_Comma): ",", UInt32(kVK_ANSI_Period): ".",
        UInt32(kVK_ANSI_Slash): "/", UInt32(kVK_ANSI_Grave): "`",
    ]
}

struct GlobalShortcutSettings: Codable, Equatable, Sendable {
    var showHideDocks: GlobalShortcut
    var quickLaunch: GlobalShortcut

    init(
        showHideDocks: GlobalShortcut = .defaultShowHide,
        quickLaunch: GlobalShortcut = .defaultQuickLaunch
    ) {
        self.showHideDocks = showHideDocks
        self.quickLaunch = quickLaunch
    }

    func shortcut(for action: GlobalShortcutAction) -> GlobalShortcut {
        switch action {
        case .showHideDocks: return showHideDocks
        case .quickLaunch: return quickLaunch
        }
    }

    mutating func set(_ shortcut: GlobalShortcut, for action: GlobalShortcutAction) {
        switch action {
        case .showHideDocks: showHideDocks = shortcut
        case .quickLaunch: quickLaunch = shortcut
        }
    }

    func validationError(
        profileShortcuts: [GlobalShortcut] = GlobalShortcutSettings.defaultProfileShortcuts
    ) -> String? {
        guard showHideDocks.isValid, quickLaunch.isValid else {
            return "Shortcuts need a supported key and at least one modifier."
        }
        guard showHideDocks != quickLaunch else {
            return "Show/Hide and Quick Launch cannot use the same shortcut."
        }
        if profileShortcuts.contains(showHideDocks)
            || profileShortcuts.contains(quickLaunch)
        {
            return "That shortcut is reserved for profile switching."
        }
        return nil
    }

    static let defaultProfileShortcuts: [GlobalShortcut] =
        GlobalShortcutManager.profileKeyCodes.map {
            GlobalShortcut(
                keyCode: $0,
                modifiers: GlobalShortcutManager.standardModifiers
            )
        }
}
