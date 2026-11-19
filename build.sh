#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
APP_DIR="/Applications/SysPulse.app"

echo "==> Building SysPulse v2.0 (Core Temp Edition)..."
clang -O3 -fobjc-arc \
    -framework Cocoa \
    -framework IOKit \
    "$DIR/src/SysPulse.m" \
    -o "$DIR/SysPulse_bin"

echo "==> Creating macOS Application Bundle..."
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$DIR/SysPulse_bin" "$APP_DIR/Contents/MacOS/SysPulse"
chmod +x "$APP_DIR/Contents/MacOS/SysPulse"
rm -f "$DIR/SysPulse_bin"

if [ -f "$DIR/resources/AppIcon.icns" ]; then
    cp "$DIR/resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

if [ -f "$DIR/resources/Info.plist" ]; then
    cp "$DIR/resources/Info.plist" "$APP_DIR/Contents/Info.plist"
fi

touch "$APP_DIR"
echo "==> Successfully installed to $APP_DIR"
