// MenuBarPopoverView.swift — Compact menu bar popover
// Clean Liquid Glass design with live ping sparkline, status badges, and quick toggle.

import SwiftUI
import Charts

struct MenuBarPopoverView: View {
    @EnvironmentObject var latencyEngine: LatencyEngine
    @EnvironmentObject var engine: JitterKillEngine
    @EnvironmentObject var monitor: NetworkStatusMonitor
    let openDashboard: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if !engine.isDaemonInstalled {
                helperWarningBanner
                Divider()
            }
            ScrollView {
                VStack(spacing: 10) {
                    pingSection
                    Divider().padding(.horizontal, 14)
                    subsystemSection
                    Divider().padding(.horizontal, 14)
                    footerActions
                }
                .padding(.vertical, 12)
            }
        }
        .frame(width: 320)
        .background(.ultraThinMaterial)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            AppAssets.logoSwiftUIImage
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 26, height: 26)
                .shadow(color: engine.isActive ? .green.opacity(0.4) : .clear, radius: 4)

            VStack(alignment: .leading, spacing: 1) {
                Text("JitterKill")
                    .font(.headline)
                Text(engine.phase == .activating ? "Activating lockdown…" :
                     (engine.phase == .deactivating ? "Restoring normal network…" :
                     (engine.isActive ? (engine.currentTriggerApp != nil ? "Locked down (\(engine.currentTriggerApp!) active)" : monitor.streamingMode.displayName) : "Standby — not optimized")))
                    .font(.caption)
                    .foregroundStyle(engine.isActive ? .green : (engine.phase == .idle ? .secondary : .orange))
                    .lineLimit(1)
            }

            Spacer()

            if engine.phase == .activating || engine.phase == .deactivating {
                ProgressView()
                    .controlSize(.small)
            } else {
                // Main toggle
                Toggle("", isOn: Binding(
                    get: { engine.isActive },
                    set: { _ in Task { await engine.toggle() } }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .tint(.green)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - Helper Warning Banner

    private var helperWarningBanner: some View {
        Button {
            Task { await engine.installOrRepairHelper() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
                Text("Helper not installed — Click to setup")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                Spacer()
                if engine.isInstallingHelper {
                    ProgressView().controlSize(.mini)
                } else {
                    Text("Install")
                        .font(.caption.bold())
                        .foregroundStyle(.blue)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.orange.opacity(0.12))
        }
        .buttonStyle(.plain)
        .disabled(engine.isInstallingHelper)
    }

    // MARK: - Ping Section

    private var pingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                // Live ping hero value
                Group {
                    if let ping = latencyEngine.stats.currentPingMs {
                        Text(String(format: "%.0f", ping))
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                            .foregroundStyle(LatencyPalette.forLatency(ping))
                            .contentTransition(.numericText())
                        Text("ms")
                            .font(.title3.weight(.light))
                            .foregroundStyle(.secondary)
                    } else {
                        ProgressView().controlSize(.small)
                        Text("Measuring…").font(.title3).foregroundStyle(.secondary)
                    }
                }
                Spacer()

                // Mini stats column
                VStack(alignment: .trailing, spacing: 3) {
                    miniStat(label: "Jitter", value: String(format: "%.0f ms", latencyEngine.stats.jitterMs))
                    miniStat(label: "Loss",   value: String(format: "%.1f%%", latencyEngine.stats.packetLossPercent))
                    miniStat(label: "P95",    value: String(format: "%.0f ms", latencyEngine.stats.p95Ms))
                }
            }
            .padding(.horizontal, 14)

            // Mini sparkline
            sparkline
                .frame(height: 56)
                .padding(.horizontal, 14)
        }
    }

    private func miniStat(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.caption2).foregroundStyle(.tertiary)
            Text(value).font(.caption2.monospacedDigit().weight(.semibold)).foregroundStyle(.secondary)
        }
    }

    private var sparkline: some View {
        let history = latencyEngine.history.suffix(60).filter { $0.success }
        if history.isEmpty {
            return AnyView(Color.clear)
        }
        let color = LatencyPalette.forLatency(latencyEngine.stats.currentPingMs ?? 50)
        return AnyView(
            Chart(history) { dp in
                LineMark(
                    x: .value("Time", dp.timestamp),
                    y: .value("Ping", dp.latencyMs)
                )
                .foregroundStyle(color)
                .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .interpolationMethod(.catmullRom)

                AreaMark(
                    x: .value("Time", dp.timestamp),
                    yStart: .value("Base", 0),
                    yEnd: .value("Ping", dp.latencyMs)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [color.opacity(0.2), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
        )
    }

    // MARK: - Subsystem Status

    private var subsystemSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Subsystems")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)

            VStack(spacing: 0) {
                subsystemRow("awdl0", isLocked: !monitor.awdl0State.isUp,   icon: "wifi")
                Divider().padding(.leading, 44)
                subsystemRow("llw0 (Skywalk)", isLocked: !monitor.llw0State.isUp, icon: "antenna.radiowaves.left.and.right")
                Divider().padding(.leading, 44)
                subsystemRow("TCP delayed_ack: \(monitor.delayedAck)",
                             isLocked: monitor.delayedAck == 0,
                             icon: "network.badge.shield.half.filled")
                if !monitor.activeStreamingAppNames.isEmpty {
                    Divider().padding(.leading, 44)
                    subsystemRow(monitor.activeStreamingAppNames.joined(separator: ", "),
                                 isLocked: true,
                                 icon: "gamecontroller.fill")
                }
            }
            .padding(.horizontal, 14)
        }
    }

    private func subsystemRow(_ label: String, isLocked: Bool, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.callout)
                .foregroundStyle(isLocked ? .green : .secondary)
                .frame(width: 24)
            Text(label).font(.subheadline)
            Spacer()
            Image(systemName: isLocked ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(isLocked ? .green : .secondary)
                .font(.callout)
        }
        .padding(.vertical, 7)
    }

    // MARK: - Footer Actions

    private var footerActions: some View {
        HStack {
            Button {
                openDashboard()
            } label: {
                Label("Open Dashboard", systemImage: "rectangle.expand.vertical")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)

            Button {
                AppDelegate.shared?.openPreferences()
            } label: {
                Image(systemName: "gearshape.fill")
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 4)
    }
}
