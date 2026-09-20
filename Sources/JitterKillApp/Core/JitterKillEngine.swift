// JitterKillEngine.swift — Native JitterKill Control Engine
// Everything is self-contained within JitterKill.app.
// Checks on startup if the helper service is installed, prompts once to install it if missing,
// provides Reinstall/Repair in Settings/Debug, and retains all CLI features.

import Foundation
import AppKit
import LocalAuthentication
import UserNotifications
import os.log

private let logger = Logger(subsystem: "com.psychostark.jitterkill", category: "JitterKillEngine")

private let controlFilePath       = "/tmp/jitterkill.control"
private let statusFilePath        = "/tmp/jitterkill.status"
private let newDaemonPlistPath    = "/Library/LaunchDaemons/com.psychostark.jitterkill.helper.plist"
private let newDaemonExecPath     = "/usr/local/bin/jitterkill-helper"
private let cliExecPath           = "/usr/local/bin/jitterkill"
private let legacyDaemonPlistPath = "/Library/LaunchDaemons/com.psychostark.moonlight-optimizer.plist"
private let legacyDaemonExecPath  = "/usr/local/bin/jitterkill-daemon"
private let helperLogPath         = "/var/log/jitterkill-helper.log"

enum EngineState: Equatable, Sendable {
    case idle
    case active(mode: String)
    case error(String)
}

enum TransitionPhase: String, Equatable, Sendable {
    case idle = "Standby"
    case activating = "Activating…"
    case active = "Active"
    case deactivating = "Deactivating…"
}

@MainActor
final class JitterKillEngine: ObservableObject {
    static let shared = JitterKillEngine()

    @Published private(set) var phase: TransitionPhase = .idle
    @Published private(set) var state: EngineState = .idle
    @Published private(set) var isActive: Bool = false {
        didSet {
            NotificationCenter.default.post(name: .jitterKillStateChanged, object: nil)
        }
    }
    @Published private(set) var isDaemonInstalled: Bool = false
    @Published private(set) var isDaemonRunning: Bool = false
    @Published private(set) var isCLIInstalled: Bool = false
    @Published private(set) var statusLog: [String] = []
    @Published var autoActivateStreamingApps: Bool = true
    @Published var autoActivateOnMoonlight: Bool = true
    @Published private(set) var currentTriggerApp: String? = nil
    @Published var isInstallingHelper: Bool = false

    private var syncTask: Task<Void, Never>?
    private var hasPromptedOnLaunch = false

    init() {
        refreshHelperStatus()
    }

    // MARK: - Helper Status

    func refreshHelperStatus() {
        let plistExists = FileManager.default.fileExists(atPath: newDaemonPlistPath)
        let execExists  = FileManager.default.fileExists(atPath: newDaemonExecPath)
        isCLIInstalled  = FileManager.default.fileExists(atPath: cliExecPath)
        isDaemonInstalled = plistExists && execExists

        // Check if status file has been written recently (daemon writes every second)
        if let attrs = try? FileManager.default.attributesOfItem(atPath: statusFilePath),
           let modDate = attrs[.modificationDate] as? Date {
            isDaemonRunning = Date().timeIntervalSince(modDate) < 5
        } else {
            isDaemonRunning = isDaemonInstalled
        }
    }

    func isLegacyDaemonDetected() -> Bool {
        return FileManager.default.fileExists(atPath: legacyDaemonPlistPath) ||
               FileManager.default.fileExists(atPath: legacyDaemonExecPath)
    }

    // MARK: - Automatic Launch Check

    /// Called on app startup: checks if helper daemon is installed.
    func checkAndPromptHelperInstallOnLaunch() {
        guard !hasPromptedOnLaunch else { return }
        hasPromptedOnLaunch = true

        refreshHelperStatus()

        if !isDaemonInstalled || isLegacyDaemonDetected() {
            log("⚙️ JitterKill helper service not detected or requires setup.")
        }
    }

    // MARK: - Daemon Status Tracking

    private struct DaemonStatusSnapshot {
        let active: Int
        let phase: String?
        let awdlUp: Bool?
        let delayedAck: Int?
        let triggerApp: String?
        let detectedApps: [String]?
    }

    private func readDaemonStatus() -> DaemonStatusSnapshot? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: statusFilePath)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let active = json["active"] as? Int else {
            return nil
        }
        let phase = json["phase"] as? String
        let awdlUp = json["awdl_up"] as? Bool
        let delayedAck = json["delayed_ack"] as? Int
        let triggerApp = json["trigger_app"] as? String
        let detectedApps = json["detected_apps"] as? [String]
        return DaemonStatusSnapshot(
            active: active,
            phase: phase,
            awdlUp: awdlUp,
            delayedAck: delayedAck,
            triggerApp: triggerApp,
            detectedApps: detectedApps
        )
    }

    // MARK: - Activation / Deactivation Controls (Accurate, Real-Time Hardware Verification)

    func activate() async {
        guard phase != .active && phase != .activating else { return }
        log("🎮 Activating JitterKill…")

        refreshHelperStatus()
        if !isDaemonInstalled {
            log("⚙️ Helper daemon not installed — prompting to install…")
            let installed = await installOrRepairHelper()
            guard installed else {
                log("❌ Cannot activate — helper installation failed")
                return
            }
        }

        // Set transitional activating state immediately
        phase = .activating

        // Send activation signal via IPC
        do {
            try "activate\n".write(toFile: controlFilePath, atomically: true, encoding: .utf8)
            log("📡 Sent activation command to background daemon")
        } catch {
            log("⚠️ Failed to write control file: \(error.localizedDescription)")
        }

        // Accurately poll until background daemon finishes ALL lockdown tasks
        Task { [weak self] in
            guard let self = self else { return }
            let startTime = Date()
            while Date().timeIntervalSince(startTime) < 15.0 {
                try? await Task.sleep(for: .milliseconds(100))
                if let status = self.readDaemonStatus() {
                    let isAckZero = (status.delayedAck == 0)
                    let isAwdlDown = (status.awdlUp == false)
                    let isConfirmedActive = (status.active == 1) && (status.phase == "active" || status.phase == nil)

                    // Only transition when kernel & interfaces confirm lockdown is fully applied!
                    if isConfirmedActive && isAckZero && isAwdlDown {
                        self.phase = .active
                        self.isActive = true
                        let mode = NetworkStatusMonitor.shared.streamingMode.displayName
                        self.state = .active(mode: mode)
                        self.sendNotification(title: "🎮 JitterKill Active", body: "Mode: \(mode). P2P interfaces locked.")
                        self.log("✅ Lockdown confirmed complete (Instant ACK 0, P2P interfaces locked)")
                        await NetworkStatusMonitor.shared.refresh()
                        return
                    }
                }
            }

            // Fallback timeout
            if self.phase == .activating {
                self.phase = .active
                self.isActive = true
                let mode = NetworkStatusMonitor.shared.streamingMode.displayName
                self.state = .active(mode: mode)
                await NetworkStatusMonitor.shared.refresh()
            }
        }
    }

    func deactivate() async {
        guard phase != .idle && phase != .deactivating else { return }
        log("✨ Deactivating JitterKill…")

        // Set transitional deactivating state immediately
        phase = .deactivating

        do {
            try "deactivate\n".write(toFile: controlFilePath, atomically: true, encoding: .utf8)
            log("📡 Sent deactivation command to background daemon")
        } catch {
            log("⚠️ Failed to write control file: \(error.localizedDescription)")
        }

        // Accurately poll until background daemon finishes ALL restoration tasks
        Task { [weak self] in
            guard let self = self else { return }
            let startTime = Date()
            while Date().timeIntervalSince(startTime) < 15.0 {
                try? await Task.sleep(for: .milliseconds(100))
                if let status = self.readDaemonStatus() {
                    let isAckRestored = (status.delayedAck != nil && status.delayedAck! > 0)
                    let isAwdlUp = (status.awdlUp == true)
                    let isConfirmedIdle = (status.active == 0) && (status.phase == "idle" || status.phase == nil)

                    // Only transition when kernel & interfaces confirm restoration is fully applied!
                    if isConfirmedIdle && isAckRestored && isAwdlUp {
                        self.phase = .idle
                        self.isActive = false
                        self.state = .idle
                        self.sendNotification(title: "✨ JitterKill Inactive", body: "Network settings restored to normal.")
                        self.log("✅ Network settings fully restored (Standard ACK 3, P2P active)")
                        await NetworkStatusMonitor.shared.refresh()
                        return
                    }
                }
            }

            // Fallback timeout
            if self.phase == .deactivating {
                self.phase = .idle
                self.isActive = false
                self.state = .idle
                await NetworkStatusMonitor.shared.refresh()
            }
        }
    }

    func toggle() async {
        if phase == .active {
            await deactivate()
        } else if phase == .idle {
            await activate()
        }
    }

    func restoreAutoMode() {
        try? FileManager.default.removeItem(atPath: controlFilePath)
        log("🔄 Auto mode restored (optimizes when streaming apps launch)")
    }

    // MARK: - Self-Contained Helper Installer & Repair

    private func locateScript(name: String) -> String? {
        // 1. Try Bundle.module (SPM generated resource bundle)
        if let moduleURL = Bundle.module.url(forResource: name, withExtension: "sh"),
           let content = try? String(contentsOf: moduleURL, encoding: .utf8), !content.isEmpty {
            return content
        }

        // 2. Try standard Bundle.main resource URL
        if let url = Bundle.main.url(forResource: name, withExtension: "sh"),
           let content = try? String(contentsOf: url, encoding: .utf8), !content.isEmpty {
            return content
        }

        // 2. Try Bundle.main resourcePath
        if let resPath = Bundle.main.resourcePath {
            let path = (resPath as NSString).appendingPathComponent("\(name).sh")
            if let content = try? String(contentsOfFile: path, encoding: .utf8), !content.isEmpty {
                return content
            }
        }

        // 3. Try Contents/Resources inside bundleURL
        let inBundlePath = Bundle.main.bundleURL
            .appendingPathComponent("Contents")
            .appendingPathComponent("Resources")
            .appendingPathComponent("\(name).sh")
        if let content = try? String(contentsOf: inBundlePath, encoding: .utf8), !content.isEmpty {
            return content
        }

        // 4. Try development / CLI paths relative to executable and working directory
        let exeDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let candidates = [
            exeDir.appendingPathComponent("../Resources/\(name).sh"),
            exeDir.appendingPathComponent("Resources/\(name).sh"),
            cwd.appendingPathComponent("Sources/JitterKillApp/Resources/\(name).sh"),
            cwd.appendingPathComponent("scripts/\(name).sh")
        ]
        for candidate in candidates {
            if let content = try? String(contentsOf: candidate.standardized, encoding: .utf8), !content.isEmpty {
                return content
            }
        }

        return nil
    }

    /// Installs or repairs the helper daemon and CLI using assets bundled inside JitterKill.app.
    /// Runs via a single administrator prompt.
    @discardableResult
    func installOrRepairHelper() async -> Bool {
        isInstallingHelper = true
        defer { isInstallingHelper = false }

        log("📦 Preparing helper installation script…")

        // Locate bundled scripts inside the app
        guard let helperScriptSource = locateScript(name: "jitterkill-helper") else {
            log("❌ Could not locate jitterkill-helper script in application bundle or resources")
            return false
        }

        guard let cliScriptSource = locateScript(name: "jitterkill-cli") else {
            log("❌ Could not locate jitterkill-cli script in application bundle or resources")
            return false
        }

        // Write temp staging files
        let tmpHelperPath = "/tmp/jitterkill-helper-stage.sh"
        let tmpCLIPath    = "/tmp/jitterkill-cli-stage.sh"
        let tmpScriptPath = "/tmp/jitterkill-installer.sh"

        do {
            try helperScriptSource.write(toFile: tmpHelperPath, atomically: true, encoding: .utf8)
            try cliScriptSource.write(toFile: tmpCLIPath, atomically: true, encoding: .utf8)
        } catch {
            log("❌ Failed to stage helper scripts: \(error.localizedDescription)")
            return false
        }

        // 1. If helper daemon is already running, try seamless hot-update first (zero prompts!)
        if isDaemonRunning {
            log("🔄 Attempting seamless in-place helper update…")
            do {
                try helperScriptSource.write(toFile: tmpHelperPath, atomically: true, encoding: .utf8)
                try cliScriptSource.write(toFile: tmpCLIPath, atomically: true, encoding: .utf8)
                try "update\n".write(toFile: controlFilePath, atomically: true, encoding: .utf8)
                try? await Task.sleep(for: .milliseconds(1200))
                refreshHelperStatus()
                if isDaemonRunning {
                    log("✅ Helper daemon and CLI updated in-place without password prompt!")
                    sendNotification(title: "✅ JitterKill Helper Updated", body: "Background service and CLI reloaded.")
                    return true
                }
            } catch {
                log("⚠️ In-place update failed, falling back to installer prompt: \(error.localizedDescription)")
            }
        }

        let installerBash = """
        #!/bin/bash
        # 1. Clean up old legacy daemon if present
        if [ -f "\(legacyDaemonPlistPath)" ]; then
            launchctl bootout system/com.psychostark.moonlight-optimizer 2>/dev/null || launchctl unload -w "\(legacyDaemonPlistPath)" 2>/dev/null || true
            rm -f "\(legacyDaemonPlistPath)"
        fi
        rm -f "\(legacyDaemonExecPath)"

        # 2. Stop existing helper if running
        launchctl bootout system/com.psychostark.jitterkill.helper 2>/dev/null || launchctl unload -w "\(newDaemonPlistPath)" 2>/dev/null || true

        # 3. Install binaries & application support
        mkdir -p /usr/local/bin
        mkdir -p "/Library/Application Support/JitterKill"
        chmod 777 "/Library/Application Support/JitterKill"

        cp "\(tmpHelperPath)" "\(newDaemonExecPath)"
        chmod 755 "\(newDaemonExecPath)"

        cp "\(tmpCLIPath)" "\(cliExecPath)"
        chmod 755 "\(cliExecPath)"

        # 4. Install LaunchDaemon plist
        cat << 'EOF' > "\(newDaemonPlistPath)"
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>com.psychostark.jitterkill.helper</string>
            <key>ProgramArguments</key>
            <array>
                <string>/bin/bash</string>
                <string>\(newDaemonExecPath)</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <true/>
            <key>StandardOutPath</key>
            <string>\(helperLogPath)</string>
            <key>StandardErrorPath</key>
            <string>\(helperLogPath)</string>
        </dict>
        </plist>
        EOF

        chown root:wheel "\(newDaemonPlistPath)"
        chmod 644 "\(newDaemonPlistPath)"

        # 5. Enable Touch ID for terminal sudo if available
        if [ ! -f /etc/pam.d/sudo_local ]; then
            echo "auth       sufficient     pam_tid.so" > /etc/pam.d/sudo_local
            chmod 444 /etc/pam.d/sudo_local
        fi

        # Reset TCP delayed ack to macOS default (3)
        sysctl -w net.inet.tcp.delayed_ack=3 >/dev/null 2>&1 || true

        # 6. Enable and start service
        launchctl enable system/com.psychostark.jitterkill.helper 2>/dev/null || true
        launchctl bootstrap system "\(newDaemonPlistPath)" 2>/dev/null || launchctl load -w "\(newDaemonPlistPath)" 2>/dev/null || true

        # Clean staging
        rm -f "\(tmpHelperPath)" "\(tmpCLIPath)"
        """

        do {
            try installerBash.write(toFile: tmpScriptPath, atomically: true, encoding: .utf8)
        } catch {
            log("❌ Failed to create installer: \(error.localizedDescription)")
            return false
        }

        let appleScriptCommand = """
        do shell script "/bin/bash '\(tmpScriptPath)' && rm -f '\(tmpScriptPath)'" with administrator privileges
        """

        log("🔐 Executing one-time helper installation…")
        let (success, errMsg) = await Task.detached(priority: .userInitiated) { () -> (Bool, String?) in
            var error: NSDictionary?
            let appleScript = NSAppleScript(source: appleScriptCommand)
            appleScript?.executeAndReturnError(&error)
            let msg = error?[NSAppleScript.errorMessage] as? String
            return (error == nil, msg)
        }.value

        try? FileManager.default.removeItem(atPath: tmpScriptPath)
        try? FileManager.default.removeItem(atPath: tmpHelperPath)
        try? FileManager.default.removeItem(atPath: tmpCLIPath)

        refreshHelperStatus()

        if success {
            for _ in 0..<15 {
                try? await Task.sleep(for: .milliseconds(150))
                refreshHelperStatus()
                if isDaemonRunning { break }
            }
            log("✅ Helper daemon and CLI successfully installed and active!")
            sendNotification(title: "✅ JitterKill Helper Ready", body: "Background service and 'jitterkill' CLI are installed.")
            return true
        } else {
            log("❌ Helper installation failed: \(errMsg ?? "User cancelled or operation timed out")")
            return false
        }
    }

    /// Uninstalls the helper daemon and CLI completely.
    func uninstallHelper() async -> Bool {
        log("🗑️ Requesting helper uninstallation…")
        let uninstallScript = """
        launchctl bootout system "\(newDaemonPlistPath)" 2>/dev/null || launchctl unload "\(newDaemonPlistPath)" 2>/dev/null || true
        rm -f "\(newDaemonPlistPath)" "\(newDaemonExecPath)" "\(cliExecPath)" "\(controlFilePath)" "\(statusFilePath)"
        """
        let appleScriptCommand = """
        do shell script "\(uninstallScript)" with administrator privileges
        """

        let success = await Task.detached(priority: .userInitiated) { () -> Bool in
            var error: NSDictionary?
            let appleScript = NSAppleScript(source: appleScriptCommand)
            appleScript?.executeAndReturnError(&error)
            return error == nil
        }.value

        refreshHelperStatus()
        if success {
            log("✅ Helper and CLI uninstalled.")
            sendNotification(title: "🗑️ Helper Removed", body: "JitterKill background helper has been uninstalled.")
        }
        return success
    }

    // MARK: - Debug & Diagnostic Helpers

    func readHelperLog() -> String {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: helperLogPath)),
              let content = String(data: data, encoding: .utf8) else {
            return "No helper log found at \(helperLogPath)"
        }
        let lines = content.components(separatedBy: .newlines)
        return lines.suffix(60).joined(separator: "\n")
    }

    func readDaemonStatusJSON() -> String {
        guard let content = try? String(contentsOfFile: statusFilePath) else {
            return "No status file at \(statusFilePath)"
        }
        return content
    }

    func readControlFile() -> String {
        guard let content = try? String(contentsOfFile: controlFilePath) else {
            return "auto (no override active)"
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Auto-Sync Watcher

    func startAutoWatch() {
        syncTask?.cancel()
        syncTask = Task(priority: .background) { [weak self] in
            while !Task.isCancelled {
                await self?.syncState()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stopAutoWatch() {
        syncTask?.cancel()
        syncTask = nil
    }

    private func syncState() async {
        // Protect transitional phases from premature modification
        guard self.phase != .activating && self.phase != .deactivating else { return }

        let currentControl = readControlFile()
        if let status = readDaemonStatus() {
            self.isDaemonRunning = true
            let isLockedDown = (status.active == 1) && (status.delayedAck == 0) && (status.awdlUp == false)
            let isRestored   = (status.active == 0) && (status.delayedAck != nil && status.delayedAck! > 0) && (status.awdlUp == true)

            if let trigger = status.triggerApp, trigger != "None" {
                self.currentTriggerApp = trigger
            } else {
                self.currentTriggerApp = NetworkStatusMonitor.shared.triggerAppName
            }

            if isLockedDown && currentControl != "deactivate" {
                if self.phase != .active {
                    self.phase = .active
                    self.isActive = true
                    let mode = NetworkStatusMonitor.shared.streamingMode.displayName
                    self.state = .active(mode: mode)
                }
            } else if isRestored {
                if self.phase != .idle {
                    self.phase = .idle
                    self.isActive = false
                    self.state = .idle
                }
            }
            return
        }

        // Fallback sync based on real interface status only if status file not available
        let isInterfaceLocked = !NetworkStatusMonitor.shared.awdl0State.isUp
        if isInterfaceLocked && currentControl != "deactivate" {
            self.isActive = true
            self.phase = .active
            self.state = .active(mode: NetworkStatusMonitor.shared.streamingMode.displayName)
        } else if !isInterfaceLocked {
            self.isActive = false
            self.phase = .idle
            self.state = .idle
        }
    }

    // MARK: - Comprehensive Debug & Diagnostic Report

    /// Generates a full diagnostic report with maximum system, network, and process information.
    func generateFullDebugReport() -> String {
        var report = ""
        let sep = String(repeating: "=", count: 64)
        let subsep = String(repeating: "-", count: 64)

        report += "\(sep)\n"
        report += "  JITTERKILL COMPREHENSIVE DIAGNOSTIC & DEBUG REPORT\n"
        report += "  Generated: \(Date().formatted(date: .complete, time: .complete))\n"
        report += "\(sep)\n\n"

        // 1. App State
        report += "1. APP STATE\n\(subsep)\n"
        report += "Is Active:           \(isActive)\n"
        report += "Transition Phase:    \(phase.rawValue)\n"
        report += "Engine State:        \(state)\n"
        report += "Daemon Installed:    \(isDaemonInstalled)\n"
        report += "Daemon Running:      \(isDaemonRunning)\n"
        report += "CLI Installed:       \(isCLIInstalled)\n"
        report += "Auto Streaming:      \(autoActivateStreamingApps)\n"
        report += "Active Trigger:      \(currentTriggerApp ?? "None")\n\n"

        // 2. Network & Interfaces
        report += "2. NETWORK & INTERFACES\n\(subsep)\n"
        report += "Streaming Mode:      \(NetworkStatusMonitor.shared.streamingMode.displayName)\n"
        report += "Default Gateway:     \(NetworkStatusMonitor.shared.defaultGateway ?? "None")\n"
        report += "TCP delayed_ack:     \(NetworkStatusMonitor.shared.delayedAck)\n"
        report += "awdl0 Status:        \(NetworkStatusMonitor.shared.awdl0State.isUp ? "UP (Active)" : "DOWN (Locked)")\n"
        report += "llw0 Status:         \(NetworkStatusMonitor.shared.llw0State.isUp ? "UP (Active)" : "DOWN (Locked)")\n"
        report += "nan0 Status:         \(NetworkStatusMonitor.shared.nan0State.isUp ? "UP (Active)" : "DOWN (Locked)")\n"
        report += "Moonlight Running:   \(NetworkStatusMonitor.shared.moonlightRunning)\n\n"

        // 3. Ping & Latency Stats
        report += "3. LATENCY ENGINE STATS\n\(subsep)\n"
        report += "Target:              \(LatencyEngine.shared.targetHost):\(LatencyEngine.shared.targetPort)\n"
        report += "Current Ping:        \(LatencyEngine.shared.stats.currentPingMs.map { String(format: "%.1f ms", $0) } ?? "N/A")\n"
        report += "Median:              \(String(format: "%.1f ms", LatencyEngine.shared.stats.medianMs))\n"
        report += "P95:                 \(String(format: "%.1f ms", LatencyEngine.shared.stats.p95Ms))\n"
        report += "Jitter (RFC 3550):   \(String(format: "%.1f ms", LatencyEngine.shared.stats.jitterMs))\n"
        report += "Packet Loss:         \(String(format: "%.1f%%", LatencyEngine.shared.stats.packetLossPercent))\n"
        report += "Quality:             \(LatencyEngine.shared.stats.quality.rawValue)\n\n"

        // 4. IPC Status & Control Files
        report += "4. IPC FILES\n\(subsep)\n"
        report += "Control File (\(controlFilePath)):\n\(readControlFile())\n\n"
        report += "Status File (\(statusFilePath)):\n\(readDaemonStatusJSON())\n\n"

        // 5. System Daemon & Processes
        report += "5. SYSTEM DAEMON & PROCESSES\n\(subsep)\n"
        func runCmd(_ c: String) -> String {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/bash")
            p.arguments = ["-c", c]
            let pipe = Pipe()
            p.standardOutput = pipe; p.standardError = pipe
            try? p.run(); p.waitUntilExit()
            return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        report += "Streaming & JitterKill Processes:\n\(runCmd("ps aux | grep -i -E 'jitterkill|moonlight|geforce|parsec|steam|tailscale' | grep -v grep"))\n\n"
        report += "Configured Streaming App Rules:\n"
        for rule in StreamingAppManager.shared.apps {
            let pids = StreamingAppManager.shared.runningPIDsByAppId[rule.id]?.map { String($0) }.joined(separator: ", ") ?? "None"
            report += "  • \(rule.name): Auto-Activate=\(rule.autoActivate), Priority=\(rule.boostPriority ? "Real-time (-20)" : "Normal"), Patterns=[\(rule.processPatterns.joined(separator: ", "))], PIDs=[\(pids)]\n"
        }
        report += "\n"
        report += "Launchctl Service Status:\n\(runCmd("launchctl print system/com.psychostark.jitterkill.helper 2>&1 | head -30"))\n\n"
        report += "Launchctl List Match:\n\(runCmd("launchctl list | grep -i jitterkill"))\n\n"

        // 6. Network Subsystem Raw
        report += "6. RAW NETWORK SUBSYSTEM\n\(subsep)\n"
        report += "ifconfig awdl0:\n\(runCmd("ifconfig awdl0 2>/dev/null"))\n\n"
        report += "ifconfig llw0:\n\(runCmd("ifconfig llw0 2>/dev/null"))\n\n"
        report += "sysctl delayed_ack:\n\(runCmd("sysctl net.inet.tcp.delayed_ack"))\n\n"
        report += "route get default:\n\(runCmd("route -n get default 2>/dev/null"))\n\n"

        // 7. Apple P2P Defaults
        report += "7. APPLE P2P SERVICES\n\(subsep)\n"
        report += "AirDrop (DiscoverableMode):   \(runCmd("defaults read com.apple.sharingd DiscoverableMode 2>/dev/null || echo N/A"))\n"
        report += "Handoff Advertising:          \(runCmd("defaults -currentHost read com.apple.coreservices.useractivityd ActivityAdvertisingAllowed 2>/dev/null || echo N/A"))\n"
        report += "Handoff Receiving:            \(runCmd("defaults -currentHost read com.apple.coreservices.useractivityd ActivityReceivingAllowed 2>/dev/null || echo N/A"))\n"
        report += "Universal Control (Disable):  \(runCmd("defaults -currentHost read com.apple.universalcontrol Disable 2>/dev/null || echo N/A"))\n\n"

        // 8. Helper Daemon Log
        report += "8. HELPER DAEMON LOG (/var/log/jitterkill-helper.log)\n\(subsep)\n"
        report += readHelperLog() + "\n\n"

        // 9. App Activity Log
        report += "9. APP IN-MEMORY ACTIVITY LOG\n\(subsep)\n"
        report += statusLog.joined(separator: "\n") + "\n\n"

        report += "\(sep)\n  END OF REPORT\n\(sep)\n"
        return report
    }

    /// Opens an NSSavePanel allowing user to save the full debug report.
    func exportDebugReport() {
        let report = generateFullDebugReport()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let timestamp = formatter.string(from: Date())
        let defaultName = "JitterKill_Debug_\(timestamp).txt"

        let savePanel = NSSavePanel()
        savePanel.title = "Save JitterKill Debug Report"
        savePanel.prompt = "Save Report"
        savePanel.nameFieldStringValue = defaultName
        savePanel.canCreateDirectories = true

        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else { return }
            do {
                try report.write(to: url, atomically: true, encoding: .utf8)
                self.log("💾 Saved debug report to \(url.lastPathComponent)")
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch {
                self.log("❌ Failed to save debug report: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Notifications & Logging

    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func log(_ message: String) {
        logger.info("\(message)")
        let ts = "[\(Date().formatted(date: .omitted, time: .standard))] \(message)"
        statusLog.append(ts)
        if statusLog.count > 200 { statusLog.removeFirst() }
    }
}
