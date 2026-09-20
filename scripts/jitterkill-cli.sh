#!/usr/bin/env bash
# ==============================================================================
# 🎮 JitterKill CLI — Fast, clean terminal controller (NO SUDO NEEDED)
# ==============================================================================

CONTROL_FILE="/tmp/jitterkill.control"
STATUS_FILE="/tmp/jitterkill.status"
CONFIG_FILE="/Library/Application Support/JitterKill/apps.json"
TMP_CONFIG_FILE="/tmp/jitterkill.apps.json"

print_status() {
  echo "=========================================================="
  echo " 🎮 JitterKill — Game Streaming Optimizer"
  echo "=========================================================="

  # Check if helper daemon is running
  if ! launchctl print system/com.psychostark.jitterkill.helper >/dev/null 2>&1 && \
     ! launchctl list com.psychostark.jitterkill.helper >/dev/null 2>&1 && \
     ! pgrep -f "jitterkill-helper" >/dev/null 2>&1; then
    echo " ⚠️ Helper Daemon: NOT RUNNING"
    echo "    Launch JitterKill.app to install or repair the helper service,"
    echo "    or run: open -a JitterKill"
    echo "=========================================================="
    return
  fi

  local active="0"
  local mode="Detecting..."
  local ctrl="auto"
  local trigger="None"
  local detected=""
  local awdl_up="true"
  local ack="3"

  if [ -f "$STATUS_FILE" ]; then
    active=$(grep -o '"active": *[0-9]*' "$STATUS_FILE" | awk '{print $2}')
    mode=$(grep -o '"mode": *"[^"]*"' "$STATUS_FILE" | cut -d'"' -f4)
    ctrl=$(grep -o '"control": *"[^"]*"' "$STATUS_FILE" | cut -d'"' -f4)
    trigger=$(grep -o '"trigger_app": *"[^"]*"' "$STATUS_FILE" | cut -d'"' -f4)
    awdl_up=$(grep -o '"awdl_up": *[a-z]*' "$STATUS_FILE" | awk '{print $2}')
    ack=$(grep -o '"delayed_ack": *[0-9]*' "$STATUS_FILE" | awk '{print $2}')
    # Extract detected apps array elements
    detected=$(python3 -c "
import json
try:
    with open('$STATUS_FILE') as f:
        d = json.load(f)
        apps = [a.strip() for a in d.get('detected_apps', []) if a and a.strip()]
        print(', '.join(apps) if apps else '')
except:
    pass
" 2>/dev/null)
  else
    # Read live directly
    ifconfig awdl0 2>/dev/null | head -1 | grep -q "<UP" && awdl_up="true" || awdl_up="false"
    ack=$(sysctl -n net.inet.tcp.delayed_ack 2>/dev/null || echo 3)
    [ "$awdl_up" = "false" ] && active="1" || active="0"
  fi

  if [ "$active" = "1" ]; then
    echo " 🟢 Status:       ACTIVE (Locked down for gaming 🚀)"
  else
    echo " ⚪ Status:       STANDBY (Normal macOS operation 💤)"
  fi

  echo " 📡 Network Mode: $mode"
  echo " 🎛️ Control Mode: ${ctrl:-auto}"

  if [ "$trigger" != "None" ] && [ -n "$trigger" ]; then
    echo " 🎯 Trigger App:  $trigger"
  fi

  if [ -n "$detected" ]; then
    echo " 🎮 Streaming:    $detected (Active)"
  else
    echo " 🎮 Streaming:    No streaming apps detected (Standby 💤)"
  fi

  if [ "$awdl_up" = "false" ]; then
    echo " 🔒 Interfaces:   awdl0: LOCKED DOWN ✓ | llw0: LOCKED DOWN ✓"
  else
    echo " 🔓 Interfaces:   awdl0: ACTIVE (UP)   | llw0: ACTIVE (UP)"
  fi

  if [ "$ack" = "0" ]; then
    echo " ⚡ TCP ACK:      Instant (delayed_ack=0) ✓"
  else
    echo " ⏳ TCP ACK:      Delayed (delayed_ack=$ack)"
  fi

  echo "=========================================================="
  echo " Usage:"
  echo "   jitterkill on       Force lockdown ON immediately"
  echo "   jitterkill off      Force lockdown OFF (restore defaults)"
  echo "   jitterkill auto     Return to auto-watch (streaming apps auto-detect)"
  echo "   jitterkill apps     List monitored streaming apps & priority settings"
  echo "   jitterkill app      Open native macOS Dashboard"
  echo "=========================================================="
}

print_apps() {
  local target_conf=""
  if [ -f "$CONFIG_FILE" ]; then
    target_conf="$CONFIG_FILE"
  elif [ -f "$TMP_CONFIG_FILE" ]; then
    target_conf="$TMP_CONFIG_FILE"
  fi

  if [ -z "$target_conf" ]; then
    echo "⚠️ No configuration file found at $CONFIG_FILE"
    return
  fi

  echo "================================================================================"
  echo " 🎮 JitterKill — Monitored Streaming Apps & Priority Rules"
  echo "================================================================================"
  printf " %-24s  %-15s  %-12s  %-20s\n" "APP NAME" "AUTO-ACTIVATE" "PRIORITY" "CURRENT STATUS"
  echo "--------------------------------------------------------------------------------"

  python3 -c "
import json, subprocess, sys

def is_tailscale_active():
    try:
        out = subprocess.check_output(['/Applications/Tailscale.app/Contents/MacOS/Tailscale', 'status'], stderr=subprocess.DEVNULL).decode().strip()
        if out and 'stopped' not in out.lower():
            return True
    except:
        pass
    return False

def get_pids(pattern):
    if pattern in ['IPNExtension', 'tailscaled', 'Tailscale']:
        if not is_tailscale_active():
            return []
    try:
        out = subprocess.check_output(['pgrep', '-x', pattern], stderr=subprocess.DEVNULL).decode().strip()
        if out:
            pids = out.split()
            filtered = []
            for pid in pids:
                try:
                    comm = subprocess.check_output(['ps', '-p', pid, '-o', 'comm='], stderr=subprocess.DEVNULL).decode().strip()
                    if not comm.startswith('/System/Library') and not comm.startswith('/usr/libexec') and not any(comm.endswith(s) for s in ['bash', 'zsh', 'sh', 'python', 'python3', 'pgrep', 'grep']):
                        filtered.append(pid)
                except:
                    pass
            return filtered
    except:
        pass
    return []

try:
    with open(sys.argv[1]) as f:
        apps = json.load(f)
    for a in apps:
        name = a.get('name', 'Unknown')
        auto = 'YES ✓' if a.get('autoActivate', False) else 'NO'
        prio = 'REAL-TIME 🚀' if a.get('boostPriority', False) else 'Normal'
        pats = a.get('processPatterns', [])
        found_pids = []
        for p in pats:
            pids = get_pids(p)
            found_pids.extend(pids)
        
        status = f'RUNNING (PID {\", \".join(found_pids[:3])})' if found_pids else 'Standby 💤'
        print(f' {name:<24}  {auto:<15}  {prio:<12}  {status:<20}')
except Exception as e:
    print(f'Error reading config: {e}')
" "$target_conf"

  echo "================================================================================"
  echo " 💡 Configure apps via JitterKill Dashboard or edit:"
  echo "    $CONFIG_FILE"
  echo "================================================================================"
}

case "$1" in
  on|activate)
    echo "activate" > "$CONTROL_FILE"
    echo "🎮 JitterKill: Forced lockdown ON."
    ;;
  off|deactivate)
    echo "deactivate" > "$CONTROL_FILE"
    echo "✨ JitterKill: Forced lockdown OFF (restored defaults)."
    ;;
  auto)
    rm -f "$CONTROL_FILE"
    echo "🔄 JitterKill: Auto-detection restored (optimizes when streaming apps launch)."
    ;;
  apps|list-apps|rules)
    print_apps
    ;;
  app|ui|gui)
    if [ -d "/Applications/JitterKill.app" ]; then
      open "/Applications/JitterKill.app"
    elif [ -d "$HOME/Applications/JitterKill.app" ]; then
      open "$HOME/Applications/JitterKill.app"
    elif open -a JitterKill 2>/dev/null; then
      :
    else
      echo "❌ JitterKill.app not found in /Applications. Please install JitterKill.app first."
      exit 1
    fi
    echo "🖥️ Opened JitterKill macOS app."
    ;;
  debug|export-logs|logs)
    OUT_FILE="$HOME/Desktop/JitterKill_Debug_$(date +%Y-%m-%d_%H%M%S).txt"
    echo "🔍 Gathering comprehensive JitterKill debug diagnostic..."
    {
      echo "================================================================"
      echo "  JITTERKILL DIAGNOSTIC REPORT — $(date)"
      echo "================================================================"
      echo ""
      echo "--- 1. SYSTEM & HARDWARE ---"
      sw_vers 2>&1
      uname -a 2>&1
      echo ""
      echo "--- 2. IPC STATUS & CONTROL ---"
      echo "Control File (/tmp/jitterkill.control):"
      cat /tmp/jitterkill.control 2>&1 || echo "None"
      echo "Status File (/tmp/jitterkill.status):"
      cat /tmp/jitterkill.status 2>&1 || echo "None"
      echo ""
      echo "--- 3. CONFIGURED APPS RULES ---"
      cat "$CONFIG_FILE" 2>&1 || cat "$TMP_CONFIG_FILE" 2>&1 || echo "None"
      echo ""
      echo "--- 4. NETWORK INTERFACES ---"
      ifconfig awdl0 2>&1
      ifconfig llw0 2>&1
      ifconfig nan0 2>&1
      sysctl net.inet.tcp.delayed_ack 2>&1
      route -n get default 2>&1
      echo ""
      echo "--- 5. DAEMON & PROCESSES ---"
      ps aux | grep -i -E "jitterkill|moonlight|geforce|parsec|steam|tailscale" | grep -v grep 2>&1
      launchctl print system/com.psychostark.jitterkill.helper 2>&1 | head -30
      echo ""
      echo "--- 6. HELPER DAEMON LOG (/var/log/jitterkill-helper.log) ---"
      tail -n 80 /var/log/jitterkill-helper.log 2>&1 || echo "No helper log found"
      echo ""
      echo "--- 7. APPLE P2P SERVICES ---"
      echo "AirDrop: $(defaults read com.apple.sharingd DiscoverableMode 2>/dev/null || echo N/A)"
      echo "Handoff Adv: $(defaults -currentHost read com.apple.coreservices.useractivityd ActivityAdvertisingAllowed 2>/dev/null || echo N/A)"
      echo "Handoff Recv: $(defaults -currentHost read com.apple.coreservices.useractivityd ActivityReceivingAllowed 2>/dev/null || echo N/A)"
      echo "Universal Control: $(defaults -currentHost read com.apple.universalcontrol Disable 2>/dev/null || echo N/A)"
      echo "================================================================"
    } > "$OUT_FILE"
    echo "✅ Debug report saved to: $OUT_FILE"
    head -n 25 "$OUT_FILE"
    ;;
  help|--help|-h)
    print_status
    ;;
  status|"")
    print_status
    ;;
  *)
    echo "Unknown command: $1"
    echo "Valid commands: on | off | auto | apps | status | app | debug"
    exit 1
    ;;
esac
