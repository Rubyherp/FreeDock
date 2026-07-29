import Foundation
import Testing

@testable import FreeDock

@Suite("Window preview keyboard selection")
struct WindowPreviewKeyboardSelectionTests {
  @Test("Initial selection prefers focused, then main, then first")
  func initialPreference() {
    let first = window()
    let main = window(isMain: true)
    let focused = window(isFocused: true)

    #expect(
      WindowPreviewKeyboardSelection(
        windows: [first, main, focused]
      ).selectedWindowID == focused.id
    )
    #expect(
      WindowPreviewKeyboardSelection(
        windows: [first, main]
      ).selectedWindowID == main.id
    )
    #expect(
      WindowPreviewKeyboardSelection(
        windows: [first]
      ).selectedWindowID == first.id
    )
    #expect(
      WindowPreviewKeyboardSelection().selectedWindowID == nil
    )
  }

  @Test("Refresh and reorder preserve the selected identity")
  func refreshPreservesIdentity() {
    let first = window(isFocused: true)
    let second = window()
    let third = window()
    var selection = WindowPreviewKeyboardSelection(
      windows: [first, second, third]
    )
    selection.selectNext(in: [first, second, third])

    selection.update(windows: [third, second, first])

    #expect(selection.selectedWindowID == second.id)
    #expect(selection.returnTargetID == second.id)
    #expect(selection.showsFocusIndicator)
  }

  @Test("A removed selection recovers using current window preference")
  func removedSelectionRecovers() {
    let first = window(isFocused: true)
    let removed = window()
    let fallbackFirst = window()
    let fallbackMain = window(isMain: true)
    var selection = WindowPreviewKeyboardSelection(
      windows: [first, removed]
    )
    selection.selectNext(in: [first, removed])
    #expect(selection.selectedWindowID == removed.id)

    selection.update(
      windows: [fallbackFirst, fallbackMain, first]
    )

    #expect(selection.selectedWindowID == first.id)
    #expect(selection.showsFocusIndicator)

    selection.update(windows: [fallbackFirst, fallbackMain])
    #expect(selection.selectedWindowID == fallbackMain.id)
    #expect(selection.showsFocusIndicator)
  }

  @Test("Next selection wraps at both ends")
  func nextWraps() {
    let first = window(isFocused: true)
    let second = window()
    let third = window()
    let windows = [first, second, third]
    var selection = WindowPreviewKeyboardSelection(
      windows: windows
    )

    selection.selectNext(in: windows)
    #expect(selection.selectedWindowID == second.id)
    selection.selectNext(in: windows)
    #expect(selection.selectedWindowID == third.id)
    selection.selectNext(in: windows)
    #expect(selection.selectedWindowID == first.id)
  }

  @Test("Previous selection wraps at both ends")
  func previousWraps() {
    let first = window(isFocused: true)
    let second = window()
    let third = window()
    let windows = [first, second, third]
    var selection = WindowPreviewKeyboardSelection(
      windows: windows
    )

    selection.selectPrevious(in: windows)
    #expect(selection.selectedWindowID == third.id)
    selection.selectPrevious(in: windows)
    #expect(selection.selectedWindowID == second.id)
  }

  @Test("Focus indicator stays hidden until keyboard navigation")
  func focusIndicatorVisibility() {
    let first = window(isFocused: true)
    let second = window()
    var selection = WindowPreviewKeyboardSelection(
      windows: [first, second]
    )

    #expect(selection.selectedWindowID == first.id)
    #expect(!selection.showsFocusIndicator)
    selection.update(windows: [second, first])
    #expect(!selection.showsFocusIndicator)

    selection.selectNext(in: [second, first])
    #expect(selection.showsFocusIndicator)
    #expect(selection.returnTargetID == second.id)
  }

  @Test("Empty refresh clears selection and keyboard focus")
  func emptyRefreshClearsSelection() {
    let only = window(isFocused: true)
    var selection = WindowPreviewKeyboardSelection(
      windows: [only]
    )
    selection.selectNext(in: [only])
    #expect(selection.showsFocusIndicator)

    selection.update(windows: [])

    #expect(selection.selectedWindowID == nil)
    #expect(selection.returnTargetID == nil)
    #expect(!selection.showsFocusIndicator)
  }

  private func window(
    id: UUID = UUID(),
    isMain: Bool = false,
    isFocused: Bool = false
  ) -> DockApplicationWindow {
    DockApplicationWindow(
      id: id,
      applicationInstanceID: UUID(),
      applicationName: "Example",
      title: "Window",
      captureWindowID: nil,
      isMinimized: false,
      isApplicationHidden: false,
      isOnScreen: true,
      canFocusExactly: true,
      isMain: isMain,
      isFocused: isFocused
    )
  }
}
