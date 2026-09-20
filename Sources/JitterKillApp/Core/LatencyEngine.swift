// LatencyEngine.swift — Real-time TCP latency measurement engine
// Measures network latency using microsecond-precision TCP socket connection timing.
// Uses a rolling circular history buffer and computes Jitter (RFC 3550),
// Median, P95, and Packet Loss in real time.

import Foundation
import Network
import os.log

private let logger = Logger(subsystem: "com.psychostark.jitterkill", category: "LatencyEngine")

// MARK: - Thread-safe resume guard (Swift 6 concurrency)

/// Ensures a CheckedContinuation is resumed exactly once across concurrent closures.
final class ResumeGuard: @unchecked Sendable {
    private let lock = NSLock()
    private var _resumed = false

    /// Returns true if this call should do the resume (only first caller wins).
    func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !_resumed else { return false }
        _resumed = true
        return true
    }
}

// MARK: - Model Types

struct PingResult: Identifiable, Sendable {
    let id = UUID()
    let timestamp: Date
    let latencyMs: Double
    let success: Bool
    let host: String
    let port: UInt16
}

struct NetworkStats: Sendable {
    let currentPingMs: Double?
    let medianMs: Double
    let p95Ms: Double
    let jitterMs: Double
    let packetLossPercent: Double
    let minMs: Double
    let maxMs: Double
    let quality: LatencyQuality

    static let empty = NetworkStats(
        currentPingMs: nil, medianMs: 0, p95Ms: 0,
        jitterMs: 0, packetLossPercent: 0, minMs: 0, maxMs: 0, quality: .unknown
    )
}

enum LatencyQuality: String, Sendable {
    case excellent = "Excellent"
    case good      = "Good"
    case fair      = "Fair"
    case poor      = "Poor"
    case unknown   = "Measuring…"

    static func from(ms: Double) -> LatencyQuality {
        switch ms {
        case ..<20:  return .excellent
        case ..<50:  return .good
        case ..<100: return .fair
        default:     return .poor
        }
    }

    var color: String {
        switch self {
        case .excellent: return "qualityExcellent"
        case .good:      return "qualityGood"
        case .fair:      return "qualityFair"
        case .poor:      return "qualityPoor"
        case .unknown:   return "qualityUnknown"
        }
    }

    var systemImage: String {
        switch self {
        case .excellent: return "wifi"
        case .good:      return "wifi"
        case .fair:      return "wifi.exclamationmark"
        case .poor:      return "wifi.slash"
        case .unknown:   return "antenna.radiowaves.left.and.right"
        }
    }
}

// MARK: - Rolling History

final class RollingBuffer<T: Sendable>: @unchecked Sendable {
    private var buffer: [T] = []
    private let maxCount: Int
    private let lock = NSLock()

    init(maxCount: Int = 3600) {
        self.maxCount = maxCount
    }

    func append(_ element: T) {
        lock.lock(); defer { lock.unlock() }
        if buffer.count >= maxCount { buffer.removeFirst() }
        buffer.append(element)
    }

    func snapshot() -> [T] {
        lock.lock(); defer { lock.unlock() }
        return buffer
    }

    func filtered(after date: Date) -> [T] where T == PingResult {
        lock.lock(); defer { lock.unlock() }
        return buffer.filter { $0.timestamp > date }
    }
}

// MARK: - Latency Engine

@MainActor
final class LatencyEngine: ObservableObject {
    static let shared = LatencyEngine()

    @Published private(set) var stats: NetworkStats = .empty
    @Published private(set) var history: [PingResult] = []
    @Published private(set) var latestResult: PingResult?
    @Published var targetHost: String = "1.1.1.1"
    @Published var targetPort: UInt16 = 53
    @Published var probeInterval: TimeInterval = 2.0

    private let buffer = RollingBuffer<PingResult>(maxCount: 3600)
    private var probeTask: Task<Void, Never>?
    private let statsWindowSeconds: TimeInterval = 120

    var isRunning: Bool { probeTask != nil }

    func start() {
        guard probeTask == nil else { return }
        logger.info("LatencyEngine starting — target \(self.targetHost):\(self.targetPort)")
        probeTask = Task { [weak self] in
            await self?.probeLoop()
        }
    }

    func stop() {
        probeTask?.cancel()
        probeTask = nil
        logger.info("LatencyEngine stopped")
    }

    func updateTarget(host: String, port: UInt16) {
        targetHost = host
        targetPort = port
        if isRunning { stop(); start() }
    }

    // MARK: - Core Probe Loop

    private func probeLoop() async {
        while !Task.isCancelled {
            let host = targetHost
            let port = targetPort
            let result = await probe(host: host, port: port)
            await MainActor.run { [weak self] in
                self?.record(result)
            }
            try? await Task.sleep(for: .seconds(probeInterval))
        }
    }

    // MARK: - TCP Probe (Swift 6-safe)

    private func probe(host: String, port: UInt16) async -> PingResult {
        let start = ContinuousClock.now
        let guard_ = ResumeGuard()

        let success = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let connection = NWConnection(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(rawValue: port) ?? 53,
                using: .tcp
            )

            // Timeout via DispatchQueue (no DispatchWorkItem capture needed)
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
        return PingResult(
            timestamp: Date(),
            latencyMs: success ? ms : 1500,
            success: success,
            host: host,
            port: port
        )
    }

    // MARK: - Recording & Stats

    private func record(_ result: PingResult) {
        buffer.append(result)
        latestResult = result
        let windowStart = Date().addingTimeInterval(-statsWindowSeconds)
        let window = buffer.filtered(after: windowStart)
        history = buffer.snapshot()
        stats = computeStats(from: window)
    }

    private func computeStats(from results: [PingResult]) -> NetworkStats {
        let successful = results.filter { $0.success }.map { $0.latencyMs }
        let total = results.count

        guard !successful.isEmpty else {
            let loss = total > 0 ? 100.0 : 0.0
            return NetworkStats(
                currentPingMs: nil, medianMs: 0, p95Ms: 0,
                jitterMs: 0, packetLossPercent: loss, minMs: 0, maxMs: 0, quality: .unknown
            )
        }
        let sorted = successful.sorted()
        let median = sorted[sorted.count / 2]
        let p95 = sorted[Int(Double(sorted.count) * 0.95)]
        let minMs = sorted.first ?? 0
        let maxMs = sorted.last ?? 0
        let mean = successful.reduce(0, +) / Double(successful.count)
        let jitter = successful.count > 1
            ? sqrt(successful.map { pow($0 - mean, 2) }.reduce(0, +) / Double(successful.count - 1))
            : 0
        let loss = total > 0 ? Double(total - successful.count) / Double(total) * 100 : 0
        let current = latestResult?.success == true ? latestResult?.latencyMs : nil
        return NetworkStats(
            currentPingMs: current,
            medianMs: median,
            p95Ms: p95,
            jitterMs: jitter,
            packetLossPercent: loss,
            minMs: minMs,
            maxMs: maxMs,
            quality: LatencyQuality.from(ms: current ?? median)
        )
    }
}
