#!/bin/bash
# FreeDock build helper
# Usage: ./scripts/build.sh [--release]

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/.build"
APP_NAME="FreeDock"
LOGO_SOURCE="/Users/xiangnenghor/Documents/FreeDock-logo.png"

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

# Build an .icns app icon from the provided PNG logo when available.
if [ -f "$LOGO_SOURCE" ]; then
    ICONSET_DIR="$APP_BUNDLE/Contents/Resources/AppIcon.iconset"
    ICON_FILE="$APP_BUNDLE/Contents/Resources/AppIcon.icns"

    rm -rf "$ICONSET_DIR"
    mkdir -p "$ICONSET_DIR"

    sips -z 16 16 "$LOGO_SOURCE" --out "$ICONSET_DIR/icon_16x16.png" > /dev/null
    sips -z 32 32 "$LOGO_SOURCE" --out "$ICONSET_DIR/icon_16x16@2x.png" > /dev/null
    sips -z 32 32 "$LOGO_SOURCE" --out "$ICONSET_DIR/icon_32x32.png" > /dev/null
    sips -z 64 64 "$LOGO_SOURCE" --out "$ICONSET_DIR/icon_32x32@2x.png" > /dev/null
    sips -z 128 128 "$LOGO_SOURCE" --out "$ICONSET_DIR/icon_128x128.png" > /dev/null
    sips -z 256 256 "$LOGO_SOURCE" --out "$ICONSET_DIR/icon_128x128@2x.png" > /dev/null
    sips -z 256 256 "$LOGO_SOURCE" --out "$ICONSET_DIR/icon_256x256.png" > /dev/null
    sips -z 512 512 "$LOGO_SOURCE" --out "$ICONSET_DIR/icon_256x256@2x.png" > /dev/null
    sips -z 512 512 "$LOGO_SOURCE" --out "$ICONSET_DIR/icon_512x512.png" > /dev/null
    sips -z 1024 1024 "$LOGO_SOURCE" --out "$ICONSET_DIR/icon_512x512@2x.png" > /dev/null

    iconutil -c icns "$ICONSET_DIR" -o "$ICON_FILE"
    rm -rf "$ICONSET_DIR"

    echo "==> App icon generated from $LOGO_SOURCE"
else
    echo "==> Warning: logo not found at $LOGO_SOURCE, building without custom app icon"
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
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
EOF

echo "==> App bundle created at $APP_BUNDLE"
echo "    Open with: open \"$APP_BUNDLE\""