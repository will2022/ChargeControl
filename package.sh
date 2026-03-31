#!/bin/bash
set -e

# Configuration
APP_NAME="ChargeControl"
BUILD_DIR="build"
DMG_NAME="${APP_NAME}.dmg"
DMG_ROOT="dmg_root"

echo "📦 Packaging $APP_NAME into $DMG_NAME..."

# 1. Ensure we have a fresh build
if [ ! -d "$BUILD_DIR/${APP_NAME}.app" ]; then
    echo "⚠️ Build not found. Running build.sh first..."
    ./build.sh
fi

# 2. Setup DMG root folder
echo "Step 1: Setting up temporary packaging folder..."
rm -rf "$DMG_ROOT"
mkdir -p "$DMG_ROOT"

# 3. Copy the compiled app
echo "Step 2: Copying $APP_NAME.app..."
cp -R "$BUILD_DIR/${APP_NAME}.app" "$DMG_ROOT/"

# 4. Create a symlink to /Applications for the user
echo "Step 3: Creating /Applications symlink..."
ln -s /Applications "$DMG_ROOT/Applications"

# 5. Create the DMG using hdiutil
echo "Step 4: Building the Disk Image (hdiutil)..."
rm -f "$DMG_NAME"
hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_ROOT" -ov -format UDZO "$DMG_NAME"

# 6. Cleanup
echo "Step 5: Cleaning up..."
rm -rf "$DMG_ROOT"

echo "✅ Success! $DMG_NAME is ready for release."
