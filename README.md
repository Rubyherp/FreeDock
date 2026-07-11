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
    <img src="https://img.shields.io/github/stars/Rubyherp/FreeDock?style=for-the-badge&logo=github&label=Star%20on%20GitHub" alt="GitHub stars">
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
- **Drag & drop** — Drag `.app` files from Finder directly onto a dock
- **Reorder** — Drag icons within a dock to rearrange them
- **Horizontal or vertical** — Choose the orientation that fits your workflow
- **Running app indicators** — See which apps are currently open at a glance
- **Click to launch or switch** — Single-click to open an app or bring it to focus
- **Lock positions** — Prevent accidental dock movement
- **Persistent config** — All docks are saved to `~/.config/freedock.json`
- **Native & lightweight** — Built with SwiftUI and AppKit, minimal resource usage

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

## Configuration

Docks are saved to `~/.config/freedock.json`. The file is human-readable and editable — changes take effect the next time FreeDock launches.

```json
{
  "docks" : [
    {
      "name" : "Dock 1",
      "orientation" : "horizontal",
      "iconSize" : 48,
      "items" : [
        { "appPath" : "/Applications/Safari.app", "label" : "Safari" }
      ]
    }
  ]
}
```

## Contributing

Contributions are welcome! Please read `CONTRIBUTING.md` before opening a PR.

## Security

To report a vulnerability, please follow `SECURITY.md` and avoid public issue disclosure.

## Code of Conduct

Please read `CODE_OF_CONDUCT.md` before participating.

## License

MIT
