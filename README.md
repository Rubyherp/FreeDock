# FreeDock

Multiple floating docks for macOS. Free and open-source.

## Features

- Create unlimited floating docks on any screen
- Drag `.app` files from Finder onto a dock to add them
- Right-click to remove apps
- Drag icons within a dock to reorder
- Drag the dock's padding area to reposition it
- Horizontal or vertical orientation
- Running app indicator dots
- Click to launch or switch to an app
- Lock Dock Positions to prevent accidental moves
- Config saved to `~/.config/freedock.json` (human-editable)

## Requirements

- macOS 12+
- Xcode 15+ (for development)

## Build & Run

```bash
git clone https://github.com/YOUR_USER/FreeDock.git
cd FreeDock
make bundle  # builds and creates build/FreeDock.app
make run     # bundles and opens the .app
```

> **Note:** `swift run` launches the binary directly, bypassing the `.app` bundle. The `LSUIElement` setting (menu-bar agent mode) won't be respected this way. Always use `make run`, `./scripts/build.sh`, or open the `.app` bundle.

## Usage

Click the grid icon (⫷) in your menu bar. Select **New Dock → Horizontal** or **Vertical**. Drag apps from Finder into the dock. Right‑click an app to remove it. Drag empty space around the dock to move it.

## Config

All docks are saved to `~/.config/freedock.json`. You can edit this file directly — changes take effect the next time FreeDock launches.

## License

MIT
