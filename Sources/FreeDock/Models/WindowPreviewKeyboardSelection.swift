import Foundation

struct WindowPreviewKeyboardSelection: Equatable, Sendable {
  private(set) var selectedWindowID: DockApplicationWindow.ID?
  private(set) var showsFocusIndicator = false

  init(windows: [DockApplicationWindow] = []) {
    selectedWindowID = Self.preferredWindowID(in: windows)
  }

  var returnTargetID: DockApplicationWindow.ID? {
    selectedWindowID
  }

  mutating func update(windows: [DockApplicationWindow]) {
    guard !windows.isEmpty else {
      selectedWindowID = nil
      showsFocusIndicator = false
      return
    }
    if let selectedWindowID,
      windows.contains(where: { $0.id == selectedWindowID })
    {
      return
    }
    selectedWindowID = Self.preferredWindowID(in: windows)
  }

  mutating func selectNext(in windows: [DockApplicationWindow]) {
    move(by: 1, in: windows)
  }

  mutating func selectPrevious(
    in windows: [DockApplicationWindow]
  ) {
    move(by: -1, in: windows)
  }

  private mutating func move(
    by offset: Int,
    in windows: [DockApplicationWindow]
  ) {
    guard !windows.isEmpty else {
      selectedWindowID = nil
      showsFocusIndicator = false
      return
    }

    if let selectedWindowID,
      let index = windows.firstIndex(
        where: { $0.id == selectedWindowID }
      )
    {
      let count = windows.count
      let destination = (index + offset + count) % count
      self.selectedWindowID = windows[destination].id
    } else {
      selectedWindowID = Self.preferredWindowID(in: windows)
    }
    showsFocusIndicator = true
  }

  private static func preferredWindowID(
    in windows: [DockApplicationWindow]
  ) -> DockApplicationWindow.ID? {
    windows.first(where: \.isFocused)?.id
      ?? windows.first(where: \.isMain)?.id
      ?? windows.first?.id
  }
}
