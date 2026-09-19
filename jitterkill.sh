#!/usr/bin/env bash
# ==============================================================================
# 🎮 UNIVERSAL MOONLIGHT & TAILSCALE OPTIMIZER FOR macOS
# ------------------------------------------------------------------------------
# Supports all 3 Moonlight clients:
#   • Moonlight.app
#   • Moonlight Legacy.app
#   • Moonlight V+.app
#
# Adaptable streaming modes:
#   • Windows Mobile Hotspot Mode (192.168.137.1)
#   • Tailscale Remote Mesh Mode (Direct P2P vs DERP Relay check)
#   • Local Home LAN / Wi-Fi Mode
#
# Can run:
#   1. Automatically in the background via LaunchDaemon:
#      sudo ~/smooth_stream.sh --install
#   2. Interactively in Terminal:
#      stream-mode  (or sudo ~/smooth_stream.sh)
# ==============================================================================

DAEMON_LABEL="com.psychostark.moonlight-optimizer"
PLIST_PATH="/Library/LaunchDaemons/${DAEMON_LABEL}.plist"
SCRIPT_PATH="/Users/psychostark/Documents/projects/JitterKill/jitterkill.sh"
LOG_PATH="/var/log/moonlight-optimizer.log"

# Ensure script is run with sudo (except for read-only --status)
if [ "$1" != "--status" ] && [ "$EUID" -ne 0 ]; then
  echo ""
  echo "⚠️  Administrator privileges required."
  echo "👉 Please run with sudo:"
  echo "   sudo $0 $@"
  echo ""
  exit 1
fi

# Detect active non-root console user
CONSOLE_USER="${SUDO_USER:-$(stat -f '%Su' /dev/console 2>/dev/null)}"
if [ -z "$CONSOLE_USER" ] || [ "$CONSOLE_USER" = "root" ]; then
  CONSOLE_USER=$(id -un 501 2>/dev/null || echo "psychostark")
fi
CONSOLE_HOME=$(eval echo "~$CONSOLE_USER")

# ------------------------------------------------------------------------------
# Desktop Notification Helper
# ------------------------------------------------------------------------------
notify_user() {
  local title="$1"
  local message="$2"
  if [ -n "$CONSOLE_USER" ] && [ "$CONSOLE_USER" != "root" ]; then
    sudo -u "$CONSOLE_USER" osascript -e "display notification \"$message\" with title \"$title\"" >/dev/null 2>&1 || true
  fi
}

# ------------------------------------------------------------------------------
# Moonlight Process Detector (Matches all 3 clients)
# ------------------------------------------------------------------------------
is_moonlight_running() {
  pgrep -x "Moonlight" >/dev/null 2>&1 || \
  pgrep -f "Contents/MacOS/Moonlight" >/dev/null 2>&1
}

get_moonlight_pids() {
  pgrep -x "Moonlight" 2>/dev/null || \
  pgrep -f "Contents/MacOS/Moonlight" 2>/dev/null
}

# ------------------------------------------------------------------------------
# Streaming Mode Detector (Hotspot vs Tailscale vs LAN)
# ------------------------------------------------------------------------------
detect_streaming_mode() {
  local ts_bin="/Applications/Tailscale.app/Contents/MacOS/Tailscale"
  local is_tailscale=0
  local ts_status=""

  if [ -x "$ts_bin" ]; then
    ts_status=$("$ts_bin" status 2>/dev/null || true)
    if [ -n "$ts_status" ] && ! echo "$ts_status" | grep -iq "stopped"; then
      is_tailscale=1
    fi
  fi

  local gw
  gw=$(route -n get default 2>/dev/null | awk '/gateway:/ {print $2}')
  local domain
  domain=$(ipconfig getpacket en0 2>/dev/null | awk '/domain_name \(string\):/ {print $3}')

  # Dynamically detect Windows Hotspot (domain mshome.net, 192.168.137.x subnet, or nitro-5 hostname)
  if [ "$domain" = "mshome.net" ] || [[ "$gw" =~ ^192\.168\.137\. ]] || arp -a 2>/dev/null | grep -iqE "mshome\.net|nitro"; then
    STREAM_MODE="Windows Hotspot (Nitro-5 @ ${gw:-dynamic})"
    MODE_TYPE="HOTSPOT"
  elif [ "$is_tailscale" -eq 1 ]; then
    if echo "$ts_status" | grep -iq "relay"; then
      STREAM_MODE="Tailscale (⚠️ DERP Relay Detected)"
      MODE_TYPE="TAILSCALE_RELAY"
    else
      STREAM_MODE="Tailscale (✅ Direct P2P)"
      MODE_TYPE="TAILSCALE_DIRECT"
    fi
  else
    STREAM_MODE="Local Wi-Fi / LAN (${gw:-gateway})"
    MODE_TYPE="LAN"
  fi
}

# ------------------------------------------------------------------------------
# State Variables
# ------------------------------------------------------------------------------
ORIG_AIRDROP="Off"
ORIG_HANDOFF_ADV="0"
ORIG_HANDOFF_REC="0"
ORIG_UNIVERSAL_CTRL="0"
ORIG_AIRPLAY_RECV="0"
ORIG_LOCATION="0"
ORIG_DELAYED_ACK="3"
LOC_PLIST=""
PAUSED_PIDS=()
OPTIMIZED_ACTIVE=0

# ------------------------------------------------------------------------------
# Snapshot Initial System Settings
# ------------------------------------------------------------------------------
snapshot_settings() {
  ORIG_AIRDROP=$(sudo -u "$CONSOLE_USER" defaults read com.apple.sharingd DiscoverableMode 2>/dev/null || echo "Off")
  ORIG_HANDOFF_ADV=$(sudo -u "$CONSOLE_USER" defaults -currentHost read com.apple.coreservices.useractivityd ActivityAdvertisingAllowed 2>/dev/null || echo "0")
  ORIG_HANDOFF_REC=$(sudo -u "$CONSOLE_USER" defaults -currentHost read com.apple.coreservices.useractivityd ActivityReceivingAllowed 2>/dev/null || echo "0")
  ORIG_UNIVERSAL_CTRL=$(sudo -u "$CONSOLE_USER" defaults -currentHost read com.apple.universalcontrol Disable 2>/dev/null || echo "0")
  ORIG_AIRPLAY_RECV=$(sudo -u "$CONSOLE_USER" defaults -currentHost read com.apple.controlcenter "AirplayReciever" 2>/dev/null || echo "0")

  local loc_dir="/var/db/locationd/Library/Preferences/ByHost"
  LOC_PLIST=$(find "$loc_dir" -name "com.apple.locationd.*.plist" 2>/dev/null | head -n 1)
  ORIG_LOCATION="0"
  if [ -n "$LOC_PLIST" ] && [ -f "$LOC_PLIST" ]; then
    ORIG_LOCATION=$(defaults read "${LOC_PLIST%.plist}" LocationServicesEnabled 2>/dev/null || echo "0")
  fi

  ORIG_DELAYED_ACK=$(sysctl -n net.inet.tcp.delayed_ack 2>/dev/null || echo "3")
  PAUSED_PIDS=()
}

# ------------------------------------------------------------------------------
# Apply Optimizations
# ------------------------------------------------------------------------------
apply_optimizations() {
  if [ "$OPTIMIZED_ACTIVE" -eq 1 ]; then
    return
  fi

  snapshot_settings
  detect_streaming_mode

  echo "[$(date '+%H:%M:%S')] 🎮 Activating Gaming Optimization..."
  echo "[$(date '+%H:%M:%S')] 📡 Detected Mode: $STREAM_MODE"

  # Silence AirDrop, Handoff, Universal Control, AirPlay
  sudo -u "$CONSOLE_USER" defaults write com.apple.sharingd DiscoverableMode -string "Off" 2>/dev/null
  killall -HUP sharingd 2>/dev/null

  sudo -u "$CONSOLE_USER" defaults -currentHost write com.apple.coreservices.useractivityd ActivityAdvertisingAllowed -bool false 2>/dev/null
  sudo -u "$CONSOLE_USER" defaults -currentHost write com.apple.coreservices.useractivityd ActivityReceivingAllowed -bool false 2>/dev/null
  killall -HUP useractivityd 2>/dev/null

  sudo -u "$CONSOLE_USER" defaults -currentHost write com.apple.universalcontrol Disable -bool true 2>/dev/null
  sudo -u "$CONSOLE_USER" defaults -currentHost write com.apple.controlcenter "AirplayReciever" -bool false 2>/dev/null

  # Silence Location Services
  if [ -n "$LOC_PLIST" ] && [ -f "$LOC_PLIST" ]; then
    defaults write "${LOC_PLIST%.plist}" LocationServicesEnabled -int 0 2>/dev/null
    killall -HUP locationd 2>/dev/null
  fi

  # Kernel TCP tuning
  sysctl -w net.inet.tcp.delayed_ack=0 >/dev/null 2>&1

  # Drop P2P Wi-Fi interfaces
  ifconfig awdl0 down 2>/dev/null
  ifconfig llw0 down 2>/dev/null
  ifconfig nan0 down 2>/dev/null

  # Pause jitter-inducing background apps
  for p in $(pgrep -i "localsend" 2>/dev/null); do
    kill -STOP "$p" 2>/dev/null && PAUSED_PIDS+=("$p")
  done
  for p in $(pgrep -i "pock" 2>/dev/null); do
    kill -STOP "$p" 2>/dev/null && PAUSED_PIDS+=("$p")
  done

  # Boost Moonlight and Tailscale priority to real-time (-20)
  for p in $(get_moonlight_pids); do
    renice -20 -p "$p" >/dev/null 2>&1
  done
  for p in $(pgrep -i "tailscale" 2>/dev/null); do
    renice -20 -p "$p" >/dev/null 2>&1
  done

  OPTIMIZED_ACTIVE=1

  # Trigger desktop notification
  if [ "$MODE_TYPE" = "TAILSCALE_RELAY" ]; then
    notify_user "⚠️ Moonlight Active (Tailscale Relay)" "Traffic is relayed via DERP! High latency likely."
  else
    notify_user "🎮 Moonlight Optimizer Active" "Mode: $STREAM_MODE"
  fi
}

# ------------------------------------------------------------------------------
# Revert Optimizations
# ------------------------------------------------------------------------------
revert_optimizations() {
  if [ "$OPTIMIZED_ACTIVE" -eq 0 ]; then
    return
  fi

  echo "[$(date '+%H:%M:%S')] ✨ Moonlight quit. Restoring all system settings..."

  # Re-enable Wi-Fi P2P interfaces
  ifconfig awdl0 up 2>/dev/null
  ifconfig llw0 up 2>/dev/null
  ifconfig nan0 up 2>/dev/null

  # Restore AirDrop
  sudo -u "$CONSOLE_USER" defaults write com.apple.sharingd DiscoverableMode -string "$ORIG_AIRDROP" 2>/dev/null
  killall -HUP sharingd 2>/dev/null

  # Restore Handoff
  local adv_bool=$([ "$ORIG_HANDOFF_ADV" = "1" ] && echo "true" || echo "false")
  local rec_bool=$([ "$ORIG_HANDOFF_REC" = "1" ] && echo "true" || echo "false")
  sudo -u "$CONSOLE_USER" defaults -currentHost write com.apple.coreservices.useractivityd ActivityAdvertisingAllowed -bool "$adv_bool" 2>/dev/null
  sudo -u "$CONSOLE_USER" defaults -currentHost write com.apple.coreservices.useractivityd ActivityReceivingAllowed -bool "$rec_bool" 2>/dev/null
  killall -HUP useractivityd 2>/dev/null

  # Restore Universal Control
  local uc_bool=$([ "$ORIG_UNIVERSAL_CTRL" = "1" ] && echo "true" || echo "false")
  sudo -u "$CONSOLE_USER" defaults -currentHost write com.apple.universalcontrol Disable -bool "$uc_bool" 2>/dev/null

  # Restore AirPlay Receiver
  local ar_bool=$([ "$ORIG_AIRPLAY_RECV" = "1" ] && echo "true" || echo "false")
  sudo -u "$CONSOLE_USER" defaults -currentHost write com.apple.controlcenter "AirplayReciever" -bool "$ar_bool" 2>/dev/null

  # Restore Location Services
  if [ -n "$LOC_PLIST" ] && [ -f "$LOC_PLIST" ]; then
    defaults write "${LOC_PLIST%.plist}" LocationServicesEnabled -int "$ORIG_LOCATION" 2>/dev/null
    killall -HUP locationd 2>/dev/null
  fi

  # Restore TCP Delayed ACK
  sysctl -w net.inet.tcp.delayed_ack="$ORIG_DELAYED_ACK" >/dev/null 2>&1

  # Unpause background apps
  if [ ${#PAUSED_PIDS[@]} -gt 0 ]; then
    for pid in "${PAUSED_PIDS[@]}"; do
      kill -CONT "$pid" 2>/dev/null
    done
    PAUSED_PIDS=()
  fi

  OPTIMIZED_ACTIVE=0
  notify_user "✨ Moonlight Closed" "All network & system settings restored to normal."
}

# ------------------------------------------------------------------------------
# Enforcement Routine (Called periodically while Moonlight is open)
# ------------------------------------------------------------------------------
enforce_lockdown() {
  ifconfig awdl0 down 2>/dev/null
  ifconfig llw0 down 2>/dev/null
  ifconfig nan0 down 2>/dev/null

  for p in $(get_moonlight_pids); do
    renice -20 -p "$p" >/dev/null 2>&1
  done
  for p in $(pgrep -i "tailscale" 2>/dev/null); do
    renice -20 -p "$p" >/dev/null 2>&1
  done
}

# ------------------------------------------------------------------------------
# Service Management (--install, --uninstall, --status)
# ------------------------------------------------------------------------------
# System daemon target path (outside of protected ~/Documents to bypass macOS TCC sandbox)
DAEMON_EXEC_PATH="/usr/local/bin/jitterkill-daemon"

install_daemon() {
  echo "[*] Installing Moonlight Auto-Optimizer LaunchDaemon..."

  # Copy script to /usr/local/bin where root launchd daemons can run without macOS TCC / Documents sandbox block
  mkdir -p /usr/local/bin
  cp "$SCRIPT_PATH" "$DAEMON_EXEC_PATH"
  chmod 755 "$DAEMON_EXEC_PATH"

  cat <<EOF > "$PLIST_PATH"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${DAEMON_LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>${DAEMON_EXEC_PATH}</string>
        <string>--watch</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>${LOG_PATH}</string>
    <key>StandardErrorPath</key>
    <string>${LOG_PATH}</string>
</dict>
</plist>
EOF

  chown root:wheel "$PLIST_PATH"
  chmod 644 "$PLIST_PATH"

  # Unload if already loaded, then load
  launchctl bootout system "$PLIST_PATH" 2>/dev/null || launchctl unload "$PLIST_PATH" 2>/dev/null || true
  launchctl bootstrap system "$PLIST_PATH" 2>/dev/null || launchctl load -w "$PLIST_PATH" 2>/dev/null || true

  echo ""
  echo "✅ Auto-Optimizer Daemon successfully installed and running!"
  echo "   • Status: Active in background across all 3 Moonlight clients."
  echo "   • Behavior: Activates when Moonlight opens, restores when Moonlight quits."
  echo "   • Daemon Executable: ${DAEMON_EXEC_PATH}"
  echo "   • Logs: View anytime with 'tail -f ${LOG_PATH}'"
  echo "   • Uninstall anytime: 'sudo ${SCRIPT_PATH} --uninstall'"
  exit 0
}

uninstall_daemon() {
  echo "[*] Uninstalling Moonlight Auto-Optimizer LaunchDaemon..."
  launchctl bootout system "$PLIST_PATH" 2>/dev/null || launchctl unload "$PLIST_PATH" 2>/dev/null || true
  rm -f "$PLIST_PATH"
  rm -f "$DAEMON_EXEC_PATH"
  revert_optimizations
  echo "✅ Auto-Optimizer Daemon has been removed."
  exit 0
}

status_daemon() {
  echo "=========================================================="
  echo " 📊 Moonlight Optimizer Status"
  echo "=========================================================="
  if [ -f "$PLIST_PATH" ]; then
    echo " Daemon Service:  INSTALLED ($PLIST_PATH)"
    if sudo launchctl list 2>/dev/null | grep -q "$DAEMON_LABEL" || launchctl print "system/$DAEMON_LABEL" 2>/dev/null | grep -q "state = running"; then
      echo " Daemon Status:   RUNNING in background ✅"
    else
      echo " Daemon Status:   STOPPED ⚠️ (re-run 'stream-install')"
    fi
  else
    echo " Daemon Service:  NOT INSTALLED (run 'stream-install')"
  fi

  if is_moonlight_running; then
    detect_streaming_mode
    echo " Moonlight App:   RUNNING (PIDs: $(get_moonlight_pids | tr '\n' ' '))"
    echo " Streaming Mode:  $STREAM_MODE"
    echo " Optimization:    ACTIVE 🚀"
  else
    echo " Moonlight App:   NOT RUNNING (Standby/Idle 💤)"
  fi
  echo "=========================================================="
  exit 0
}

# Handle command line flags
case "$1" in
  --install)
    install_daemon
    ;;
  --uninstall)
    uninstall_daemon
    ;;
  --status)
    status_daemon
    ;;
  --watch)
    # Background Daemon loop
    trap revert_optimizations INT TERM EXIT
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Moonlight Optimizer Daemon started (watching for Moonlight)..."
    while true; do
      if is_moonlight_running; then
        if [ "$OPTIMIZED_ACTIVE" -eq 0 ]; then
          apply_optimizations
        else
          enforce_lockdown
        fi
      else
        if [ "$OPTIMIZED_ACTIVE" -eq 1 ]; then
          revert_optimizations
        fi
      fi
      sleep 1
    done
    ;;
  *)
    # Interactive Foreground Mode (stream-mode)
    trap revert_optimizations INT TERM EXIT
    detect_streaming_mode

    echo "================================================================================"
    echo " 🚀 MOONLIGHT STREAM OPTIMIZER (INTERACTIVE MODE)"
    echo " Mode: $STREAM_MODE"
    echo "================================================================================"
    apply_optimizations
    echo ""
    echo "✅ Optimizer is ACTIVE! awdl0, llw0, nan0 are pinned DOWN."
    echo "🎮 Start your Moonlight session now."
    echo ">>> Press [ Ctrl + C ] in this window when you finish to restore everything."
    echo "--------------------------------------------------------------------------------"

    while true; do
      enforce_lockdown
      sleep 1
    done
    ;;
esac
