import Testing

@testable import FreeDock

@Suite("Preferences permission state")
struct PreferencesPermissionStateTests {
  @Test("Initial rows are checking and ordered consistently")
  func initialCheckingRows() {
    let state = PreferencesPermissionState()

    #expect(
      state.presentations.map(\.permission)
        == [.accessibility, .screenRecording]
    )
    #expect(
      state.presentations.allSatisfy {
        $0.status == .checking
          && $0.statusLabel == "Checking…"
          && $0.actionTitle == "Checking…"
          && !$0.isActionEnabled
      }
    )
  }

  @Test("Not-granted rows explain required and optional access")
  func notGrantedPresentation() {
    let state = PreferencesPermissionState(
      snapshot: PreferencesPermissionSnapshot(
        accessibilityGranted: false,
        screenRecordingGranted: false
      )
    )
    let accessibility = state.presentation(
      for: .accessibility
    )
    let screenRecording = state.presentation(
      for: .screenRecording
    )

    #expect(accessibility.title == "Accessibility")
    #expect(accessibility.statusLabel == "Not Granted")
    #expect(
      accessibility.actionTitle
        == "Enable Accessibility…"
    )
    #expect(accessibility.detail.contains("Required"))
    #expect(accessibility.isActionEnabled)

    #expect(screenRecording.title == "Screen Recording")
    #expect(screenRecording.statusLabel == "Not Granted")
    #expect(
      screenRecording.actionTitle
        == "Enable Screen Recording…"
    )
    #expect(screenRecording.detail.contains("Optional"))
    #expect(
      screenRecording.detail.contains(
        "window switching still works"
      )
    )
    #expect(screenRecording.isActionEnabled)
  }

  @Test("Granted rows expose management actions")
  func grantedPresentation() {
    let state = PreferencesPermissionState(
      snapshot: PreferencesPermissionSnapshot(
        accessibilityGranted: true,
        screenRecordingGranted: true
      )
    )

    #expect(
      state.presentation(for: .accessibility).statusLabel
        == "Granted"
    )
    #expect(
      state.presentation(for: .accessibility).actionTitle
        == "Manage Accessibility…"
    )
    #expect(
      state.presentation(for: .screenRecording).statusLabel
        == "Granted"
    )
    #expect(
      state.presentation(for: .screenRecording).actionTitle
        == "Manage Screen Recording…"
    )
  }

  @Test("Periodic refresh reports only actual status changes")
  func periodicRefreshChanges() {
    var state = PreferencesPermissionState()
    let denied = PreferencesPermissionSnapshot(
      accessibilityGranted: false,
      screenRecordingGranted: false
    )

    #expect(
      state.refresh(with: denied)
        == .changed([.accessibility, .screenRecording])
    )
    let stableState = state
    #expect(state.refresh(with: denied) == .unchanged)
    #expect(state == stableState)

    #expect(
      state.refresh(
        with: PreferencesPermissionSnapshot(
          accessibilityGranted: true,
          screenRecordingGranted: false
        )
      ) == .changed([.accessibility])
    )
    #expect(
      state.refresh(
        with: PreferencesPermissionSnapshot(
          accessibilityGranted: true,
          screenRecordingGranted: true
        )
      ) == .changed([.screenRecording])
    )
  }

  @Test("Refresh observes permission revocation")
  func refreshObservesRevocation() {
    var state = PreferencesPermissionState(
      snapshot: PreferencesPermissionSnapshot(
        accessibilityGranted: true,
        screenRecordingGranted: true
      )
    )

    let result = state.refresh(
      with: PreferencesPermissionSnapshot(
        accessibilityGranted: false,
        screenRecordingGranted: true
      )
    )

    #expect(result == .changed([.accessibility]))
    #expect(
      state.snapshot.accessibility == .notGranted
    )
    #expect(
      state.snapshot.screenRecording == .granted
    )
  }

  @Test("Snapshot boolean initializer keeps permissions independent")
  func booleanSnapshot() {
    let snapshot = PreferencesPermissionSnapshot(
      accessibilityGranted: false,
      screenRecordingGranted: true
    )

    #expect(
      snapshot.status(for: .accessibility)
        == .notGranted
    )
    #expect(
      snapshot.status(for: .screenRecording)
        == .granted
    )
  }
}
