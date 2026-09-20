// DNSBenchmarkEngine.swift — Concurrent DNS/host benchmark engine
// Tests multiple candidate endpoints concurrently and ranks them by average latency.
// Provides "Auto-Detect Fastest" functionality, GeForce NOW edge servers, and custom host management.

import Foundation
import Network
import os.log

private let logger = Logger(subsystem: "com.psychostark.jitterkill", category: "DNSBenchmark")

// MARK: - Target Category

enum TargetCategory: String, Codable, CaseIterable, Sendable {
    case dns = "DNS Resolvers"
    case gamingApi = "Game APIs"
    case geforceNow = "GeForce NOW Servers"
    case custom = "Custom Targets"

    var iconSystemName: String {
        switch self {
        case .dns: return "network"
        case .gamingApi: return "gamecontroller"
        case .geforceNow: return "play.tv.fill"
        case .custom: return "terminal"
        }
    }
}

// MARK: - Ping Target Model

struct PingTarget: Identifiable, Hashable, Codable, Sendable {
    var id: String { "\(host):\(port)" }
    let name: String
    let host: String
    let port: UInt16
    var isCustom: Bool = false
    var category: TargetCategory = .dns
    var averageMs: Double? = nil
    var isBestCandidate: Bool = false

    @MainActor
    var displayAddress: String {
        if host == "auto-gateway" {
            let gw = NetworkStatusMonitor.shared.defaultGateway ?? "router"
            return port == 53 ? gw : "\(gw):\(port)"
        }
        if port == 53 || port == 443 {
            return host
        }
        return "\(host):\(port)"
    }

    static let builtins: [PingTarget] = [
        // Router / Gateway
        PingTarget(name: "Gateway (Auto)", host: "auto-gateway", port: 53, category: .dns),

        // Global Public DNS (Primary & Secondary)
        PingTarget(name: "Cloudflare DNS (Global)", host: "1.1.1.1", port: 53, category: .dns),
        PingTarget(name: "Cloudflare DNS Secondary (Global)", host: "1.0.0.1", port: 53, category: .dns),
        PingTarget(name: "Google DNS (Global)", host: "8.8.8.8", port: 53, category: .dns),
        PingTarget(name: "Google DNS Secondary (Global)", host: "8.8.4.4", port: 53, category: .dns),
        PingTarget(name: "Quad9 DNS (Global)", host: "9.9.9.9", port: 53, category: .dns),
        PingTarget(name: "Quad9 DNS Secondary (Global)", host: "149.112.112.112", port: 53, category: .dns),
        PingTarget(name: "OpenDNS (Global)", host: "208.67.222.222", port: 53, category: .dns),
        PingTarget(name: "OpenDNS Secondary (Global)", host: "208.67.220.220", port: 53, category: .dns),
        PingTarget(name: "AdGuard DNS (Global)", host: "94.140.14.14", port: 53, category: .dns),
        PingTarget(name: "AdGuard DNS Secondary (Global)", host: "94.140.15.15", port: 53, category: .dns),
        PingTarget(name: "CleanBrowsing DNS (Global)", host: "185.228.168.9", port: 53, category: .dns),
        PingTarget(name: "CleanBrowsing DNS Secondary (Global)", host: "185.228.169.9", port: 53, category: .dns),

        // Game Streaming & Ecosystem APIs
        PingTarget(name: "Valve Steam API", host: "api.steampowered.com", port: 443, category: .gamingApi),
        PingTarget(name: "Battle.net API", host: "us.battle.net", port: 443, category: .gamingApi),
        PingTarget(name: "GeForce NOW Routing API", host: "prod.cloudmatchbeta.nvidiagrid.net", port: 443, category: .gamingApi),

        // GeForce NOW Edge Servers (Global Edge Nodes)
        PingTarget(name: "GeForce NOW (NP-AMS-01)", host: "np-ams-01.cloudmatchbeta.nvidiagrid.net", port: 443, category: .geforceNow),
        PingTarget(name: "GeForce NOW (NP-AMS-02)", host: "np-ams-02.cloudmatchbeta.nvidiagrid.net", port: 443, category: .geforceNow),
        PingTarget(name: "GeForce NOW (NP-AMS-05)", host: "np-ams-05.cloudmatchbeta.nvidiagrid.net", port: 443, category: .geforceNow),
        PingTarget(name: "GeForce NOW (NP-AMS-06)", host: "np-ams-06.cloudmatchbeta.nvidiagrid.net", port: 443, category: .geforceNow),
        PingTarget(name: "GeForce NOW (NP-AMS-07)", host: "np-ams-07.cloudmatchbeta.nvidiagrid.net", port: 443, category: .geforceNow),
        PingTarget(name: "GeForce NOW (NP-AMS-08)", host: "np-ams-08.cloudmatchbeta.nvidiagrid.net", port: 443, category: .geforceNow),

        PingTarget(name: "GeForce NOW (NP-ASH-02)", host: "np-ash-02.cloudmatchbeta.nvidiagrid.net", port: 443, category: .geforceNow),
        PingTarget(name: "GeForce NOW (NP-ASH-03)", host: "np-ash-03.cloudmatchbeta.nvidiagrid.net", port: 443, category: .geforceNow),
        PingTarget(name: "GeForce NOW (NP-ASH-04)", host: "np-ash-04.cloudmatchbeta.nvidiagrid.net", port: 443, category: .geforceNow),

        PingTarget(name: "GeForce NOW (NP-ATL-01)", host: "np-atl-01.cloudmatchbeta.nvidiagrid.net", port: 443, category: .geforceNow),
        PingTarget(name: "GeForce NOW (NP-ATL-03)", host: "np-atl-03.cloudmatchbeta.nvidiagrid.net", port: 443, category: .geforceNow),
        PingTarget(name: "GeForce NOW (NP-ATL-04)", host: "np-atl-04.cloudmatchbeta.nvidiagrid.net", port: 443, category: .geforceNow),

        PingTarget(name: "GeForce NOW (NP-BOM-01)", host: "np-bom-01.cloudmatchbeta.nvidiagrid.net", port: 443, category: .geforceNow),

        PingTarget(name: "GeForce NOW (NP-CHI-01)", host: "np-chi-01.cloudmatchbeta.nvidiagrid.net", port: 443, category: .geforceNow),
        PingTarget(name: "GeForce NOW (NP-CHI-02)", host: "np-chi-02.cloudmatchbeta.nvidiagrid.net", port: 443, category: .geforceNow),
        PingTarget(name: "GeForce NOW (NP-CHI-03)", host: "np-chi-03.cloudmatchbeta.nvidiagrid.net", port: 443, category: .geforceNow),
        PingTarget(name: "GeForce NOW (NP-CHI-04)", host: "np-chi-04.cloudmatchbeta.nvidiagrid.net", port: 443, category: .geforceNow),
        PingTarget(name: "GeForce NOW (NP-CHI-05)", host: "np-chi-05.cloudmatchbeta.nvidiagrid.net", port: 443, category: .geforceNow),

        PingTarget(name: "GeForce NOW (NP-DAL-01)", host: "np-dal-01.cloudmatchbeta.nvidiagrid.net", port: 443, category: .geforceNow),
        PingTarget(name: "GeForce NOW (NP-DAL-02)", host: "np-dal-02.cloudmatchbeta.nvidiagrid.net", port: 443, category: .geforceNow),
        PingTarget(name: "GeForce NOW (NP-DAL-04)", host: "np-dal-04.cloudmatchbeta.nvidiagrid.net", port: 443, category: .geforceNow),
        PingTarget(name: "GeForce NOW (NP-DAL-05)", host: "np-dal-05.cloudmatchbeta.nvidiagrid.net", port: 443, category: .geforceNow),
        PingTarget(name: "GeForce NOW (NP-DAL-06)", host: "np-dal-06.cloudmatchbeta.nvidiagrid.net", port: 443, category: .geforceNow),

        PingTarget(name: "GeForce NOW (NP-FRK-02)", host: "np-frk-02.cloudmatchbeta.nvidiagrid.net", port: 443, category: .geforceNow),
        PingTarget(name: "GeForce NOW (NP-FRK-03)", host: "np-frk-03.cloudmatchbeta.nvidiagrid.net", port: 443, category: .geforceNow),
        PingTarget(name: "GeForce NOW (NP-FRK-06)", host: "np-frk-06.cloudmatchbeta.nvidiagrid.net", port: 443, category: .geforceNow),
        PingTarget(name: "GeForce NOW (NP-FRK-07)", host: "np-frk-07.cloudmatchbeta.nvidiagrid.net", port: 443, category: .geforceNow),
        PingTarget(name: "GeForce NOW (NP-FRK-08)", host: "np-frk-08.cloudmatchbeta.nvidiagrid.net", port: 443, category: .geforceNow),

        PingTarget(name: "GeForce NOW (NP-LAX-01)", host: "np-lax-01.cloudmatchbeta.nvidiagrid.net", port: 443, category: .geforceNow),
        PingTarget(name: "GeForce NOW (NP-LAX-02)", host: "np-lax-02.cloudmatchbeta.nvidiagrid.net", port: 443, category: .geforceNow),
        PingTarget(name: "GeForce NOW (NP-LAX-03)", host: "np-lax-03.cloudmatchbeta.nvidiagrid.net", port: 443, category: .geforceNow),

        PingTarget(name: "GeForce NOW (NP-LON-01)", host: "np-lon-01.cloudmatchbeta.nvidiagrid.net", port: 443, category: .geforceNow),
        PingTarget(name: "GeForce NOW (NP-LON-02)", host: "np-lon-02.cloudmatchbeta.nvidiagrid.net", port: 443, category: .geforceNow),
        PingTarget(name: "GeForce NOW (NP-LON-03)", host: "np-lon-03.cloudmatchbeta.nvidiagrid.net", port: 443, category: .geforceNow),
        PingTarget(name: "GeForce NOW (NP-LON-05)", host: "np-lon-05.cloudmatchbeta.nvidiagrid.net", port: 443, category: .geforceNow),
        PingTarget(name: "GeForce NOW (NP-LON-06)", host: "np-lon-06.cloudmatchbeta.nvidiagrid.net", port: 443, category: .geforceNow),
        PingTarget(name: "GeForce NOW (NP-LON-07)", host: "np-lon-07.cloudmatchbeta.nvidiagrid.net", port: 443, category: .geforceNow),
        PingTarget(name: "GeForce NOW (NP-LON-08)", host: "np-lon-08.cloudmatchbeta.nvidiagrid.net", port: 443, category: .geforceNow),

        PingTarget(name: "GeForce NOW (NP-MIA-01)", host: "np-mia-01.cloudmatchbeta.nvidiagrid.net", port: 443, category: .geforceNow),
        PingTarget(name: "GeForce NOW (NP-MIA-02)", host: "np-mia-02.cloudmatchbeta.nvidiagrid.net", port: 443, category: .geforceNow),
        PingTarget(name: "GeForce NOW (NP-MIA-03)", host: "np-mia-03.cloudmatchbeta.nvidiagrid.net", port: 443, category: .geforceNow),
        PingTarget(name: "GeForce NOW (NP-MIA-04)", host: "np-mia-04.cloudmatchbeta.nvidiagrid.net", port: 443, category: .geforceNow),

        PingTarget(name: "GeForce NOW (NP-MON-02)", host: "np-mon-02.cloudmatchbeta.nvidiagrid.net", port: 443, category: .geforceNow),

        PingTarget(name: "GeForce NOW (NP-NWK-01)", host: "np-nwk-01.cloudmatchbeta.nvidiagrid.net", port: 443, category: .geforceNow),
        PingTarget(name: "GeForce NOW (NP-NWK-02)", host: "np-nwk-02.cloudmatchbeta.nvidiagrid.net", port: 443, category: .geforceNow),
        PingTarget(name: "GeForce NOW (NP-NWK-03)", host: "np-nwk-03.cloudmatchbeta.nvidiagrid.net", port: 443, category: .geforceNow),
        PingTarget(name: "GeForce NOW (NP-NWK-04)", host: "np-nwk-04.cloudmatchbeta.nvidiagrid.net", port: 443, category: .geforceNow),

        PingTarget(name: "GeForce NOW (NP-PAR-01)", host: "np-par-01.cloudmatchbeta.nvidiagrid.net", port: 443, category: .geforceNow),
        PingTarget(name: "GeForce NOW (NP-PAR-02)", host: "np-par-02.cloudmatchbeta.nvidiagrid.net", port: 443, category: .geforceNow),
        PingTarget(name: "GeForce NOW (NP-PAR-04)", host: "np-par-04.cloudmatchbeta.nvidiagrid.net", port: 443, category: .geforceNow),
        PingTarget(name: "GeForce NOW (NP-PAR-05)", host: "np-par-05.cloudmatchbeta.nvidiagrid.net", port: 443, category: .geforceNow),
        PingTarget(name: "GeForce NOW (NP-PAR-06)", host: "np-par-06.cloudmatchbeta.nvidiagrid.net", port: 443, category: .geforceNow),
        PingTarget(name: "GeForce NOW (NP-PAR-07)", host: "np-par-07.cloudmatchbeta.nvidiagrid.net", port: 443, category: .geforceNow),

        PingTarget(name: "GeForce NOW (NP-PDX-01)", host: "np-pdx-01.cloudmatchbeta.nvidiagrid.net", port: 443, category: .geforceNow),
        PingTarget(name: "GeForce NOW (NP-PHX-02)", host: "np-phx-02.cloudmatchbeta.nvidiagrid.net", port: 443, category: .geforceNow),
        PingTarget(name: "GeForce NOW (NP-SEA-01)", host: "np-sea-01.cloudmatchbeta.nvidiagrid.net", port: 443, category: .geforceNow),
        PingTarget(name: "GeForce NOW (NP-SOF-02)", host: "np-sof-02.cloudmatchbeta.nvidiagrid.net", port: 443, category: .geforceNow),

        PingTarget(name: "GeForce NOW (NP-STH-01)", host: "np-sth-01.cloudmatchbeta.nvidiagrid.net", port: 443, category: .geforceNow),
        PingTarget(name: "GeForce NOW (NP-STH-02)", host: "np-sth-02.cloudmatchbeta.nvidiagrid.net", port: 443, category: .geforceNow),
        PingTarget(name: "GeForce NOW (NP-STH-03)", host: "np-sth-03.cloudmatchbeta.nvidiagrid.net", port: 443, category: .geforceNow),
        PingTarget(name: "GeForce NOW (NP-STH-04)", host: "np-sth-04.cloudmatchbeta.nvidiagrid.net", port: 443, category: .geforceNow),

        PingTarget(name: "GeForce NOW (NP-TYO-01)", host: "np-tyo-01.cloudmatchbeta.nvidiagrid.net", port: 443, category: .geforceNow),
        PingTarget(name: "GeForce NOW (NP-WAW-01)", host: "np-waw-01.cloudmatchbeta.nvidiagrid.net", port: 443, category: .geforceNow),
        PingTarget(name: "GeForce NOW (NP-YYZ-01)", host: "np-yyz-01.cloudmatchbeta.nvidiagrid.net", port: 443, category: .geforceNow)
    ]
}

// MARK: - Benchmark Result

struct BenchmarkResult: Identifiable, Sendable {
    let id = UUID()
    let target: PingTarget
    let averageMs: Double
    let minMs: Double
    let maxMs: Double
    let jitterMs: Double
    let successRate: Double
    var rank: Int = 0

    var isUsable: Bool { successRate > 0.5 }

    var qualityColor: String {
        if !isUsable { return "qualityPoor" }
        return LatencyQuality.from(ms: averageMs).color
    }
}

// MARK: - Benchmark State

enum BenchmarkState: Equatable {
    case idle
    case running(progress: Double)
    case completed
    case failed(String)
}

// MARK: - DNS Benchmark Engine

@MainActor
final class DNSBenchmarkEngine: ObservableObject {
    static let shared = DNSBenchmarkEngine()

    @Published private(set) var benchmarkResults: [BenchmarkResult] = []
    @Published private(set) var state: BenchmarkState = .idle
    @Published private(set) var bestTarget: PingTarget?
    @Published var targets: [PingTarget] = PingTarget.builtins
    @Published var selectedTarget: PingTarget = PingTarget.builtins[1]

    private let probesPerTarget = 4
    private var benchmarkTask: Task<Void, Never>?

    private let customTargetsKey = "com.psychostark.jitterkill.customTargets"
    private let selectedTargetKey = "com.psychostark.jitterkill.selectedTargetId"

    init() {
        loadCustomTargets()
        loadSelectedTarget()
    }

    // MARK: - Target Persistence

    private func loadCustomTargets() {
        if let data = UserDefaults.standard.data(forKey: customTargetsKey),
           let decoded = try? JSONDecoder().decode([PingTarget].self, from: data) {
            let customWithCategory = decoded.map { t -> PingTarget in
                var mod = t
                mod.isCustom = true
                mod.category = .custom
                return mod
            }
            targets = PingTarget.builtins + customWithCategory
        } else {
            targets = PingTarget.builtins
        }
    }

    private func saveCustomTargets() {
        let customOnly = targets.filter { $0.isCustom }
        if let data = try? JSONEncoder().encode(customOnly) {
            UserDefaults.standard.set(data, forKey: customTargetsKey)
        }
    }

    private func loadSelectedTarget() {
        if let savedId = UserDefaults.standard.string(forKey: selectedTargetKey),
           let found = targets.first(where: { $0.id == savedId }) {
            self.selectedTarget = found
            let host = resolvedHost(for: found)
            LatencyEngine.shared.updateTarget(host: host, port: found.port)
        } else {
            self.selectedTarget = PingTarget.builtins[1]
        }
    }

    // MARK: - Custom Target Management

    func addCustomTarget(name: String, host: String, port: UInt16) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedHost.isEmpty else { return }

        let target = PingTarget(
            name: trimmedName,
            host: trimmedHost,
            port: port,
            isCustom: true,
            category: .custom
        )

        if !targets.contains(where: { $0.id == target.id }) {
            targets.append(target)
            saveCustomTargets()
        }
    }

    func removeCustomTarget(id: String) {
        targets.removeAll { $0.isCustom && $0.id == id }
        saveCustomTargets()

        // If the deleted target was currently selected, fall back to Cloudflare DNS
        if selectedTarget.id == id {
            selectTarget(PingTarget.builtins[1])
        }

        // Also remove from active benchmark results
        benchmarkResults.removeAll { $0.target.id == id }
    }

    // MARK: - Auto-Detect Fastest

    func runAutoDetect() {
        benchmarkTask?.cancel()
        state = .running(progress: 0)
        benchmarkResults = []
        benchmarkTask = Task { [weak self] in
            await self?.runBenchmark()
        }
    }

    func cancelBenchmark() {
        benchmarkTask?.cancel()
        benchmarkTask = nil
        state = .idle
    }

    func selectTarget(_ target: PingTarget) {
        selectedTarget = target
        UserDefaults.standard.set(target.id, forKey: selectedTargetKey)
        let host = resolvedHost(for: target)
        LatencyEngine.shared.updateTarget(host: host, port: target.port)
    }

    // MARK: - Internal Benchmark

    private func runBenchmark() async {
        let candidates = targets.filter { $0.host != "auto-gateway" }
        var allCandidates = candidates
        if let gw = NetworkStatusMonitor.shared.defaultGateway {
            let gatewayTarget = PingTarget(name: "Gateway (\(gw))", host: gw, port: 80, category: .dns)
            allCandidates.insert(gatewayTarget, at: 0)
        }

        let totalWork = allCandidates.count * probesPerTarget
        nonisolated(unsafe) var completedWork = 0

        var results: [BenchmarkResult] = []

        await withTaskGroup(of: BenchmarkResult?.self) { group in
            for target in allCandidates {
                group.addTask { [self] in
                    await self.benchmarkTarget(target)
                }
            }
            for await result in group {
                if let r = result {
                    await MainActor.run { [weak self] in
                        self?.benchmarkResults.append(r)
                        self?.benchmarkResults.sort { $0.averageMs < $1.averageMs }
                        completedWork += self?.probesPerTarget ?? 0
                        let progress = Double(completedWork) / Double(totalWork)
                        self?.state = .running(progress: min(progress, 0.99))
                    }
                    results.append(r)
                }
            }
        }

        await MainActor.run { [weak self] in
            guard let self else { return }
            let sorted = results
                .filter { $0.isUsable }
                .sorted { $0.averageMs < $1.averageMs }
            self.benchmarkResults = sorted.enumerated().map { idx, r in
                var ranked = r
                ranked.rank = idx + 1
                return ranked
            }
            if let best = sorted.first {
                self.bestTarget = best.target
                self.selectTarget(best.target)
            }
            self.state = .completed
        }
    }

    private func benchmarkTarget(_ target: PingTarget) async -> BenchmarkResult {
        var samples: [Double] = []
        let host = resolvedHost(for: target)

        for _ in 0..<probesPerTarget {
            if Task.isCancelled { break }
            let result = await tcpProbe(host: host, port: target.port)
            if result.success { samples.append(result.latencyMs) }
            try? await Task.sleep(for: .milliseconds(250))
        }

        let total = probesPerTarget
        let successRate = Double(samples.count) / Double(total)

        guard !samples.isEmpty else {
            return BenchmarkResult(target: target, averageMs: 9999, minMs: 9999, maxMs: 9999, jitterMs: 0, successRate: 0)
        }
        let avg = samples.reduce(0, +) / Double(samples.count)
        let sorted = samples.sorted()
        let jitter = samples.count > 1
            ? sqrt(samples.map { pow($0 - avg, 2) }.reduce(0, +) / Double(samples.count - 1))
            : 0

        return BenchmarkResult(
            target: target,
            averageMs: avg,
            minMs: sorted.first ?? 0,
            maxMs: sorted.last ?? 0,
            jitterMs: jitter,
            successRate: successRate
        )
    }

    private func resolvedHost(for target: PingTarget) -> String {
        target.host == "auto-gateway"
            ? (NetworkStatusMonitor.shared.defaultGateway ?? "1.1.1.1")
            : target.host
    }

    // MARK: - TCP Probe (Swift 6-safe)

    private func tcpProbe(host: String, port: UInt16) async -> PingResult {
        let start = ContinuousClock.now
        let guard_ = ResumeGuard()

        let success = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let connection = NWConnection(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(rawValue: port) ?? 53,
                using: .tcp
            )
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1.5) {
                if guard_.claim() { continuation.resume(returning: false) }
                connection.cancel()
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if guard_.claim() { continuation.resume(returning: true) }
                    connection.cancel()
                case .failed, .cancelled:
                    if guard_.claim() { continuation.resume(returning: false) }
                default: break
                }
            }
            connection.start(queue: .global(qos: .utility))
        }

        let elapsed = start.duration(to: .now)
        let ms = Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
        return PingResult(timestamp: Date(), latencyMs: success ? ms : 9999, success: success, host: host, port: port)
    }
}
