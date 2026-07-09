#!/bin/bash
# FreeDock build helper
# Usage: ./scripts/build.sh [--release]

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/.build"
APP_NAME="FreeDock"

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
