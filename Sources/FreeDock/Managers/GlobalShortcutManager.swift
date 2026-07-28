import Carbon.HIToolbox
import Foundation

final class GlobalShortcutManager: @unchecked Sendable {
    static let standardModifiers = UInt32(controlKey) | UInt32(optionKey)
    static let showHideKeyCode = UInt32(kVK_Space)
    static let profileKeyCodes: [UInt32] = [
        UInt32(kVK_ANSI_1),
        UInt32(kVK_ANSI_2),
        UInt32(kVK_ANSI_3),
        UInt32(kVK_ANSI_4),
        UInt32(kVK_ANSI_5),
        UInt32(kVK_ANSI_6),
        UInt32(kVK_ANSI_7),
        UInt32(kVK_ANSI_8),
        UInt32(kVK_ANSI_9),
    ]

    private static let signature: OSType = 0x46444F43 // "FDOC"
    private var eventHandler: EventHandlerRef?
    private var hotKeyReferences: [EventHotKeyRef] = []
    private var actions: [UInt32: @MainActor () -> Void] = [:]

    @MainActor
    init() {
        installEventHandler()
    }

    @MainActor
    func reset() {
        for reference in hotKeyReferences {
            UnregisterEventHotKey(reference)
        }
        hotKeyReferences.removeAll()
        actions.removeAll()
    }

    @discardableResult
    @MainActor
    func register(
        id: UInt32,
        keyCode: UInt32,
        modifiers: UInt32 = GlobalShortcutManager.standardModifiers,
        action: @escaping @MainActor () -> Void
    ) -> Bool {
        guard eventHandler != nil else { return false }

        var reference: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &reference
        )

        guard status == noErr, let reference else { return false }
        hotKeyReferences.append(reference)
        actions[id] = action
        return true
    }

    @MainActor
    private func installEventHandler() {
        guard eventHandler == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            Self.handleEvent,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
    }

    @MainActor
    private func performAction(for id: UInt32) {
        actions[id]?()
    }

    private static let handleEvent: EventHandlerUPP = { _, event, userData in
        guard let event, let userData else { return OSStatus(eventNotHandledErr) }

        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr, hotKeyID.signature == signature else {
            return OSStatus(eventNotHandledErr)
        }

        let manager = Unmanaged<GlobalShortcutManager>
            .fromOpaque(userData)
            .takeUnretainedValue()
        Task { @MainActor in
            manager.performAction(for: hotKeyID.id)
        }
        return noErr
    }
}
