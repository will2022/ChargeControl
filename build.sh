#!/bin/bash
set -e

echo "Building ChargeControl..."

BUILD_DIR="build"
APP_NAME="ChargeControl.app"
APP_DIR="$BUILD_DIR/$APP_NAME"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
DAEMONS_DIR="$CONTENTS_DIR/Library/LaunchDaemons"

rm -rf "$BUILD_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"
mkdir -p "$DAEMONS_DIR"

# Build Daemon
echo "Compiling Daemon..."
swiftc -o "$MACOS_DIR/ChargeControlDaemon" \
    -import-objc-header Daemon/SMCParamStruct.h \
    Daemon/*.swift Shared/*.swift \
    -lsqlite3 \
    -framework Foundation -framework IOKit

# Build CLI
echo "Compiling CLI..."
swiftc -o "$MACOS_DIR/cc" \
    CLI/*.swift Shared/*.swift \
    -framework Foundation

# Build App
echo "Compiling App..."
swiftc -o "$MACOS_DIR/ChargeControl" \
    App/AppDelegate.swift App/BatteryState.swift App/SettingsView.swift App/Components.swift App/AppIntents.swift Shared/ChargeControlCommProtocol.swift \
    -framework AppKit -framework SwiftUI -framework ServiceManagement -framework Charts -framework AppIntents

# Copy Resources
echo "Copying resources..."
if [ -d "App/Resources" ]; then
    cp App/Resources/* "$RESOURCES_DIR/"
fi

# Copy plist
cp Daemon/launchd.plist "$DAEMONS_DIR/com.chargecontrol.daemon.plist"

# Create Info.plist for App
cat << 'PLIST' > "$CONTENTS_DIR/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>ChargeControl</string>
    <key>CFBundleIdentifier</key>
    <string>com.chargecontrol.app</string>
    <key>CFBundleName</key>
    <string>ChargeControl</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.2</string>
    <key>CFBundleVersion</key>
    <string>3</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

echo "Signing binaries..."
codesign -s - --force --deep "$MACOS_DIR/ChargeControlDaemon"
codesign -s - --force --deep "$MACOS_DIR/cc"
codesign -s - --force --deep "$APP_DIR"

echo "Build complete at $APP_DIR"
