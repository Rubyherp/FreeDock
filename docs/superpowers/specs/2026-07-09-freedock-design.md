# FreeDock — Open-Source macOS Multi-Dock

**Date:** 2026-07-09
**Status:** Approved Design

---

## Overview

FreeDock is a lightweight, open-source macOS menu-bar app that lets users create multiple floating docks on their screen. Each dock shows a row/column of app icons, can launch/switch apps, and can be freely positioned. Inspired by ExtraDock, but free and open-source.

---

## Architecture

**Pattern:** macOS menu-bar agent (`LSUIElement = true`). No dock icon, no app switcher entry. The app lives in the menu bar and spawns borderless floating window panels.

```
FreeDock/
├── Sources/
│   ├── FreeDockApp.swift         // @main, sets up AppDelegate
│   ├── AppDelegate.swift         // NSApplicationDelegate, menu bar, lifecycle
│   ├── Models/
│   │   ├── AppConfig.swift       // Top-level config: [DockConfig]
│   │   ├── DockConfig.swift      // Per-dock: id, position, orientation, items
│   │   └── DockItem.swift        // App entry: appPath, label (bundleID derived at runtime)
│   ├── Managers/
│   │   ├── DockManager.swift     // Creates/destroys dock windows, holds state
│   │   └── ConfigManager.swift   // JSON read/write to ~/.config/freedock.json
│   ├── Windows/
│   │   └── DockPanel.swift       // NSPanel subclass, floating level, no titlebar
│   └── Views/
│       ├── DockContentView.swift // HStack or VStack of items, orientation-aware
│       ├── DockItemView.swift    // Icon + running dot + label
│       └── DockMenuView.swift    // Right-click NSMenu for removing apps
├── Resources/
│   └── Assets.xcassets
└── Package.swift                 // SwiftPM project (builds via `swift run`)
```

**Data flow:**
```
ConfigManager ↔ ~/.config/freedock.json
      ↕
DockManager (in-memory [DockConfig], publishes changes)
      ↕
DockPanel (NSPanel) → DockContentView (SwiftUI)
```

**Tech stack:** Swift 6, SwiftUI for views, AppKit for window/system integration. SwiftPM build (no Xcode project required, but Xcode-compatible).

---

## Data Model

```swift
// ~/.config/freedock.json
struct AppConfig: Codable {
    var docks: [DockConfig] = []
}

struct DockConfig: Codable, Identifiable {
    var id: UUID
    var name: String
    var position: CGPoint
    var orientation: Orientation
    var iconSize: Double = 48.0
    var items: [DockItem] = []
}

struct DockItem: Codable, Identifiable {
    var id: UUID
    var appPath: String
    var label: String?
}

enum Orientation: String, Codable {
    case horizontal
    case vertical
}
```

- **Config path:** `~/.config/freedock.json` — macOS home-dir convention (not strictly XDG, but simple and git-friendly). The `$XDG_CONFIG_HOME` env var is not consulted.
- **Bundle resolution:** `DockItem.appPath` read at runtime from the `.app` bundle's `Info.plist` for display name and bundle ID. Bundle ID is never stored in the config — it's derived from the `.app` bundle on every load. `DockItem` has no bundleID field.
- **Thread safety:** `DispatchQueue` (serial) with a cancellable/rescheduled `DispatchWorkItem` for 500ms debounce on saves. Not `OperationQueue` — that doesn't support debouncing.

---

## App Lifecycle & Menu Bar

- **App type:** `LSUIElement = true` — no dock icon, no ⌘+Tab entry
- **Menu bar:** `NSStatusBar.system.statusItem` with template icon
- **Menu contents:**
  - "New Dock" → creates empty dock at screen center
  - Separator
  - List of existing docks (checkmark = visible) → toggle visibility
  - Separator
  - "Launch at Login" (toggle)
  - "Quit FreeDock"
- **On launch:** Loads config from disk, restores all saved docks
- **On quit:** Saves all dock positions and config

---

## Dock Windows (DockPanel)

**NSPanel properties:**
- `.styleMask = [.borderless]`
- `.isFloatingPanel = true` — makes panel float above normal windows (NSPanel property)
- `.becomesKeyOnlyIfNeeded = true` — panel doesn't steal focus on click
- `.level = .floating` — above normal windows, below fullscreen
- `.isOpaque = false`, `.backgroundColor = .clear`
- `.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`
  - `canJoinAllSpaces`: docks appear on every Space (correct for multi-monitor)
  - `fullScreenAuxiliary`: docks appear alongside fullscreen apps on the same screen, not on top of them. This is intentional — docks won't overlay fullscreen video but will be visible next to split-screen fullscreen apps.

**Repositioning (not `isMovableByWindowBackground`):**
`isMovableByWindowBackground = true` is NOT used because it conflicts with drag-to-reorder gestures on items. Instead:
- Each dock has a guaranteed **8pt padding** around its content area. This padding serves as the drag handle — wide enough to grab easily regardless of how many items are in the dock.
- When the dock is empty, the entire dock area acts as a drag handle.
- On the menu bar, a "Lock Dock Positions" toggle disables all drag handles to prevent accidental moves.

**Off-screen position clamp:**
When restoring a dock's saved `CGPoint`, if the position falls outside the visible screen bounds (e.g., after disconnecting an external monitor), the dock is clamped to the nearest valid position within the main screen's `visibleFrame`. This prevents docks from appearing off-screen.

**DockPanel sizing:** Auto-resizes to fit content. Minimum size to maintain grab-ability when empty.

---

## Dock Content (SwiftUI Views)

**DockContentView:**
- Orientation-aware: `HStack` (horizontal) or `VStack` (vertical)
- Uses SwiftUI `.dropDestination(for: URL.self)` to accept `.app` file URLs from Finder — validate bundle, resolve display name, append item, save config. `URL` is the correct `Transferable` type for file URLs dragged from Finder.
- Accepts `onMove` for drag-to-reorder within the dock
- Empty state: compact semi-transparent bar — the entire area acts as a drag handle for repositioning

**DockItemView:**
- App icon via `NSWorkspace.shared.icon(forFile:)`
- Running indicator dot (subscribes to `NSWorkspace` notifications)
- Optional label below/next to icon
- Click → launch app or bring to front (`NSWorkspace.shared.open`)
- Right-click → "Remove from Dock"
- Drag off dock → remove item

**Running app detection:**
- `NSWorkspace.shared.runningApplications` changes observed via
  `NSWorkspace.didLaunchApplicationNotification` and
  `NSWorkspace.didTerminateApplicationNotification`

---

## Drag & Drop

| Action | Implementation |
|---|---|
| Add app | Drag `.app` from Finder onto dock (`.dropDestination(for: URL.self)`) → validate bundle → resolve display name → append item |
| Remove app | Right-click "Remove" or drag icon off the dock |
| Reorder | Drag within dock (`onMove` / `DragGesture`) |
| Reposition dock | Drag handle region (padding strip or empty-state area), not the whole window background |
| Config save | Triggered on every change, debounced 500ms, serial `DispatchQueue` with cancellable `DispatchWorkItem` |

**Stale app handling (v1):**
If an app at `appPath` is uninstalled or moved, the dock item still shows but gets a generic file icon and clicking it silently fails (`NSWorkspace.shared.open` returns false). v1 does not auto-remove stale entries — the user can manually remove them via right-click. A future version may show a "missing" visual indicator.

---

## Configuration Persistence

- **File:** `~/.config/freedock.json`
- **Format:** JSON with `.prettyPrinted` — human-readable
- **Backup:** `~/.config/freedock.json.bak` written before each save
- **Save triggers:** add/remove/reorder item, move dock, change orientation, create/delete dock
- **Thread safety:** Serial `DispatchQueue` with cancellable `DispatchWorkItem` (500ms debounce)

---

## Deviations from ExtraDock (v1 scope)

| Feature | ExtraDock | FreeDock v1 |
|---|---|---|
| Multiple docks | ✅ | ✅ |
| Drag to position | ✅ | ✅ |
| Add/remove apps via drag | ✅ | ✅ |
| Right-click remove | ✅ | ✅ |
| Horizontal/Vertical | ✅ | ✅ |
| Running indicators | ✅ | ✅ |
| Widgets (clock, shelf, etc.) | ✅ | ❌ (future) |
| Per-monitor auto-hide | ✅ | ❌ (future) |
| Live Dock mirror | ✅ | ❌ (future) |
| Custom icons | ✅ | ❌ (future) |
| Space Awareness | ✅ | ❌ (future) |
| Custom effects/colors | ✅ | ❌ (future) |

---

## Build & Distribution

**SwiftPM setup:** The project uses `Package.swift` (SwiftPM) — no `.xcodeproj` required, but Xcode-compatible for those who prefer the IDE.

**LSUIElement (Info.plist):** SwiftPM targets don't generate an Info.plist by default. To make the app a menu-bar agent (no dock icon), the build setup must include a custom `Info.plist` with `LSUIElement = true`, wired into `Package.swift` via `info.plist` parameter on the `.executable` target.

**Build & run (important):** `swift run` launches the executable directly, bypassing the `.app` bundle — so Info.plist (and `LSUIElement`) won't be respected, and the app may incorrectly appear in the Dock. The correct build approach is:
1. `swift build` to compile
2. Wrap the resulting binary in an `.app` bundle with the Info.plist
3. Open the `.app` bundle (or use a build script that automates this)

A build helper script (`scripts/build.sh`) that automates the `.app` wrapping will be included in the repo and documented in the README.

Alternatively, contributors with Xcode can use `xcodebuild` which handles bundling natively.

**Sandboxing:** FreeDock is NOT sandboxed for v1. It needs access to:
- The filesystem (reading `.app` bundles, accessing `~/.config/`)
- `NSWorkspace` (launching apps, enumerating running apps)
- Arbitrary file URLs from Finder drag-and-drop

This makes Mac App Store distribution impossible without significant rework — v1 targets direct distribution (GitHub releases, `brew tap`, or manual build).

## Open Source Considerations

- **License:** MIT (standard permissive)
- **Config format:** simple JSON, documented in README
- **Dependencies:** zero — pure Swift + Apple frameworks only (AppKit, SwiftUI, Combine)
- **Distribution:** build from source via `swift run`, or pre-built binary attached to GitHub releases

---

## Future (post-v1)

- Per-monitor dock assignment
- Live Dock widget (mirrors native macOS Dock)
- Widget system (clock, folder stack, shelf)
- Custom icons and colors
- System tray / menu bar presets
- Preferences window (icon size, opacity, behavior)
