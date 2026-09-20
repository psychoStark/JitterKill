#!/usr/bin/env bash
# ==============================================================================
# 🎮 JitterKill Privileged Helper Daemon
# ------------------------------------------------------------------------------
# Runs as root via LaunchDaemon: com.psychostark.jitterkill.helper
# Controlled via IPC: /tmp/jitterkill.control
# Reports status to: /tmp/jitterkill.status
# Configured via: /Library/Application Support/JitterKill/apps.json
# ==============================================================================

DAEMON_LABEL="com.psychostark.jitterkill.helper"
CONTROL_FILE="/tmp/jitterkill.control"
STATUS_FILE="/tmp/jitterkill.status"
LOG_PATH="/var/log/jitterkill-helper.log"

CONFIG_DIR="/Library/Application Support/JitterKill"
CONFIG_FILE="$CONFIG_DIR/apps.json"
TMP_CONFIG_FILE="/tmp/jitterkill.apps.json"

# Detect active console user
CONSOLE_USER="${SUDO_USER:-$(stat -f '%Su' /dev/console 2>/dev/null)}"
if [ -z "$CONSOLE_USER" ] || [ "$CONSOLE_USER" = "root" ]; then
  CONSOLE_USER=$(id -un 501 2>/dev/null || echo "psychostark")
fi

# Ensure config directory exists with open permissions for GUI synchronization
mkdir -p "$CONFIG_DIR" 2>/dev/null
chmod 777 "$CONFIG_DIR" 2>/dev/null

# ------------------------------------------------------------------------------
# Default Streaming Apps Preset Seed (Moonlight, GeForce NOW, Parsec, Steam, etc.)
# ------------------------------------------------------------------------------
seed_default_config() {
  cat << 'EOF' > "$CONFIG_FILE"
[
  {
    "id": "moonlight",
    "name": "Moonlight",
    "processPatterns": ["Moonlight", "Moonlight Legacy", "Moonlight V+"],
    "bundleIdentifier": "com.moonlight-stream.Moonlight",
    "autoActivate": true,
    "boostPriority": true,
    "isBuiltIn": true,
    "iconSystemName": "gamecontroller.fill"
  },
  {
    "id": "geforcenow",
    "name": "GeForce NOW",
    "processPatterns": ["GeForceNOW", "GeForce NOW", "GeForceNOWStreamer"],
    "bundleIdentifier": "com.nvidia.gfnpc.mall",
    "autoActivate": true,
    "boostPriority": true,
    "isBuiltIn": true,
    "iconSystemName": "play.tv.fill"
  },
  {
    "id": "parsec",
    "name": "Parsec",
    "processPatterns": ["Parsec"],
    "bundleIdentifier": "com.parsec.client",
    "autoActivate": true,
    "boostPriority": true,
    "isBuiltIn": true,
    "iconSystemName": "display.2"
  },
  {
    "id": "steam",
    "name": "Steam / Steam Link",
    "processPatterns": ["streaming_client", "Steam Link", "steam_osx", "steam"],
    "bundleIdentifier": "com.valvesoftware.steam",
    "autoActivate": true,
    "boostPriority": true,
    "isBuiltIn": true,
    "iconSystemName": "gamecontroller"
  },
  {
    "id": "psremoteplay",
    "name": "PS Remote Play",
    "processPatterns": ["RemotePlay", "PS Remote Play"],
    "bundleIdentifier": "com.playstation.RemotePlay",
    "autoActivate": true,
    "boostPriority": true,
    "isBuiltIn": true,
    "iconSystemName": "gamecontroller.fill"
  },
  {
    "id": "chiaki",
    "name": "Chiaki / Chiaki-ng",
    "processPatterns": ["chiaki", "chiaki-ng", "Chiaki", "Chiaki-ng"],
    "bundleIdentifier": "com.stream.chiaki",
    "autoActivate": true,
    "boostPriority": true,
    "isBuiltIn": true,
    "iconSystemName": "gamecontroller"
  },
  {
    "id": "xbox",
    "name": "Xbox Cloud Gaming",
    "processPatterns": ["Xbox Cloud Gaming", "Better xCloud", "Xbox"],
    "bundleIdentifier": "com.microsoft.xbox",
    "autoActivate": true,
    "boostPriority": true,
    "isBuiltIn": true,
    "iconSystemName": "gamecontroller"
  },
  {
    "id": "shadow",
    "name": "Shadow PC",
    "processPatterns": ["Shadow", "ShadowPC"],
    "bundleIdentifier": "com.blade.shadow",
    "autoActivate": true,
    "boostPriority": true,
    "isBuiltIn": true,
    "iconSystemName": "pc"
  },
  {
    "id": "luna",
    "name": "Amazon Luna",
    "processPatterns": ["Amazon Luna", "Luna"],
    "bundleIdentifier": "com.amazon.luna",
    "autoActivate": true,
    "boostPriority": true,
    "isBuiltIn": true,
    "iconSystemName": "moon.stars.fill"
  },
  {
    "id": "sunshine",
    "name": "Sunshine Server",
    "processPatterns": ["sunshine", "Sunshine"],
    "bundleIdentifier": null,
    "autoActivate": true,
    "boostPriority": true,
    "isBuiltIn": true,
    "iconSystemName": "sun.max.fill"
  },
  {
    "id": "tailscale",
    "name": "Tailscale (Mesh VPN)",
    "processPatterns": ["tailscaled", "Tailscale", "IPNExtension"],
    "bundleIdentifier": "io.tailscale.ipn.mac",
    "autoActivate": false,
    "boostPriority": true,
    "isBuiltIn": true,
    "iconSystemName": "shield.lefthalf.filled"
  }
]
EOF
  chmod 666 "$CONFIG_FILE" 2>/dev/null || true
  cp -f "$CONFIG_FILE" "$TMP_CONFIG_FILE" 2>/dev/null || true
  chmod 666 "$TMP_CONFIG_FILE" 2>/dev/null || true
}

if [ ! -f "$CONFIG_FILE" ] && [ ! -f "$TMP_CONFIG_FILE" ]; then
  seed_default_config
fi

# ------------------------------------------------------------------------------
# App Config Parsing & Mtime-based Caching
# ------------------------------------------------------------------------------
LAST_CONFIG_MTIME=""
CONFIG_RULES_RAW=""

check_config_reload() {
  local target_conf=""
  if [ -f "$CONFIG_FILE" ]; then
    target_conf="$CONFIG_FILE"
  elif [ -f "$TMP_CONFIG_FILE" ]; then
    target_conf="$TMP_CONFIG_FILE"
  fi

  if [ -z "$target_conf" ]; then
    seed_default_config
    target_conf="$CONFIG_FILE"
  fi

  local cur_mtime
  cur_mtime=$(stat -f %m "$target_conf" 2>/dev/null || echo "0")

  if [ "$cur_mtime" != "$LAST_CONFIG_MTIME" ]; then
    LAST_CONFIG_MTIME="$cur_mtime"
    # Parse JSON with /usr/bin/python3 (runs ONLY when config file modified)
    CONFIG_RULES_RAW=$(/usr/bin/python3 -c '
import json, sys
try:
    with open(sys.argv[1], "r") as f:
        data = json.load(f)
    for item in data:
        aid = item.get("id", "")
        aname = item.get("name", "")
        aauto = "1" if item.get("autoActivate", False) else "0"
        aprio = "1" if item.get("boostPriority", False) else "0"
        pats = ",".join(item.get("processPatterns", []))
        if aid and pats:
            print(f"{aid}\t{aname}\t{aauto}\t{aprio}\t{pats}")
except Exception:
    pass
' "$target_conf" 2>/dev/null)
    echo "[$(date '+%H:%M:%S')] 📋 App rules reloaded from $(basename "$target_conf")" >> "$LOG_PATH"
  fi
}

# ------------------------------------------------------------------------------
# Dynamic Streaming App & Process Scanning
# ------------------------------------------------------------------------------
TRIGGER_APP=""
IS_ANY_AUTO_APP_RUNNING=0
DETECTED_APPS_STR=""
PRIORITY_PIDS=()

is_tailscale_active() {
  local ts_bin="/Applications/Tailscale.app/Contents/MacOS/Tailscale"
  [ -x "$ts_bin" ] || return 1
  local ts_status
  ts_status=$("$ts_bin" status 2>/dev/null) || return 1
  if [ -z "$ts_status" ] || echo "$ts_status" | grep -iq "stopped"; then
    return 1
  fi
  return 0
}

get_pids_for_pattern() {
  local p="$1"
  [ -z "$p" ] && return 0

  # Tailscale check: ONLY report PIDs if there is an active mesh connection!
  if [[ "$p" == "IPNExtension" || "$p" == "tailscaled" || "$p" == "Tailscale" ]]; then
    if ! is_tailscale_active; then
      return 0
    fi
  fi

  for pid in $(pgrep -x "$p" 2>/dev/null); do
    local comm_path
    comm_path=$(ps -p "$pid" -o comm= 2>/dev/null)
    if [[ "$comm_path" != /System/Library/* && \
          "$comm_path" != /usr/libexec/* && \
          "$comm_path" != *bash && \
          "$comm_path" != *zsh && \
          "$comm_path" != *sh && \
          "$comm_path" != *python* && \
          "$comm_path" != *pgrep* && \
          "$comm_path" != *grep* ]]; then
      echo "$pid"
    fi
  done
}

scan_streaming_apps() {
  TRIGGER_APP=""
  IS_ANY_AUTO_APP_RUNNING=0
  PRIORITY_PIDS=()
  local detected_list=()

  while IFS=$'\t' read -r aid aname aauto aprio apat; do
    [ -z "$aid" ] && continue
    local app_running=0
    local app_pids=()

    IFS=',' read -ra plist <<< "$apat"
    for p in "${plist[@]}"; do
      [ -z "$p" ] && continue
      local pids
      pids=$(get_pids_for_pattern "$p")
      if [ -n "$pids" ]; then
        for pid in $pids; do
          app_pids+=("$pid")
        done
        app_running=1
      fi
    done

    if [ "$app_running" -eq 1 ]; then
      detected_list+=("\"$aname\"")
      if [ -z "$TRIGGER_APP" ] && [ "$aauto" = "1" ]; then
        TRIGGER_APP="$aname"
        IS_ANY_AUTO_APP_RUNNING=1
      fi
      if [ "$aprio" = "1" ]; then
        PRIORITY_PIDS+=("${app_pids[@]}")
      fi
    fi
  done <<< "$CONFIG_RULES_RAW"

  if [ ${#detected_list[@]} -gt 0 ]; then
    DETECTED_APPS_STR=$(IFS=,; echo "${detected_list[*]}")
  else
    DETECTED_APPS_STR=""
  fi
}

is_moonlight_running() {
  pgrep -x "Moonlight" >/dev/null 2>&1
}

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

  if [ "$domain" = "mshome.net" ] || [[ "$gw" =~ ^192\.168\.137\. ]] || arp -a 2>/dev/null | grep -iqE "mshome\.net"; then
    STREAM_MODE="Windows Hotspot (${gw:-dynamic})"
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
# Snapshot & State Tracking
# ------------------------------------------------------------------------------
ORIG_AIRDROP="Off"
ORIG_HANDOFF_ADV="0"
ORIG_HANDOFF_REC="0"
ORIG_UNIVERSAL_CTRL="0"
ORIG_AIRPLAY_RECV="0"
ORIG_LOCATION="0"
ORIG_DELAYED_ACK="3"
LOC_PLIST=""
OPTIMIZED_ACTIVE=0

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
  if [ -z "$ORIG_DELAYED_ACK" ] || [ "$ORIG_DELAYED_ACK" = "0" ]; then
    ORIG_DELAYED_ACK=3
  fi
}

# ------------------------------------------------------------------------------
# Lockdown Actions
# ------------------------------------------------------------------------------
apply_optimizations() {
  if [ "$OPTIMIZED_ACTIVE" -eq 1 ]; then
    return
  fi

  snapshot_settings
  detect_streaming_mode

  local trig_msg="${TRIGGER_APP:-Manual}"
  echo "[$(date '+%H:%M:%S')] 🎮 Activating JitterKill Lockdown ($STREAM_MODE | Trigger: $trig_msg)..." >> "$LOG_PATH"

  # Silence Apple P2P broadcasts
  sudo -u "$CONSOLE_USER" defaults write com.apple.sharingd DiscoverableMode -string "Off" 2>/dev/null
  killall -HUP sharingd 2>/dev/null

  sudo -u "$CONSOLE_USER" defaults -currentHost write com.apple.coreservices.useractivityd ActivityAdvertisingAllowed -bool false 2>/dev/null
  sudo -u "$CONSOLE_USER" defaults -currentHost write com.apple.coreservices.useractivityd ActivityReceivingAllowed -bool false 2>/dev/null
  killall -HUP useractivityd 2>/dev/null

  sudo -u "$CONSOLE_USER" defaults -currentHost write com.apple.universalcontrol Disable -bool true 2>/dev/null
  sudo -u "$CONSOLE_USER" defaults -currentHost write com.apple.controlcenter "AirplayReciever" -bool false 2>/dev/null

  if [ -n "$LOC_PLIST" ] && [ -f "$LOC_PLIST" ]; then
    defaults write "${LOC_PLIST%.plist}" LocationServicesEnabled -int 0 2>/dev/null
    killall -HUP locationd 2>/dev/null
  fi

  # Kernel TCP tuning: instant ACK
  sysctl -w net.inet.tcp.delayed_ack=0 >/dev/null 2>&1

  # Drop P2P Wi-Fi interfaces
  ifconfig awdl0 down 2>/dev/null
  ifconfig llw0 down 2>/dev/null
  ifconfig nan0 down 2>/dev/null

  # Boost configured priority streaming processes to real-time (-20)
  for p in "${PRIORITY_PIDS[@]}"; do
    [ -n "$p" ] && renice -20 -p "$p" >/dev/null 2>&1
  done

  OPTIMIZED_ACTIVE=1
}

revert_optimizations() {
  echo "[$(date '+%H:%M:%S')] ✨ Deactivating JitterKill Lockdown (Restoring defaults)..." >> "$LOG_PATH"

  # Re-enable Wi-Fi P2P interfaces unconditionally
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

  # Restore TCP Delayed ACK to standard macOS default (3)
  local restore_ack=3
  if [ -n "$ORIG_DELAYED_ACK" ] && [ "$ORIG_DELAYED_ACK" -ne 0 ]; then
    restore_ack="$ORIG_DELAYED_ACK"
  fi
  sysctl -w net.inet.tcp.delayed_ack="$restore_ack" >/dev/null 2>&1

  OPTIMIZED_ACTIVE=0
}

enforce_lockdown() {
  ifconfig awdl0 down 2>/dev/null
  ifconfig llw0 down 2>/dev/null
  ifconfig nan0 down 2>/dev/null

  for p in "${PRIORITY_PIDS[@]}"; do
    [ -n "$p" ] && renice -20 -p "$p" >/dev/null 2>&1
  done
}

write_status() {
  local cur_phase="$1"
  local cur_active="$2"
  detect_streaming_mode
  local awdl_up=$(ifconfig awdl0 2>/dev/null | head -1 | grep -q "<UP" && echo "true" || echo "false")
  local llw_up=$(ifconfig llw0 2>/dev/null | head -1 | grep -q "<UP" && echo "true" || echo "false")
  local ack=$(sysctl -n net.inet.tcp.delayed_ack 2>/dev/null || echo 3)

  cat <<EOF > "${STATUS_FILE}.tmp"
{
  "active": $cur_active,
  "phase": "$cur_phase",
  "mode": "${STREAM_MODE:-Unknown}",
  "control": "${ctrl:-auto}",
  "trigger_app": "${TRIGGER_APP:-None}",
  "detected_apps": [${DETECTED_APPS_STR}],
  "moonlight": $(is_moonlight_running && echo "true" || echo "false"),
  "awdl_up": $awdl_up,
  "llw_up": $llw_up,
  "delayed_ack": $ack,
  "timestamp": $(date +%s)
}
EOF
  mv -f "${STATUS_FILE}.tmp" "${STATUS_FILE}" 2>/dev/null
  chmod 666 "${STATUS_FILE}" 2>/dev/null
}

# ------------------------------------------------------------------------------
# Main Daemon Loop
# ------------------------------------------------------------------------------
trap revert_optimizations INT TERM EXIT
echo "[$(date '+%Y-%m-%d %H:%M:%S')] JitterKill Helper Daemon started" >> "$LOG_PATH"

IDLE_CYCLES=0
DEBOUNCE_CYCLES=4 # 4 * 0.25s = 1 second of stable idle before auto-deactivating

while true; do
  check_config_reload
  scan_streaming_apps

  ctrl=""
  if [ -f "$CONTROL_FILE" ]; then
    ctrl=$(head -n 1 "$CONTROL_FILE" 2>/dev/null | tr -d ' \t\r\n')
  fi

  # Seamless self-update if requested by app/installer
  if [ "$ctrl" = "reload" ] || [ "$ctrl" = "restart" ] || [ "$ctrl" = "update" ]; then
    echo "[$(date '+%H:%M:%S')] 🔄 Helper update/reload requested..." >> "$LOG_PATH"
    if [ -f "/tmp/jitterkill-helper-stage.sh" ]; then
      cp "/tmp/jitterkill-helper-stage.sh" "$0" 2>/dev/null || true
      chmod 755 "$0" 2>/dev/null || true
      rm -f "/tmp/jitterkill-helper-stage.sh"
    fi
    if [ -f "/tmp/jitterkill-cli-stage.sh" ]; then
      cp "/tmp/jitterkill-cli-stage.sh" "/usr/local/bin/jitterkill" 2>/dev/null || true
      chmod 755 "/usr/local/bin/jitterkill" 2>/dev/null || true
      rm -f "/tmp/jitterkill-cli-stage.sh"
    fi
    if [ -d "/Applications/JitterKill.app" ]; then
      chown -R psychostark:staff "/Applications/JitterKill.app" 2>/dev/null || true
      chmod -R 775 "/Applications/JitterKill.app" 2>/dev/null || true
    fi
    revert_optimizations
    echo "deactivate" > "$CONTROL_FILE"
    exec /bin/bash "$0"
  fi

  should_optimize=0
  if [ "$ctrl" = "activate" ]; then
    should_optimize=1
    IDLE_CYCLES=0
  elif [ "$ctrl" = "deactivate" ]; then
    should_optimize=0
    IDLE_CYCLES=999 # immediate manual deactivate
  elif [ "$IS_ANY_AUTO_APP_RUNNING" -eq 1 ]; then
    should_optimize=1
    IDLE_CYCLES=0
  fi

  if [ "$should_optimize" -eq 1 ]; then
    IDLE_CYCLES=0
    if [ "$OPTIMIZED_ACTIVE" -eq 0 ]; then
      write_status "activating" 0
      apply_optimizations
      OPTIMIZED_ACTIVE=1
      write_status "active" 1
    else
      enforce_lockdown
      write_status "active" 1
    fi
  else
    if [ "$OPTIMIZED_ACTIVE" -eq 1 ]; then
      IDLE_CYCLES=$((IDLE_CYCLES + 1))
      if [ "$IDLE_CYCLES" -ge "$DEBOUNCE_CYCLES" ]; then
        write_status "deactivating" 1
        revert_optimizations
        OPTIMIZED_ACTIVE=0
        write_status "idle" 0
        IDLE_CYCLES=0
      else
        # Still active during debounce grace period
        write_status "active" 1
      fi
    else
      IDLE_CYCLES=0
      # If deactivated but delayed_ack is 0, make sure it is reset to 3
      ack=$(sysctl -n net.inet.tcp.delayed_ack 2>/dev/null || echo "3")
      if [ "$ack" = "0" ]; then
        sysctl -w net.inet.tcp.delayed_ack=3 >/dev/null 2>&1
      fi
      write_status "idle" 0
    fi
  fi

  sleep 0.25
done
