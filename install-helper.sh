#!/bin/bash
set -e

APP_PATH="/Applications/ChargeControl.app"

if [ ! -d "$APP_PATH" ]; then
    echo "Error: Please copy ChargeControl.app to /Applications first."
    exit 1
fi

DAEMON_PLIST="/Library/LaunchDaemons/com.chargecontrol.daemon.plist"
HELPER_BIN="$APP_PATH/Contents/MacOS/ChargeControlDaemon"

echo "Creating and Installing Daemon Plist..."
sudo cat << PLIST > /tmp/com.chargecontrol.daemon.plist
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>com.chargecontrol.daemon</string>
	<key>Program</key>
	<string>$HELPER_BIN</string>
	<key>MachServices</key>
	<dict>
		<key>com.chargecontrol.daemon</key>
		<true/>
	</dict>
	<key>RunAtLoad</key>
	<true/>
	<key>KeepAlive</key>
	<true/>
</dict>
</plist>
PLIST

sudo cp /tmp/com.chargecontrol.daemon.plist "$DAEMON_PLIST"

# Fix permissions
sudo chown root:wheel "$DAEMON_PLIST"
sudo chmod 644 "$DAEMON_PLIST"

echo "Loading Daemon..."
sudo launchctl bootout system "$DAEMON_PLIST" 2>/dev/null || true
sudo launchctl bootstrap system "$DAEMON_PLIST"

echo "Done! The background daemon is now running."
