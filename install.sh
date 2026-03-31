#!/bin/bash
set -e

REPO="will2022/ChargeControl"
APP_NAME="ChargeControl.app"
APP_DEST="/Applications/ChargeControl.app"

echo "🚀 Installing ChargeControl..."

# 1. Fetch latest release info
echo "Step 1: Finding latest version..."
LATEST_RELEASE=$(curl -s "https://api.github.com/repos/$REPO/releases/latest")
DOWNLOAD_URL=$(echo "$LATEST_RELEASE" | grep "browser_download_url.*ChargeControl.dmg" | cut -d '"' -f 4)

if [ -z "$DOWNLOAD_URL" ]; then
    echo "❌ Error: Could not find the latest DMG release on GitHub."
    exit 1
fi

# 2. Download DMG
echo "Step 2: Downloading ChargeControl.dmg..."
curl -L -o /tmp/ChargeControl.dmg "$DOWNLOAD_URL"

# 3. Mount DMG
echo "Step 3: Mounting Disk Image..."
MOUNT_POINT=$(hdiutil attach /tmp/ChargeControl.dmg -nobrowse | grep /Volumes | awk '{print $3}')

# 4. Install App
echo "Step 4: Installing to /Applications..."
if [ -d "$APP_DEST" ]; then
    echo "⚠️ Existing version found. Replacing..."
    sudo rm -rf "$APP_DEST"
fi
sudo cp -R "$MOUNT_POINT/$APP_NAME" /Applications/

# 5. Cleanup
echo "Step 5: Cleaning up..."
hdiutil detach "$MOUNT_POINT"
rm /tmp/ChargeControl.dmg

# 6. Optional: Link CLI
echo "Step 6: Setting up 'cc' command..."
if [ ! -L /usr/local/bin/cc ]; then
    sudo ln -s "$APP_DEST/Contents/MacOS/cc" /usr/local/bin/cc
    echo "✅ 'cc' command linked to /usr/local/bin/cc"
fi

echo "🎉 Finished! You can now open ChargeControl from your Applications folder."
