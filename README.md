<p align="center">
  <img src="docs/logo.png" width="128" alt="FreeDock">
</p>

<h1 align="center">FreeDock</h1>

<p align="center">
  <strong>Multiple floating docks for macOS.</strong>
  <br>
  Free. Open-source. Native.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-12+-brightgreen" alt="macOS 12+">
  <img src="https://img.shields.io/badge/Swift-6.0-orange" alt="Swift 6.0">
  <img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT License">
  <img src="https://img.shields.io/badge/Platform-Apple_Silicon_%7C_Intel-blue" alt="Apple Silicon | Intel">
</p>

<p align="center">
  <img src="docs/screenshot-hero.png" width="600" alt="FreeDock in action">
</p>

FreeDock lets you create unlimited floating docks on any macOS screen. Pin your most-used apps, organize them by project, and keep them accessible with a single click — all without touching the system Dock.

---

<p align="center">
  <a href="https://github.com/Rubyherp/FreeDock/stargazers">
    <img src="https://img.shields.io/github/stars/Rubyherp/FreeDock?style=for-the-badge&logo=github&label=Star%20on%20GitHub&cacheSeconds=0" alt="GitHub stars">
    
  </a>
  &nbsp;&nbsp;
  <a href="https://www.buymeacoffee.com/thksalot">
    <img src="https://img.shields.io/badge/Buy%20Me%20a%20Coffee-Support%20My%20Education-orange?style=for-the-badge&logo=buy-me-a-coffee" alt="Buy Me a Coffee">
  </a>
</p>

<p align="center">
  <a href="https://www.buymeacoffee.com/thksalot">
    <img src="docs/qr-code.png" width="160" alt="Buy Me a Coffee QR code">
  </a>
  <br>
  <strong>If FreeDock saves you time, consider supporting my education.</strong> ☕
</p>

---

## Features

- **Unlimited docks** — Create as many docks as you need, on any screen
- **Dock profiles** — Switch between separate Work, Focus, or Personal dock setups
- **Per-display placement** — Assign each dock to a monitor and restore its relative position after reconnecting
- **Global shortcuts** — Show or hide the active profile with `⌃⌥Space`, or switch profiles with `⌃⌥1…9`
- **Live per-dock preferences** — Tune opacity, blur, shadows, magnification, spacing, orientation, indicators, and auto-hide
- **macOS Dock import** — Append pinned apps to any FreeDock dock without changing Apple’s Dock
- **Drag & drop** — Drag `.app` files from Finder directly onto a dock
- **Reorder** — Drag icons within a dock to rearrange them
- **Horizontal or vertical** — Choose the orientation that fits your workflow
- **Running app indicators** — See which apps are currently open at a glance
- **Click to launch or switch** — Single-click to open an app or bring it to focus
- **Lock positions** — Prevent accidental dock movement
- **Edge auto-hide** — Dock to the nearest screen edge and let it slide away until needed
- **Persistent config** — All docks are saved to `~/.config/freedock.json`
- **Native & lightweight** — Built with SwiftUI and AppKit, minimal resource usage

## Free and open source, permanently

FreeDock is MIT-licensed and all features are available to everyone. The goal is a thoughtful, native alternative to the system Dock—not a free trial or a feature-gated shell. See the [project roadmap](docs/ROADMAP.md) for the next improvements and ways to contribute.

## Screenshots

<p align="center">
  <img src="docs/screenshot-menu.png" width="400" alt="Menu bar">
  &nbsp;&nbsp;&nbsp;
  <img src="docs/screenshot-config-1.png" width="400" alt="Dock configuration">
</p>

<p align="center">
  <img src="docs/screenshot-config-2.png" width="400" alt="Dock settings">
</p>

<img src="docs/demo.gif" width="800" alt="FreeDock demo">

## Installation

Download the latest `FreeDock.app` from the [Releases](https://github.com/Rubyherp/FreeDock/releases) page (when available), then drag it to your Applications folder.

### Build from source

```bash
git clone https://github.com/Rubyherp/FreeDock.git
cd FreeDock
make run
```

> **Note:** `swift run` launches the binary directly, bypassing the `.app` bundle. The `LSUIElement` setting (menu-bar agent mode) won't be respected this way. Always use `make run`, `./scripts/build.sh`, or open the `.app` bundle.

**Requirements:** macOS 12+, Xcode 15+

## Usage

1. Click the **grid icon** (⫷) in your menu bar
2. Select **New Dock → Horizontal** or **Vertical**
3. Drag `.app` files from Finder into the dock
4. Click any app to launch it or bring it to focus
5. Drag the empty space around the dock to reposition it
6. Right-click an app to remove it or access more options

**Pro tip:** Use **Lock Dock Positions** from the menu bar to prevent accidental moves.

**Customization:** Choose **Preferences…** from the FreeDock menu to switch or manage profiles, create and organize docks, assign docks to displays, import pinned apps from the macOS Dock, adjust behavior and appearance, or copy and reset dock settings. Changes are applied and saved immediately.

**Shortcuts:** Press `⌃⌥Space` to show or hide every dock in the active profile. The first nine profiles are available globally with `⌃⌥1` through `⌃⌥9`.

## Configuration

Docks and profiles are saved to `~/.config/freedock.json`. The file is human-readable and editable — changes take effect the next time FreeDock launches. Legacy top-level dock configurations migrate automatically.

```json
{
  "formatVersion": 2,
  "activeProfileID": "11111111-1111-1111-1111-111111111111",
  "profiles": [
    {
      "id": "11111111-1111-1111-1111-111111111111",
      "name": "Work",
      "docks": [
        {
          "id": "22222222-2222-2222-2222-222222222222",
          "name": "Main",
          "position": [100, 100],
          "displayPlacement": {
            "displayID": "33333333-3333-3333-3333-333333333333",
            "displayName": "Built-in Retina Display",
            "normalizedCenter": [0.5, 0.1],
            "edge": "bottom"
          },
          "orientation": "horizontal",
          "iconSize": 48,
          "magnificationEnabled": true,
          "magnification": 1.3,
          "itemSpacing": 3,
          "appearance": "glass",
          "surfaceOpacity": 1,
          "blurStyle": "regular",
          "shadowStrength": 1,
          "cornerRadius": 18,
          "showRunningIndicators": true,
          "autoHideWhenDocked": true,
          "autoHideDelay": 1,
          "items": []
        }
      ]
    }
  ]
}
```

FreeDock also writes the active profile’s docks to a top-level compatibility field so older builds can still open the current setup.

## Contributing

Contributions are welcome! Please read `CONTRIBUTING.md` before opening a PR.

## Security

To report a vulnerability, please follow `SECURITY.md` and avoid public issue disclosure.

## Code of Conduct

Please read `CODE_OF_CONDUCT.md` before participating.

## License

MIT
