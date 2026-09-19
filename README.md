# 🎮 JitterKill

**High-Performance Low-Latency Game Streaming Optimizer for macOS & Windows**  
Specifically designed for Moonlight, Sunshine, and Tailscale game streaming.

Eliminates periodic ping spikes, micro-stutters, and audio dropouts caused by Apple Wireless Direct Link (`awdl0`, `llw0`, `nan0`), background discovery scans, and Windows WLAN AutoConfig.

---

## 🎯 What Problems JitterKill Solves

1. **The macOS AWDL & LLW Blind Spot:**
   - Most community tools (AWDLControl, Ping Warden, Moonlight built-in AWDL) only disable `awdl0`.
   - Modern macOS (Ventura, Sonoma, Sequoia) introduced `llw0` (Low-Latency WLAN / Skywalk) and `nan0` (Wi-Fi Aware). These remain active and continue hopping off-channel, causing 100–300 ms packet stalls.
   - **JitterKill locks down `awdl0`, `llw0`, and `nan0` simultaneously.**

2. **Background Wi-Fi & Discovery Scanners:**
   - Location Services, AirDrop discovery, Handoff, Universal Control, and AirPlay Receiver periodically trigger radio scans or multicast floods.
   - **JitterKill captures your initial settings, silences them during gameplay, and automatically restores them on exit.**

3. **Darwin Kernel TCP Latency:**
   - macOS defaults to `net.inet.tcp.delayed_ack: 3`, holding back TCP acknowledgments by up to 100 ms.
   - **JitterKill sets `delayed_ack=0` during stream sessions for instantaneous control response.**

4. **Background Process Jitter Freeze:**
   - Apps like **LocalSend** (LAN multicast discovery) and **Pock** (Touch Bar RSSI polling) flood your Wi-Fi card with requests.
   - **JitterKill non-destructively freezes them (`SIGSTOP`) and thaws them (`SIGCONT`) when you finish.**

5. **Real-time CPU Scheduling:**
   - Moonlight and the Tailscale WireGuard daemon are automatically elevated to `renice -20` (highest real-time priority).

6. **The Windows 60-Second Hotspot Scanning Bug:**
   - When hosting a Mobile Hotspot on Windows, the `WlanSvc` background scan freezes the hotspot every 60 seconds at an exact second (:31).
   - Helper scripts in `windows-host/` eliminate this host-side stall.

---

## 🚀 Quick Start (macOS)

### Option A: Automatic Background Daemon (Recommended)
Install JitterKill as a native macOS `LaunchDaemon`. It runs silently in the background at 0.0% CPU, auto-activates when you open Moonlight, and auto-restores when you quit:

```bash
stream-install
```
*(Or `sudo ./jitterkill.sh --install`)*

Check status anytime:
```bash
stream-status
```
*(Or `./jitterkill.sh --status`)*

Uninstall daemon anytime:
```bash
stream-uninstall
```

---

### Option B: Interactive Terminal Mode
Run JitterKill in a dedicated terminal window:

```bash
jitterkill
```
*(Or `stream-mode`, or `sudo ./jitterkill.sh`)*

Press `Ctrl + C` when you're done gaming to cleanly restore all settings.

---

## 💻 Windows Host Setup (Acer Nitro 5)

If you use Windows Mobile Hotspot or Wi-Fi on your host PC:

1. Copy the `windows-host/` folder to your PC.
2. Before gaming: Right-click `disable_wlan_scan.bat` and select **Run as administrator**.
3. When finished gaming: Right-click `enable_wlan_scan.bat` and select **Run as administrator**.

---

## 🌐 Tailscale Streaming Tips

* **Check for Direct P2P:** Run `tailscale ping <host-ip>`. If it says `via DERP(...)`, your stream will experience added latency. Enable UPnP on your router or forward UDP port `41641` to achieve a direct connection.
* **Moonlight Settings:** Set V-Sync to "Fast", Frame Pacing to "Smooth Video", and keep stream resolution/bitrate aligned with your display refresh rate.
