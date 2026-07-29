#!/bin/bash
# FreeDock build helper
# Usage: ./scripts/build.sh [--release]

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/.build"
APP_NAME="FreeDock"
ICON_SOURCE="$PROJECT_DIR/Resources/AppIcon.icns"

echo "==> Building FreeDock..."
cd "$PROJECT_DIR"

if [ "${1:-}" = "--release" ]; then
    swift build -c release
    BINARY="$BUILD_DIR/release/$APP_NAME"
else
    swift build
    BINARY="$BUILD_DIR/debug/$APP_NAME"
fi

APP_BUNDLE="$PROJECT_DIR/build/$APP_NAME.app"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BINARY" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Copy the app icon from repository assets when available.
if [ -f "$ICON_SOURCE" ]; then
    cp "$ICON_SOURCE" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
    echo "==> App icon copied from $ICON_SOURCE"
else
    echo "==> Warning: icon not found at $ICON_SOURCE, building without custom app icon"
fi

# Generate Info.plist for the bundle
cat > "$APP_BUNDLE/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.freedock.app</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>NSScreenCaptureUsageDescription</key>
    <string>FreeDock uses Screen Recording only to create temporary window previews while the dock switcher is open.</string>
    <key>UTExportedTypeDeclarations</key>
    <array>
        <dict>
            <key>UTTypeConformsTo</key>
            <array>
                <string>public.data</string>
            </array>
            <key>UTTypeDescription</key>
            <string>FreeDock dock item drag</string>
            <key>UTTypeIdentifier</key>
            <string>com.freedock.dock-item</string>
        </dict>
    </array>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
EOF

# SwiftPM ad-hoc signs the standalone executable. Copying it into a bundle with
# resources changes its signing context, so sign the completed app bundle before
# Launch Services opens it.
codesign --force --sign - "$APP_BUNDLE"

echo "==> App bundle created at $APP_BUNDLE"
echo "    Open with: open \"$APP_BUNDLE\""
