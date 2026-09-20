# 🎮 JitterKill

**High-Performance Low-Latency Game Streaming Optimizer for macOS & Windows**  
Specifically designed for Moonlight, Sunshine, GeForce NOW, and Tailscale game streaming. Inspired by [AWDLControl](https://github.com/james-howard/AWDLControl).

Eliminates periodic ping spikes, micro-stutters, and audio dropouts caused by Apple Wireless Direct Link (`awdl0`, `llw0`, `nan0`), background discovery scans, and Windows WLAN AutoConfig.

---

## ✨ Features

- **Triple-Interface Wi-Fi Lockdown:** Simultaneously downs and holds down `awdl0`, `llw0` (Skywalk), and `nan0` (Wi-Fi Aware) to prevent the Wi-Fi chip from hopping off-channel.
- **Darwin Kernel Low-Latency Tuning:** Automatically tunes `net.inet.tcp.delayed_ack=0` for instant TCP control & RTSP responsiveness.
- **Process Priority Elevation:** Automatically grants streaming clients real-time Mach kernel scheduling priority (`nice -20`).
- **Installed App Auto-Detection:** Automatically scans for installed streaming clients (Moonlight, GeForce NOW, Parsec, Steam, etc.) without cluttering your UI with uninstalled apps.
- **Tailscale Active Connection Filter:** Suppresses idle `IPNExtension` background processes so Tailscale only triggers optimization during an active mesh connection.
- **Full Native macOS App:**
  - Visible in the macOS Dock and App Switcher.
  - Native macOS Application Menu Bar (JitterKill, File, Optimization, Window, Help) with keyboard shortcuts.
  - Companion menu bar status icon with real-time popover.
  - Liquid Glass dashboard with real-time jitter, packet rate, and interface monitoring.
- **Comprehensive DNS & Game Server Benchmarking:**
  - 12 Global Public DNS Resolvers (Cloudflare, Google, Quad9, OpenDNS, AdGuard, CleanBrowsing).
  - Game APIs (Valve Steam, Battle.net, GeForce NOW Routing API).
  - 64+ GeForce NOW Edge Server clusters across Europe, North America, and Asia.
  - Instant search, category filters, and custom host management with one-click deletion.
- **Zero Sudo Prompts via Dedicated LaunchDaemon:** Controlled seamlessly over IPC (`/tmp/jitterkill.control`).

---

## 📋 Requirements

* **macOS 14+** (Sonoma, Sequoia, or newer)
* **Architecture:** Apple Silicon (`arm64`) or Intel (`x86_64`)

---

## 🚀 Installation

1. **Download the DMG for your Mac's architecture** from [GitHub Releases](https://github.com/psychostark/JitterKill/releases):
   - **Apple Silicon:** `JitterKill-v1.0-arm64.dmg`
   - **Intel:** `JitterKill-v1.0-x86_64.dmg`
   - **Universal:** `JitterKill-v1.0-universal.dmg` *(works on any Mac)*
2. Double-click the DMG and drag **JitterKill.app** to your **Applications** folder shortcut.
3. Open **JitterKill** from Applications.
4. Click **"Install Helper Service"** in the app (one-time prompt) to enable zero-password background optimization.

---

### ⚠️ Troubleshooting: "App is Damaged / Corrupted and can't be opened"

Because JitterKill is distributed outside the Mac App Store with an ad-hoc signature, macOS Gatekeeper may quarantine downloaded files and display one of the following prompts:
- *"JitterKill is damaged and can’t be opened. You should move it to the Bin / Trash."*
- *"Apple cannot check it for malicious software."*

**The Fix:**
Simply open your **Terminal** app and run:

```bash
chmod +x /Applications/JitterKill.app/Contents/MacOS/JitterKill
xattr -cr /Applications/JitterKill.app
```

> [!TIP]
> **Why does this happen?**
> macOS Gatekeeper attaches an extended quarantine attribute (`com.apple.quarantine`) to files downloaded from web browsers and sometimes strips the execute bit (`+x`) from the application binary. Running `chmod +x` restores the execution permissions and `xattr -cr` clears Gatekeeper's quarantine flag, allowing JitterKill to launch immediately without any warnings.
>
> If prompted with *"Apple cannot check it for malicious software"*, you can also right-click (Control-click) **JitterKill.app** in Finder, select **Open**, and click **Open** in the confirmation dialog (or navigate to **System Settings > Privacy & Security** and click **"Open Anyway"**).

---

### 2. Launch Native App
Launch **JitterKill** from Applications, Spotlight, or Terminal:

```bash
open /Applications/JitterKill.app
# Or via CLI:
jitterkill app
```

### 3. CLI Controls
JitterKill comes with a CLI tool `/usr/local/bin/jitterkill`:

```bash
jitterkill status   # View live interface status, active stream, TCP ACK state
jitterkill apps     # List configured streaming apps and current running status
jitterkill auto     # Restore auto-detection (optimizes when streaming apps launch)
jitterkill on       # Force lockdown ON immediately
jitterkill off      # Force lockdown OFF (restores standard macOS defaults)
jitterkill app      # Open native macOS Dashboard
```

---

## ⚙️ How It Works

```
┌─────────────────────────────────────────────────────────────┐
│                       JitterKill.app                        │
│   (Dock + Native Menu Bar + Liquid Glass Dashboard + Popover)│
└──────────────────────────────┬──────────────────────────────┘
                               │ IPC (/tmp/jitterkill.control)
┌──────────────────────────────▼──────────────────────────────┐
│        LaunchDaemon Helper (/usr/local/bin/jitterkill-helper)│
│                     (Runs as Root)                          │
├─────────────────────────────────────────────────────────────┤
│  • Monitors running streaming apps (Moonlight, GFN, etc.)   │
│  • Locks down awdl0, llw0, nan0 during active sessions       │
│  • Silences AirDrop, Handoff, Universal Control, Location    │
│  • Enforces net.inet.tcp.delayed_ack = 0                    │
│  • Elevates process scheduling priority to -20              │
│  • Automatically restores defaults when apps close          │
└─────────────────────────────────────────────────────────────┘
```

---

## 💻 Windows Host Setup

If you use Windows Mobile Hotspot or Wi-Fi on your host PC:

1. Copy the `windows-host/` folder to your PC.
2. Before gaming: Right-click `disable_wlan_scan.bat` and select **Run as administrator**.
3. When finished gaming: Right-click `enable_wlan_scan.bat` and select **Run as administrator**.

---

## 🌐 Tailscale Streaming Tips

* **Direct P2P vs DERP:** JitterKill detects your Tailscale routing state. If your connection is routed through a DERP relay, JitterKill alerts you. Forward UDP port `41641` on your router to enable direct peer-to-peer connection.
* **Frame Pacing:** In Moonlight settings, enable "Frame Pacing: Smooth Video" and align your stream bitrate with your network connection.
