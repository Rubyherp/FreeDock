import Foundation

enum PreferencesPermissionKind:
  String, CaseIterable, Hashable, Identifiable, Sendable
{
  case accessibility
  case screenRecording

  var id: Self { self }

  var title: String {
    switch self {
    case .accessibility:
      return "Accessibility"
    case .screenRecording:
      return "Screen Recording"
    }
  }
}

enum PreferencesPermissionStatus: Equatable, Sendable {
  case checking
  case notGranted
  case granted
}

struct PreferencesPermissionSnapshot: Equatable, Sendable {
  let accessibility: PreferencesPermissionStatus
  let screenRecording: PreferencesPermissionStatus

  static let checking = PreferencesPermissionSnapshot(
    accessibility: .checking,
    screenRecording: .checking
  )

  init(
    accessibility: PreferencesPermissionStatus,
    screenRecording: PreferencesPermissionStatus
  ) {
    self.accessibility = accessibility
    self.screenRecording = screenRecording
  }

  init(
    accessibilityGranted: Bool,
    screenRecordingGranted: Bool
  ) {
    accessibility =
      accessibilityGranted ? .granted : .notGranted
    screenRecording =
      screenRecordingGranted ? .granted : .notGranted
  }

  func status(
    for permission: PreferencesPermissionKind
  ) -> PreferencesPermissionStatus {
    switch permission {
    case .accessibility:
      return accessibility
    case .screenRecording:
      return screenRecording
    }
  }
}

struct PreferencesPermissionPresentation:
  Equatable, Identifiable, Sendable
{
  let permission: PreferencesPermissionKind
  let status: PreferencesPermissionStatus
  let statusLabel: String
  let detail: String
  let actionTitle: String
  let isActionEnabled: Bool

  var id: PreferencesPermissionKind { permission }
  var title: String { permission.title }

  init(
    permission: PreferencesPermissionKind,
    status: PreferencesPermissionStatus
  ) {
    self.permission = permission
    self.status = status

    switch status {
    case .checking:
      statusLabel = "Checking…"
      actionTitle = "Checking…"
      isActionEnabled = false
    case .notGranted:
      statusLabel = "Not Granted"
      actionTitle = Self.enableActionTitle(for: permission)
      isActionEnabled = true
    case .granted:
      statusLabel = "Granted"
      actionTitle = Self.manageActionTitle(for: permission)
      isActionEnabled = true
    }
    detail = Self.detail(for: permission, status: status)
  }

  private static func enableActionTitle(
    for permission: PreferencesPermissionKind
  ) -> String {
    switch permission {
    case .accessibility:
      return "Enable Accessibility…"
    case .screenRecording:
      return "Enable Screen Recording…"
    }
  }

  private static func manageActionTitle(
    for permission: PreferencesPermissionKind
  ) -> String {
    switch permission {
    case .accessibility:
      return "Manage Accessibility…"
    case .screenRecording:
      return "Manage Screen Recording…"
    }
  }

  private static func detail(
    for permission: PreferencesPermissionKind,
    status: PreferencesPermissionStatus
  ) -> String {
    switch (permission, status) {
    case (.accessibility, .checking):
      return "Checking whether FreeDock can discover and focus app windows."
    case (.accessibility, .notGranted):
      return
        "Required for window switching. FreeDock uses Accessibility only to discover and focus app windows."
    case (.accessibility, .granted):
      return "Window switching is enabled. FreeDock can discover and focus app windows."
    case (.screenRecording, .checking):
      return "Checking whether FreeDock can show live window thumbnails."
    case (.screenRecording, .notGranted):
      return "Optional. Enable it for live thumbnails; window switching still works without it."
    case (.screenRecording, .granted):
      return "Live window thumbnails are enabled."
    }
  }
}

enum PreferencesPermissionRefreshResult: Equatable, Sendable {
  case unchanged
  case changed(Set<PreferencesPermissionKind>)
}

struct PreferencesPermissionState: Equatable, Sendable {
  private(set) var snapshot: PreferencesPermissionSnapshot

  init(
    snapshot: PreferencesPermissionSnapshot = .checking
  ) {
    self.snapshot = snapshot
  }

  var presentations: [PreferencesPermissionPresentation] {
    PreferencesPermissionKind.allCases.map {
      presentation(for: $0)
    }
  }

  func presentation(
    for permission: PreferencesPermissionKind
  ) -> PreferencesPermissionPresentation {
    PreferencesPermissionPresentation(
      permission: permission,
      status: snapshot.status(for: permission)
    )
  }

  @discardableResult
  mutating func refresh(
    with newSnapshot: PreferencesPermissionSnapshot
  ) -> PreferencesPermissionRefreshResult {
    var changedPermissions =
      Set<PreferencesPermissionKind>()
    for permission in PreferencesPermissionKind.allCases
    where snapshot.status(for: permission)
      != newSnapshot.status(for: permission)
    {
      changedPermissions.insert(permission)
    }

    guard !changedPermissions.isEmpty else {
      return .unchanged
    }
    snapshot = newSnapshot
    return .changed(changedPermissions)
  }
}
