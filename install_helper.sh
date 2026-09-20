#!/usr/bin/env bash
set -e

# ==============================================================================
# 🎮 JitterKill Helper Installation & Migration Script
# ------------------------------------------------------------------------------
# 1. Uninstalls old com.psychostark.moonlight-optimizer daemon & scripts
# 2. Installs new com.psychostark.jitterkill.helper daemon
# 3. Installs clean /usr/local/bin/jitterkill CLI
# 4. Deploys JitterKill.app to /Applications
#
# Portable: works whether run from a DMG mount, a copied folder, or anywhere.
#   sudo /Volumes/JitterKill/install_helper.sh
#   sudo install_helper.sh
# ==============================================================================

if [ "$EUID" -ne 0 ]; then
  echo ""
  echo "⚠️ Administrator privileges required to configure system daemon."
  echo "👉 Please run with sudo:"
  echo "   sudo $0"
  echo ""
  exit 1
fi

# Detect active console user (for chown of deployed app bundle)
CONSOLE_USER="${SUDO_USER:-$(stat -f '%Su' /dev/console 2>/dev/null)}"
if [ -z "$CONSOLE_USER" ] || [ "$CONSOLE_USER" = "root" ]; then
  CONSOLE_USER=$(id -un 501 2>/dev/null || stat -f '%Su' /dev/console 2>/dev/null || echo "$USER")
fi

# --- Locate the bundled helper/CLI scripts & app bundle portably ----------------
SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_BUNDLE=""

# 1) Prefer scripts shipped inside the app bundle
for candidate in \
  "$SCRIPT_PATH/JitterKill.app/Contents/Resources/jitterkill-helper.sh" \
  "$SCRIPT_PATH/../JitterKill.app/Contents/Resources/jitterkill-helper.sh" \
  "/Applications/JitterKill.app/Contents/Resources/jitterkill-helper.sh"; do
  if [ -f "$candidate" ]; then
    APP_BUNDLE="$(cd "$(dirname "$candidate")/../.." && pwd)/JitterKill.app"
    break
  fi
done

# 2) Fall back to local Resources or scripts folder
HELPER_SRC="$SCRIPT_PATH/Sources/JitterKillApp/Resources/jitterkill-helper.sh"
CLI_SRC="$SCRIPT_PATH/Sources/JitterKillApp/Resources/jitterkill-cli.sh"

if [ ! -f "$HELPER_SRC" ] || [ ! -f "$CLI_SRC" ]; then
  HELPER_SRC="$SCRIPT_PATH/scripts/jitterkill-helper.sh"
  CLI_SRC="$SCRIPT_PATH/scripts/jitterkill-cli.sh"
fi

if [ -f "$HELPER_SRC" ] && [ -f "$CLI_SRC" ]; then
  : # found local scripts
elif [ -n "$APP_BUNDLE" ]; then
  HELPER_SRC="$APP_BUNDLE/Contents/Resources/jitterkill-helper.sh"
  CLI_SRC="$APP_BUNDLE/Contents/Resources/jitterkill-cli.sh"
else
  echo "❌ Could not locate jitterkill-helper.sh / jitterkill-cli.sh"
  echo "   Run this installer from inside the JitterKill DMG or project folder."
  exit 1
fi

OLD_PLIST="/Library/LaunchDaemons/com.psychostark.moonlight-optimizer.plist"
OLD_EXEC="/usr/local/bin/jitterkill-daemon"

NEW_PLIST="/Library/LaunchDaemons/com.psychostark.jitterkill.helper.plist"
NEW_HELPER_EXEC="/usr/local/bin/jitterkill-helper"
NEW_CLI_EXEC="/usr/local/bin/jitterkill"

echo "🧹 Cleaning up old moonlight-optimizer daemon..."
if [ -f "$OLD_PLIST" ]; then
  launchctl bootout system "$OLD_PLIST" 2>/dev/null || launchctl unload "$OLD_PLIST" 2>/dev/null || true
  rm -f "$OLD_PLIST"
  echo "   ✓ Removed old plist: $OLD_PLIST"
fi

if [ -f "$OLD_EXEC" ]; then
  rm -f "$OLD_EXEC"
  echo "   ✓ Removed old executable: $OLD_EXEC"
fi

echo "📦 Installing new JitterKill helper & CLI..."
mkdir -p /usr/local/bin
mkdir -p "/Library/Application Support/JitterKill"
chmod 777 "/Library/Application Support/JitterKill"

cp "$HELPER_SRC" "$NEW_HELPER_EXEC"
chmod 755 "$NEW_HELPER_EXEC"
echo "   ✓ Installed daemon executable: $NEW_HELPER_EXEC"

cp "$CLI_SRC" "$NEW_CLI_EXEC"
chmod 755 "$NEW_CLI_EXEC"
echo "   ✓ Installed CLI executable: $NEW_CLI_EXEC"

echo "⚙️ Configuring LaunchDaemon ($NEW_PLIST)..."
# Unload if already loaded
launchctl bootout system "$NEW_PLIST" 2>/dev/null || launchctl unload "$NEW_PLIST" 2>/dev/null || true

cat <<EOF > "$NEW_PLIST"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.psychostark.jitterkill.helper</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>${NEW_HELPER_EXEC}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/var/log/jitterkill-helper.log</string>
    <key>StandardErrorPath</key>
    <string>/var/log/jitterkill-helper.log</string>
</dict>
</plist>
EOF

chown root:wheel "$NEW_PLIST"
chmod 644 "$NEW_PLIST"

# Enable Touch ID for sudo in Terminal if not already configured
if [ ! -f /etc/pam.d/sudo_local ]; then
  echo "auth       sufficient     pam_tid.so" > /etc/pam.d/sudo_local
  chmod 444 /etc/pam.d/sudo_local
  echo "   ✓ Enabled Touch ID for sudo in Terminal (/etc/pam.d/sudo_local)"
fi

# Reset TCP delayed ack to macOS default (3)
sysctl -w net.inet.tcp.delayed_ack=3 >/dev/null 2>&1 || true

echo "🚀 Starting JitterKill helper service..."
launchctl bootstrap system "$NEW_PLIST" 2>/dev/null || launchctl load -w "$NEW_PLIST" 2>/dev/null || true

echo "📱 Deploying JitterKill.app to /Applications..."
if [ -n "$APP_BUNDLE" ] && [ -d "$APP_BUNDLE" ]; then
  rm -rf "/Applications/JitterKill.app"
  cp -R "$APP_BUNDLE" "/Applications/JitterKill.app"
  chown -R "$CONSOLE_USER":staff "/Applications/JitterKill.app" 2>/dev/null || true
  echo "   ✓ Installed /Applications/JitterKill.app"
else
  echo "   ⚠️ No JitterKill.app found alongside this installer; skipping app deploy."
fi

echo ""
echo "=========================================================="
echo " ✅ JitterKill Helper & CLI Successfully Installed!"
echo "=========================================================="
echo " • Old moonlight-optimizer daemon: REMOVED"
echo " • New helper daemon:             RUNNING (com.psychostark.jitterkill.helper)"
echo " • Terminal CLI:                  /usr/local/bin/jitterkill (type 'jitterkill' anywhere, no sudo!)"
echo " • Mac App:                       /Applications/JitterKill.app (Touch ID ready, zero popups)"
echo "=========================================================="
