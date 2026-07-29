import Testing

@testable import FreeDock

@MainActor
@Test("Permission polling stays passive and explicit actions are routed")
func permissionPollingAndActions() {
    let profile = DockProfile(name: "Default", docks: [])
    var snapshot = PreferencesPermissionSnapshot(
        accessibilityGranted: false,
        screenRecordingGranted: true
    )
    var requestedPermissions: [PreferencesPermissionKind] = []
    var openedSettings: [PreferencesPermissionKind] = []
    let store = DockPreferencesStore(
        profiles: [profile],
        activeProfileID: profile.id,
        onChange: { _, _ in },
        onManagementAction: { _ in },
        permissionSnapshot: { snapshot },
        onPermissionAction: {
            requestedPermissions.append($0)
        },
        onOpenPermissionSettings: {
            openedSettings.append($0)
        }
    )

    #expect(store.permissionState.snapshot == .checking)

    store.refreshPermissions()

    #expect(
        store.permissionState.snapshot
            == PreferencesPermissionSnapshot(
                accessibilityGranted: false,
                screenRecordingGranted: true
            )
    )
    #expect(requestedPermissions.isEmpty)
    #expect(openedSettings.isEmpty)

    snapshot = PreferencesPermissionSnapshot(
        accessibilityGranted: true,
        screenRecordingGranted: true
    )
    store.refreshPermissions()

    #expect(store.permissionState.snapshot.accessibility == .granted)
    #expect(requestedPermissions.isEmpty)

    store.performPermissionAction(.accessibility)
    store.openPermissionSettings(.screenRecording)

    #expect(requestedPermissions == [.accessibility])
    #expect(openedSettings == [.screenRecording])
}
