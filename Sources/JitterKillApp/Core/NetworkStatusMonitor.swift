// NetworkStatusMonitor.swift — Real-time network interface & streaming process state
// Pure Swift + lightweight background CLI probes. Non-blocking async updates.

import Foundation
import Combine
import AppKit

// MARK: - Interface Model

struct InterfaceState: Identifiable, Sendable {
    var id: String { name }
    let name: String
    let isUp: Bool
    let displayName: String
    let purpose: String
}

// MARK: - Streaming Mode

enum StreamingMode: Equatable, Sendable {
    case unknown
    case localLAN(gateway: String)
    case windowsHotspot(gateway: String)
    case tailscaleDirect(peerIP: String)
    case tailscaleDERP(region: String)

    var displayName: String {
        switch self {
        case .unknown:
            return "Detecting Mode…"
        case .localLAN(let gw):
            return "Local Wi-Fi / LAN (\(gw))"
        case .windowsHotspot(let gw):
            return "Windows Hotspot (\(gw))"
        case .tailscaleDirect(let ip):
            return "Tailscale Direct P2P (\(ip))"
        case .tailscaleDERP(let region):
            return "Tailscale DERP Relay (\(region))"
        }
    }

    var badgeColor: String {
        switch self {
        case .unknown:            return "gray"
        case .localLAN:           return "blue"
        case .windowsHotspot:     return "green"
        case .tailscaleDirect:    return "green"
        case .tailscaleDERP:      return "orange"
        }
    }

    var isWarning: Bool {
        if case .tailscaleDERP = self { return true }
        return false
    }

    var systemImage: String {
        switch self {
        case .unknown:          return "questionmark.circle"
        case .localLAN:         return "wifi"
        case .windowsHotspot:   return "personalhotspot"
        case .tailscaleDirect:  return "shield.checkered"
        case .tailscaleDERP:    return "exclamationmark.shield"
        }
    }
}

// MARK: - Streaming Process

struct StreamingProcess: Identifiable, Sendable {
    var id: String { "\(name)-\(pid)" }
    let name: String
    let pid: Int32
    let isRealTimePriority: Bool
}

// MARK: - Background Shell Snapshot (Sendable, no actor isolation)

private struct NetworkSnapshot: Sendable {
    var awdl0: InterfaceState
    var llw0:  InterfaceState
    var nan0:  InterfaceState
    var delayedAck: Int
    var defaultGateway: String?
    var streamingMode: StreamingMode
    var detectedProcesses: [StreamingProcess]
    var pidsByAppId: [String: [Int32]]
    var triggerAppName: String?
}

// MARK: - Non-isolated shell helpers (run these in Task.detached)

private func shell(_ command: String) -> String {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/bin/bash")
    proc.arguments = ["-c", command]
    let pipe = Pipe()
    proc.standardOutput = pipe
    proc.standardError = Pipe()
    try? proc.run()
    proc.waitUntilExit()
    return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
}

private func queryInterfaceBG(_ name: String, displayName: String, purpose: String) -> InterfaceState {
    let flagResult = shell("ifconfig \(name) 2>/dev/null | head -1")
    let isUp = flagResult.contains("<UP,") || flagResult.contains(",UP,") || flagResult.contains(",UP>")
    return InterfaceState(name: name, isUp: isUp, displayName: displayName, purpose: purpose)
}

private func readDelayedAckBG() -> Int {
    let out = shell("sysctl -n net.inet.tcp.delayed_ack 2>/dev/null").trimmingCharacters(in: .whitespacesAndNewlines)
    return Int(out) ?? 3
}

private func readDefaultGatewayBG() -> String? {
    let out = shell("route -n get default 2>/dev/null | awk '/gateway:/{print $2}'").trimmingCharacters(in: .whitespacesAndNewlines)
    return out.isEmpty ? nil : out
}

private func detectStreamingModeBG(gateway: String?) -> StreamingMode {
    guard let gw = gateway else { return .unknown }

    let domain = shell("ipconfig getpacket en0 2>/dev/null | awk '/domain_name \\(string\\):/{print $3}'").trimmingCharacters(in: .whitespacesAndNewlines)
    if domain == "mshome.net" || gw.hasPrefix("192.168.137.") {
        return .windowsHotspot(gateway: gw)
    }

    let tsBin = "/Applications/Tailscale.app/Contents/MacOS/Tailscale"
    if FileManager.default.fileExists(atPath: tsBin) {
        let tsStatus = shell("\"\(tsBin)\" status 2>/dev/null")
        if !tsStatus.lowercased().contains("stopped") && !tsStatus.isEmpty {
            if tsStatus.lowercased().contains("relay") || tsStatus.lowercased().contains("derp") {
                let region = tsStatus.components(separatedBy: "via DERP(")
                    .dropFirst().first?.components(separatedBy: ")").first ?? "unknown"
                return .tailscaleDERP(region: region)
            } else {
                let peerIP = tsStatus.components(separatedBy: .whitespacesAndNewlines)
                    .first(where: { $0.contains(".") && !$0.hasPrefix("100.") && $0 != gw }) ?? gw
                return .tailscaleDirect(peerIP: peerIP)
            }
        }
    }

    return .localLAN(gateway: gw)
}

private func isTailscaleActiveConnection() -> Bool {
    let tsBin = "/Applications/Tailscale.app/Contents/MacOS/Tailscale"
    guard FileManager.default.fileExists(atPath: tsBin) else { return false }
    let tsStatus = shell("\"\(tsBin)\" status 2>/dev/null")
    if tsStatus.isEmpty || tsStatus.lowercased().contains("stopped") {
        return false
    }
    return true
}

private func detectProcessesBG(rules: [StreamingAppRule]) -> (procs: [StreamingProcess], pidsByAppId: [String: [Int32]], trigger: String?) {
    var found: [StreamingProcess] = []
    var pidsByApp: [String: [Int32]] = [:]
    var trigger: String? = nil

    let runningApps = NSWorkspace.shared.runningApplications
    let tailscaleActive = isTailscaleActiveConnection()

    for rule in rules {
        // Tailscale check: ONLY report running if there is an active VPN connection
        if rule.id == "tailscale" && !tailscaleActive {
            continue
        }

        var appPids: [Int32] = []

        // 1. Fast in-memory Cocoa check against running GUI apps (zero subshells spawned)
        for app in runningApps {
            let matchesBundle: Bool
            if let targetBundle = rule.bundleIdentifier, let appBundle = app.bundleIdentifier {
                matchesBundle = (targetBundle.caseInsensitiveCompare(appBundle) == .orderedSame)
            } else {
                matchesBundle = false
            }

            let appName = app.localizedName ?? ""
            let execName = app.executableURL?.lastPathComponent ?? ""

            let matchesPattern = rule.processPatterns.contains { pattern in
                appName.caseInsensitiveCompare(pattern) == .orderedSame ||
                execName.caseInsensitiveCompare(pattern) == .orderedSame
            }

            if matchesBundle || matchesPattern {
                let pid = app.processIdentifier
                if pid > 0 && !appPids.contains(pid) {
                    appPids.append(pid)
                }
            }
        }

        // 2. Fallback for non-GUI command line daemons (e.g. sunshine, tailscaled)
        if appPids.isEmpty {
            for pattern in rule.processPatterns {
                if (pattern == "tailscaled" || pattern == "IPNExtension" || pattern == "Tailscale") && !tailscaleActive {
                    continue
                }

                let out = shell("pgrep -x \"\(pattern)\" 2>/dev/null").trimmingCharacters(in: .whitespacesAndNewlines)
                for line in out.components(separatedBy: .newlines) {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if let pid = Int32(trimmed), !appPids.contains(pid) {
                        let comm = shell("ps -p \(pid) -o comm= 2>/dev/null").trimmingCharacters(in: .whitespacesAndNewlines)
                        if !comm.hasPrefix("/System/Library") && !comm.hasPrefix("/usr/libexec") &&
                           !comm.hasSuffix("bash") && !comm.hasSuffix("zsh") && !comm.hasSuffix("sh") &&
                           !comm.contains("python") && !comm.contains("pgrep") && !comm.contains("grep") {
                            appPids.append(pid)
                        }
                    }
                }
            }
        }

        for pid in appPids {
            let nice = shell("ps -o nice= -p \(pid) 2>/dev/null").trimmingCharacters(in: .whitespacesAndNewlines)
            let isRT = Int(nice).map { $0 <= -10 } ?? false
            found.append(StreamingProcess(name: rule.name, pid: pid, isRealTimePriority: isRT))
        }

        if !appPids.isEmpty {
            pidsByApp[rule.id] = appPids
            if trigger == nil && rule.autoActivate {
                trigger = rule.name
            }
        }
    }

    return (found, pidsByApp, trigger)
}

/// Run all shell probes in a single background task — returns a snapshot.
private func captureNetworkSnapshot(rules: [StreamingAppRule]) -> NetworkSnapshot {
    let awdl = queryInterfaceBG("awdl0", displayName: "AWDL",          purpose: "AirDrop / Bonjour")
    let llw  = queryInterfaceBG("llw0",  displayName: "LLW (Skywalk)", purpose: "Low-Latency Wi-Fi")
    let nan  = queryInterfaceBG("nan0",  displayName: "NAN",           purpose: "Wi-Fi Aware")
    let ack  = readDelayedAckBG()
    let gw   = readDefaultGatewayBG()
    let mode = detectStreamingModeBG(gateway: gw)
    let (procs, pidsByApp, trigger) = detectProcessesBG(rules: rules)

    return NetworkSnapshot(
        awdl0: awdl, llw0: llw, nan0: nan,
        delayedAck: ack, defaultGateway: gw,
        streamingMode: mode, detectedProcesses: procs,
        pidsByAppId: pidsByApp, triggerAppName: trigger
    )
}

// MARK: - Monitor

@MainActor
final class NetworkStatusMonitor: ObservableObject {
    static let shared = NetworkStatusMonitor()

    @Published private(set) var awdl0State: InterfaceState = .init(name: "awdl0", isUp: true, displayName: "AWDL", purpose: "AirDrop / Bonjour")
    @Published private(set) var llw0State:  InterfaceState = .init(name: "llw0",  isUp: true, displayName: "LLW (Skywalk)", purpose: "Low-Latency Wi-Fi")
    @Published private(set) var nan0State:  InterfaceState = .init(name: "nan0",  isUp: false, displayName: "NAN", purpose: "Wi-Fi Aware")
    @Published private(set) var delayedAck: Int = 3
    @Published private(set) var streamingMode: StreamingMode = .unknown
    @Published private(set) var defaultGateway: String? = nil
    @Published private(set) var detectedProcesses: [StreamingProcess] = []
    @Published private(set) var moonlightRunning: Bool = false
    @Published private(set) var activeStreamingAppNames: [String] = []
    @Published private(set) var isAnyStreamingAppRunning: Bool = false
    @Published private(set) var triggerAppName: String? = nil

    private var pollTask: Task<Void, Never>?

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task(priority: .background) { [weak self] in
            await self?.pollLoop()
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// Async refresh — shell work runs in a detached background task, never blocks main thread.
    func refresh() async {
        let rules = StreamingAppManager.shared.apps
        let snapshot = await Task.detached(priority: .utility) {
            captureNetworkSnapshot(rules: rules)
        }.value

        // Apply to @Published on main actor
        self.awdl0State        = snapshot.awdl0
        self.llw0State         = snapshot.llw0
        self.nan0State         = snapshot.nan0
        self.delayedAck        = snapshot.delayedAck
        self.defaultGateway    = snapshot.defaultGateway
        self.streamingMode     = snapshot.streamingMode
        self.detectedProcesses = snapshot.detectedProcesses
        self.triggerAppName    = snapshot.triggerAppName

        let appNames = Array(Set(snapshot.detectedProcesses.map { $0.name })).sorted()
        self.activeStreamingAppNames   = appNames
        self.isAnyStreamingAppRunning  = !appNames.isEmpty
        self.moonlightRunning          = appNames.contains { $0.localizedCaseInsensitiveContains("moonlight") }

        StreamingAppManager.shared.updateRunningState(
            pidsByAppId: snapshot.pidsByAppId,
            triggerApp: snapshot.triggerAppName
        )
    }

    private func pollLoop() async {
        while !Task.isCancelled {
            await refresh()
            try? await Task.sleep(for: .seconds(2))
        }
    }
}
