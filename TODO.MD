# JitterKill Task & Roadmap

## Completed (v1.0)
- [x] **Branded Logo & Icon Integration:** Embedded official JitterKill logo into Dock icon, Application Menu Bar, Liquid Glass Dashboard sidebar, Menubar Popover header, and Settings About tab.
- [x] **Dynamic Menu Bar Icon:** Added reactive switching between `mono_guard` (locked down/activated) and `mono_unguard` (standby/deactivated) as 18×18 pt macOS template images.
- [x] **Transparent Background Rendering:** Clean alpha channel for logo squircle with no white background artifacts across dark/light macOS modes.
- [x] **Window Launch Lifecycle:** Only the native Dashboard window opens on app launch. The Settings window opens on-demand (`Cmd + ,` or menu item).
- [x] **DMG Volume Branding:** Configured DMG volume name to `JitterKill` with embedded volume icon; release file named `JitterKill-v1.0.dmg`.
- [x] **Triple Interface Lockdown:** Simultaneous downing of `awdl0`, `llw0` (Skywalk), and `nan0`.
- [x] **Low-Latency Kernel Tuning:** Automated `net.inet.tcp.delayed_ack=0` and Mach scheduling `nice -20`.
- [x] **Installed Streaming Apps Scanner:** Auto-detection for Moonlight, GeForce NOW, Steam, Parsec, and active Tailscale mesh streams.
- [x] **Rootless Helper LaunchDaemon:** Zero sudo authorization prompts via IPC socket `/tmp/jitterkill.control`.

---

## Next Steps / Future Roadmap
- [ ] Auto-updater / Sparkle framework integration for automatic GitHub release updates.
- [ ] Customizable interface rules for multi-adapter setups (e.g. Wi-Fi + Thunderbolt Ethernet).
- [ ] Menubar ping tooltip / mini live latency counter option.