// DashboardView.swift — Full native macOS Dashboard Window
// Uses Liquid Glass (macOS 26+) GlassEffectContainer and glassEffect() on cards.
// Falls back to .regularMaterial on macOS 14-25.
//
// NOTE: @State is a macro (SwiftUIMacros) not shipped with Command Line Tools.
// All mutable view state is held in ObservableObject + @StateObject instead.

import SwiftUI
import Charts
import UniformTypeIdentifiers

// MARK: - Layout

private enum Layout {
    static let cardSpacing: CGFloat = 14
    static let cardPadding: CGFloat = 18
    static let cardCornerRadius: CGFloat = 16
}

// MARK: - Glass Card Modifier

private struct GlassCard: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Layout.cardCornerRadius, style: .continuous)
        if #available(macOS 26, *) {
            content
                .padding(Layout.cardPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(.regular, in: shape)
        } else {
            content
                .padding(Layout.cardPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial, in: shape)
                .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
        }
    }
}

extension View {
    func glassCard() -> some View { modifier(GlassCard()) }
}

// MARK: - Dashboard Tab Selection State

final class DashboardNavState: ObservableObject {
    @Published var selectedTab: DashboardTab = .monitor
}

// MARK: - Dashboard Root View

struct DashboardView: View {
    @EnvironmentObject var latencyEngine: LatencyEngine
    @EnvironmentObject var engine: JitterKillEngine
    @EnvironmentObject var networkMonitor: NetworkStatusMonitor
    @EnvironmentObject var benchmark: DNSBenchmarkEngine
    @EnvironmentObject var appManager: StreamingAppManager

    @StateObject private var navState = DashboardNavState()
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .topLeading) {
            backgroundGradient.ignoresSafeArea()
            HSplitView {
                sidebar.frame(minWidth: 180, maxWidth: 200)
                content.frame(minWidth: 500)
            }
        }
        .frame(minWidth: 720, minHeight: 560)
    }

    // MARK: - Background

    private var backgroundGradient: some View {
        Group {
            if colorScheme == .dark {
                LinearGradient(
                    stops: [
                        .init(color: Color(red: 0.05, green: 0.06, blue: 0.12), location: 0),
                        .init(color: Color(red: 0.06, green: 0.10, blue: 0.18), location: 1)
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            } else {
                Color(NSColor.windowBackgroundColor)
            }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    AppAssets.logoSwiftUIImage
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24, height: 24)
                        .shadow(color: engine.isActive ? .green.opacity(0.4) : .clear, radius: 4)
                    Text("JitterKill").font(.title3.bold())
                }
                Text(engine.phase.rawValue)
                    .font(.caption)
                    .foregroundStyle(engine.phase == .active ? .green : (engine.phase == .idle ? .secondary : .orange))
            }
            .padding(.horizontal, 14)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Divider().padding(.horizontal, 10)

            VStack(spacing: 2) {
                ForEach(DashboardTab.allCases) { tab in
                    SidebarNavItem(tab: tab, isSelected: navState.selectedTab == tab) {
                        withAnimation(.easeInOut(duration: 0.2)) { navState.selectedTab = tab }
                    }
                }
            }
            .padding(.top, 8)
            .padding(.horizontal, 8)

            Spacer()

            VStack(spacing: 10) {
                Divider().padding(.horizontal, 10)
                quickToggleButton.padding(.horizontal, 14).padding(.bottom, 14)
            }
        }
        .frame(maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }

    private var quickToggleButton: some View {
        Button {
            Task { await engine.toggle() }
        } label: {
            HStack(spacing: 8) {
                switch engine.phase {
                case .activating:
                    ProgressView().controlSize(.small)
                    Text("Activating…").fontWeight(.medium)
                case .deactivating:
                    ProgressView().controlSize(.small)
                    Text("Deactivating…").fontWeight(.medium)
                case .active:
                    Image(systemName: "stop.circle.fill")
                    Text("Deactivate").fontWeight(.medium)
                case .idle:
                    Image(systemName: "play.circle.fill")
                    Text("Activate").fontWeight(.medium)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(engine.phase == .active ? .red : (engine.phase == .idle ? .green : .secondary))
        .disabled(engine.phase == .activating || engine.phase == .deactivating)
        .controlSize(.large)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        ScrollView {
            let cards = cardStack
            Group {
                if #available(macOS 26, *) {
                    GlassEffectContainer { cards }
                } else {
                    cards
                }
            }
            .padding(20)
        }
        .scrollContentBackground(.hidden)
    }

    private var cardStack: some View {
        VStack(alignment: .leading, spacing: Layout.cardSpacing) {
            switch navState.selectedTab {
            case .monitor:
                if !engine.isDaemonInstalled {
                    HelperSetupCard()
                }
                NetworkQualityCard()
                LatencyHistoryCard()
                SubsystemStatusCard()
            case .streaming:
                StreamingModeCard()
                ActiveStreamingAppsCard()
                AppRulesManagerCard()
            case .dns:
                DNSManagerCard()
            case .settings:
                EngineSettingsCard()
            }
        }
    }
}

// MARK: - Dashboard Tabs

enum DashboardTab: String, CaseIterable, Identifiable {
    case monitor   = "Monitor"
    case streaming = "Streaming"
    case dns       = "DNS & Targets"
    case settings  = "Settings"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .monitor:   return "chart.xyaxis.line"
        case .streaming: return "gamecontroller.fill"
        case .dns:       return "network"
        case .settings:  return "gearshape.fill"
        }
    }
}

// MARK: - Sidebar Nav Item

private struct SidebarNavItem: View {
    let tab: DashboardTab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: tab.systemImage).frame(width: 18, alignment: .center)
                Text(tab.rawValue).font(.subheadline)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                isSelected
                    ? RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.primary.opacity(0.1))
                    : nil
            )
            .foregroundStyle(isSelected ? .primary : .secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Helper Setup Card

private struct HelperSetupCard: View {
    @EnvironmentObject var engine: JitterKillEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.title)
                    .foregroundStyle(.orange)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(.orange.opacity(0.15)))

                VStack(alignment: .leading, spacing: 3) {
                    Text("One-Time Setup: Install Background Helper")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text("JitterKill requires its lightweight background service to lock down Wi-Fi interfaces (awdl0, llw0, nan0) and optimize TCP latency without needing your password every time.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Button {
                    Task { await engine.installOrRepairHelper() }
                } label: {
                    HStack(spacing: 6) {
                        if engine.isInstallingHelper {
                            ProgressView().controlSize(.small)
                            Text("Installing…")
                        } else {
                            Image(systemName: "arrow.down.circle.fill")
                            Text("Install Helper Service")
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .tint(.blue)
                .disabled(engine.isInstallingHelper)
            }
        }
        .glassCard()
    }
}

// MARK: - Network Quality Card

private struct NetworkQualityCard: View {
    @EnvironmentObject var latencyEngine: LatencyEngine
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 52

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Network Quality").font(.headline)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 28) {
                    heroPingBlock.frame(minWidth: 120, alignment: .leading)
                    Divider().frame(height: 80)
                    metricGrid
                }
                VStack(alignment: .leading, spacing: 14) {
                    heroPingBlock; Divider(); metricGrid
                }
            }
        }
        .glassCard()
    }

    private var heroPingBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let ping = latencyEngine.stats.currentPingMs {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(String(format: "%.0f", ping))
                        .font(.system(size: heroSize, weight: .bold, design: .rounded))
                        .foregroundStyle(LatencyPalette.forLatency(ping))
                        .contentTransition(.numericText())
                    Text("ms").font(.title2.weight(.light)).foregroundStyle(.secondary)
                }
                qualityBadge
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Measuring…").font(.title3)
                }
            }
        }
    }

    private var qualityBadge: some View {
        let quality = latencyEngine.stats.quality
        return Label(quality.rawValue, systemImage: quality.systemImage)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(LatencyPalette.forLatency(latencyEngine.stats.currentPingMs ?? 999))
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(.ultraThinMaterial, in: Capsule())
    }

    private var metricGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 14)], alignment: .leading, spacing: 10) {
            StatCell(label: "Median", value: String(format: "%.0f ms", latencyEngine.stats.medianMs),
                     color: LatencyPalette.forLatency(latencyEngine.stats.medianMs))
            StatCell(label: "Jitter", value: String(format: "%.0f ms", latencyEngine.stats.jitterMs))
            StatCell(label: "P95",    value: String(format: "%.0f ms", latencyEngine.stats.p95Ms),
                     color: LatencyPalette.forLatency(latencyEngine.stats.p95Ms))
            StatCell(label: "Loss",   value: String(format: "%.1f%%", latencyEngine.stats.packetLossPercent),
                     color: latencyEngine.stats.packetLossPercent > 2 ? LatencyPalette.poor : LatencyPalette.excellent)
            StatCell(label: "Min",    value: String(format: "%.0f ms", latencyEngine.stats.minMs))
            StatCell(label: "Max",    value: String(format: "%.0f ms", latencyEngine.stats.maxMs))
        }
    }
}

// MARK: - Stat Cell

struct StatCell: View {
    let label: String
    let value: String
    var color: Color? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(color ?? .primary)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Latency History Card

private struct LatencyHistoryCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { LatencyChartView() }.glassCard()
    }
}

// MARK: - Subsystem Status Card

private struct SubsystemStatusCard: View {
    @EnvironmentObject var monitor: NetworkStatusMonitor
    @EnvironmentObject var engine: JitterKillEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("System Lockdown Status").font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], alignment: .leading, spacing: 10) {
                InterfaceBadge(label: "awdl0", detail: "AirDrop / Bonjour",  isLocked: !monitor.awdl0State.isUp)
                InterfaceBadge(label: "llw0",  detail: "Skywalk LLW",         isLocked: !monitor.llw0State.isUp)
                InterfaceBadge(label: "nan0",  detail: "Wi-Fi Aware",          isLocked: !monitor.nan0State.isUp)
                SystemBadge(label: "TCP delayed_ack",
                            detail: monitor.delayedAck == 0 ? "Instant ACK (0)" : "Delayed ACK (\(monitor.delayedAck))",
                            isOptimized: monitor.delayedAck == 0)
                SystemBadge(label: "AirDrop",  detail: "Discovery broadcast", isOptimized: engine.isActive)
                SystemBadge(label: "Location", detail: "Background scan",     isOptimized: engine.isActive)
            }
        }
        .glassCard()
    }
}

private struct InterfaceBadge: View {
    let label: String; let detail: String; let isLocked: Bool
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isLocked ? "lock.fill" : "lock.open.fill")
                .foregroundStyle(isLocked ? .green : .orange).font(.callout)
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.subheadline.weight(.semibold))
                Text(isLocked ? "Locked DOWN ✓" : "Active (UP)")
                    .font(.caption2).foregroundStyle(isLocked ? .green : .secondary)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(isLocked ? Color.green.opacity(0.1) : Color.orange.opacity(0.08)))
    }
}

private struct SystemBadge: View {
    let label: String; let detail: String; let isOptimized: Bool
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isOptimized ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(isOptimized ? .green : .secondary).font(.callout)
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(isOptimized ? Color.green.opacity(0.1) : Color.primary.opacity(0.04)))
    }
}

// MARK: - Streaming Mode Card

private struct StreamingModeCard: View {
    @EnvironmentObject var monitor: NetworkStatusMonitor
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Streaming Mode").font(.headline)
            HStack(spacing: 12) {
                Image(systemName: monitor.streamingMode.systemImage)
                    .font(.system(size: 32))
                    .foregroundStyle(monitor.streamingMode.isWarning ? .orange : .green)
                VStack(alignment: .leading, spacing: 3) {
                    Text(monitor.streamingMode.displayName).font(.subheadline.weight(.semibold))
                    if monitor.streamingMode.isWarning {
                        Text("High latency expected — try port forwarding UDP 41641 for direct connection.")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    if let gw = monitor.defaultGateway {
                        Text("Gateway: \(gw)").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(monitor.streamingMode.isWarning ? Color.orange.opacity(0.1) : Color.green.opacity(0.08)))
        }
        .glassCard()
    }
}

// MARK: - Active Streaming Apps Card

private struct ActiveStreamingAppsCard: View {
    @EnvironmentObject var monitor: NetworkStatusMonitor
    @EnvironmentObject var engine: JitterKillEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Active Game Streaming Processes").font(.headline)
                Spacer()
                if let trigger = engine.currentTriggerApp ?? monitor.triggerAppName {
                    HStack(spacing: 4) {
                        Image(systemName: "target")
                        Text("Trigger: \(trigger)")
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.green.opacity(0.15)))
                }
            }

            if monitor.detectedProcesses.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "moon.zzz.fill").foregroundStyle(.secondary)
                    Text("No streaming apps detected — standby mode 💤")
                        .foregroundStyle(.secondary).font(.subheadline)
                }
                .padding(.vertical, 4)
            } else {
                VStack(spacing: 8) {
                    ForEach(monitor.detectedProcesses) { proc in
                        HStack(spacing: 12) {
                            Image(systemName: "gamecontroller.fill").foregroundStyle(.teal)
                                .font(.title3)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(proc.name).font(.subheadline.weight(.semibold))
                                    Text("PID \(proc.pid)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Text(proc.isRealTimePriority ? "Real-time priority 🚀 (-20)" : "Normal scheduling priority")
                                    .font(.caption2)
                                    .foregroundStyle(proc.isRealTimePriority ? .green : .secondary)
                            }
                            Spacer()
                            if proc.isRealTimePriority {
                                Text("REAL-TIME")
                                    .font(.system(size: 9, weight: .black))
                                    .foregroundStyle(.green)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.green.opacity(0.15)))
                            }
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.03)))
                    }
                }
            }
        }
        .glassCard()
    }
}


// MARK: - App Rules Manager Card

private struct AppRulesManagerCard: View {
    @EnvironmentObject var appManager: StreamingAppManager
    @StateObject private var formState = AddProcessFormState()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Auto-Activation & Priority Rules").font(.headline)
                    Text("Configure apps that trigger lockdown and receive real-time kernel scheduling priority.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 8) {
                    Button {
                        appManager.scanForInstalledApps()
                    } label: {
                        Label("Scan Installed", systemImage: "sparkle.magnifyingglass")
                    }
                    .controlSize(.small)

                    Button {
                        pickApplication()
                    } label: {
                        Label("Add App…", systemImage: "plus.app")
                    }
                    .controlSize(.small)

                    Button {
                        formState.showSheet = true
                    } label: {
                        Label("Add Process…", systemImage: "terminal")
                    }
                    .controlSize(.small)
                }
            }

            Divider()

            if appManager.apps.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "sparkle.magnifyingglass").font(.title3).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No Supported Streaming Apps Detected").font(.subheadline.weight(.semibold))
                        Text("Install Moonlight, GeForce NOW, Steam, Parsec, or click 'Add App…' to select any installed application.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 10)
            } else {
                VStack(spacing: 8) {
                    ForEach(appManager.apps) { rule in
                        AppRuleRow(rule: rule)
                    }
                }
            }
        }
        .glassCard()
        .sheet(isPresented: $formState.showSheet) {
            AddProcessSheet(formState: formState)
        }
    }

    private func pickApplication() {
        let panel = NSOpenPanel()
        panel.title = "Select Game Streaming Application"
        panel.prompt = "Add to JitterKill"
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            appManager.addAppFromBundle(url: url)
        }
    }
}

// MARK: - App Rule Row

private struct AppRuleRow: View {
    let rule: StreamingAppRule
    @EnvironmentObject var appManager: StreamingAppManager

    var body: some View {
        let runningPIDs = appManager.runningPIDsByAppId[rule.id] ?? []
        let isRunning = !runningPIDs.isEmpty

        HStack(spacing: 12) {
            Image(systemName: rule.iconSystemName ?? "gamecontroller")
                .font(.title3)
                .foregroundStyle(isRunning ? .green : .secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(rule.name).font(.subheadline.weight(.semibold))
                    if isRunning {
                        Text("Running (PID \(runningPIDs.map { String($0) }.joined(separator: ", ")))")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.green.opacity(0.15)))
                    }
                    if !rule.isBuiltIn {
                        Text("Custom")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.teal)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(Color.teal.opacity(0.12)))
                    }
                }

                if rule.id == "tailscale" {
                    Text(isRunning ? "Active VPN Mesh Stream" : "Active connection required • Currently Standby")
                        .font(.caption2).foregroundStyle(isRunning ? .green : .secondary)
                } else {
                    Text("Process: \(rule.processPatterns.joined(separator: ", "))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Auto-Activate Toggle
            Toggle(isOn: Binding(
                get: { rule.autoActivate },
                set: { _ in appManager.toggleAutoActivate(id: rule.id) }
            )) {
                Text("Auto-Lockdown")
                    .font(.caption)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .help("Automatically activates JitterKill lockdown when \(rule.name) is running.")

            Divider().frame(height: 18)

            // Priority Boost Toggle
            Toggle(isOn: Binding(
                get: { rule.boostPriority },
                set: { _ in appManager.toggleBoostPriority(id: rule.id) }
            )) {
                HStack(spacing: 3) {
                    Text("Real-Time")
                        .font(.caption)
                    if rule.boostPriority {
                        Text("🚀").font(.caption2)
                    }
                }
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .help("Elevates process priority to -20 (real-time kernel scheduling) during active sessions.")

            Button {
                appManager.removeApp(id: rule.id)
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundStyle(.red.opacity(0.7))
            }
            .buttonStyle(.plain)
            .padding(.leading, 4)
            .help("Remove rule")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isRunning ? Color.green.opacity(0.06) : Color.primary.opacity(0.02))
        )
    }
}

// MARK: - Add Process Sheet

private struct AddProcessSheet: View {
    @ObservedObject var formState: AddProcessFormState
    @EnvironmentObject var appManager: StreamingAppManager

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Custom Process Rule").font(.headline)
            Text("Enter the display name and executable or process pattern to watch.")
                .font(.caption).foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                TextField("Display Name (e.g. Cemu Emulator)", text: $formState.appName)
                    .textFieldStyle(.roundedBorder)

                TextField("Process Name or Executable (e.g. Cemu, retroarch)", text: $formState.processPattern)
                    .textFieldStyle(.roundedBorder)

                Toggle("Auto-activate lockdown when this process runs", isOn: $formState.autoActivate)
                Toggle("Elevate priority to Real-Time (-20)", isOn: $formState.boostPriority)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    formState.reset()
                }
                .keyboardShortcut(.cancelAction)

                Button("Add Rule") {
                    appManager.addCustomProcess(
                        name: formState.appName,
                        processPattern: formState.processPattern,
                        autoActivate: formState.autoActivate,
                        boostPriority: formState.boostPriority
                    )
                    formState.reset()
                }
                .buttonStyle(.borderedProminent)
                .disabled(formState.appName.trimmingCharacters(in: .whitespaces).isEmpty ||
                          formState.processPattern.trimmingCharacters(in: .whitespaces).isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 400)
    }
}

// MARK: - DNS Manager Form State

final class DNSManagerFormState: ObservableObject {
    @Published var showAddCustom: Bool = false
    @Published var customName: String = ""
    @Published var customHost: String = ""
    @Published var customPortStr: String = "53"
    @Published var searchText: String = ""
    @Published var selectedCategory: String = "All"
}

// MARK: - DNS Manager Card

private struct DNSManagerCard: View {
    @EnvironmentObject var benchmark: DNSBenchmarkEngine
    @StateObject private var form = DNSManagerFormState()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("DNS & Ping Targets").font(.headline)
                    HStack(spacing: 6) {
                        Text("Active:").font(.caption).foregroundStyle(.secondary)
                        Text("\(benchmark.selectedTarget.name) (\(benchmark.selectedTarget.displayAddress))")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.green)
                    }
                }
                Spacer()
                autoDetectButton
            }

            if !benchmark.benchmarkResults.isEmpty { benchmarkResultsView }

            // Category Picker & Search Bar
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    Picker("", selection: $form.selectedCategory) {
                        Text("All (\(benchmark.targets.count))").tag("All")
                        Text("DNS Resolvers").tag("DNS Resolvers")
                        Text("Game APIs").tag("Game APIs")
                        Text("GeForce NOW").tag("GeForce NOW")
                        Text("Custom (\(benchmark.targets.filter { $0.isCustom }.count))").tag("Custom Hosts")
                    }
                    .pickerStyle(.segmented)

                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.caption)
                        TextField("Search…", text: $form.searchText)
                            .textFieldStyle(.plain)
                        if !form.searchText.isEmpty {
                            Button {
                                form.searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill").font(.caption).foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
                    .frame(maxWidth: 180)
                }

                targetListScrollView
            }

            if form.showAddCustom {
                customTargetForm
            } else {
                Button { form.showAddCustom = true } label: {
                    Label("Add Custom Host", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderless).foregroundStyle(.teal)
            }
        }
        .glassCard()
    }

    private var autoDetectButton: some View {
        Group {
            switch benchmark.state {
            case .running(let progress):
                HStack(spacing: 8) {
                    ProgressView(value: progress).frame(width: 80).controlSize(.small)
                    Button("Cancel") { benchmark.cancelBenchmark() }.buttonStyle(.borderless).foregroundStyle(.red)
                }
            default:
                Button { benchmark.runAutoDetect() } label: {
                    Label("Auto-Detect Fastest", systemImage: "bolt.horizontal.fill")
                }
                .buttonStyle(.borderedProminent).tint(.teal).controlSize(.small)
            }
        }
    }

    private var benchmarkResultsView: some View {
        VStack(spacing: 0) {
            ForEach(benchmark.benchmarkResults.prefix(6)) { result in
                HStack(spacing: 10) {
                    Text(result.rank == 1 ? "🥇" : result.rank == 2 ? "🥈" : "#\(result.rank)")
                        .font(.caption.monospacedDigit()).frame(width: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(result.target.name).font(.subheadline)
                        Text(result.target.host).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(String(format: "%.0f ms", result.averageMs))
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                            .foregroundStyle(LatencyPalette.forLatency(result.averageMs))
                        Text(String(format: "%.0f%% OK", result.successRate * 100))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    if benchmark.selectedTarget.id == result.target.id {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.teal)
                    }
                }
                .padding(.vertical, 7)
                .contentShape(Rectangle())
                .onTapGesture { benchmark.selectTarget(result.target) }
                if result.id != benchmark.benchmarkResults.prefix(6).last?.id { Divider() }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.ultraThinMaterial))
    }

    private var filteredTargets: [PingTarget] {
        benchmark.targets.filter { target in
            let matchesCategory: Bool
            switch form.selectedCategory {
            case "DNS Resolvers": matchesCategory = (target.category == .dns)
            case "Game APIs": matchesCategory = (target.category == .gamingApi)
            case "GeForce NOW": matchesCategory = (target.category == .geforceNow)
            case "Custom Hosts": matchesCategory = target.isCustom
            default: matchesCategory = true
            }

            guard matchesCategory else { return false }

            let query = form.searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !query.isEmpty else { return true }
            return target.name.lowercased().contains(query) || target.host.lowercased().contains(query)
        }
    }

    private var targetListScrollView: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(filteredTargets) { target in
                    let isSelected = benchmark.selectedTarget.id == target.id
                    HStack(spacing: 10) {
                        Image(systemName: target.category.iconSystemName)
                            .font(.callout)
                            .foregroundStyle(isSelected ? .green : .secondary)
                            .frame(width: 20)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(target.name).font(.subheadline.weight(isSelected ? .semibold : .regular))
                            Text(target.displayAddress).font(.caption2).foregroundStyle(.secondary)
                        }

                        Spacer()

                        if isSelected {
                            Text("ACTIVE")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.green)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.green.opacity(0.15)))
                        }

                        if target.isCustom {
                            Button(role: .destructive) {
                                benchmark.removeCustomTarget(id: target.id)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.caption)
                                    .foregroundStyle(.red.opacity(0.8))
                            }
                            .buttonStyle(.plain)
                            .padding(.leading, 6)
                            .help("Remove custom host")
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(isSelected ? Color.green.opacity(0.08) : Color.primary.opacity(0.02))
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        benchmark.selectTarget(target)
                    }
                }
            }
            .padding(4)
        }
        .frame(height: 250)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.02)))
    }

    private var customTargetForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add Custom Host").font(.subheadline.weight(.medium))
            HStack(spacing: 8) {
                TextField("Name (e.g. Custom DNS)", text: $form.customName).textFieldStyle(.roundedBorder)
                TextField("Host or IP", text: $form.customHost).textFieldStyle(.roundedBorder)
                TextField("Port", text: $form.customPortStr).textFieldStyle(.roundedBorder).frame(width: 65)
            }
            HStack {
                Spacer()
                Button("Cancel") { form.showAddCustom = false }.buttonStyle(.bordered).keyboardShortcut(.cancelAction)
                Button("Save") {
                    let port = UInt16(form.customPortStr) ?? 53
                    benchmark.addCustomTarget(name: form.customName, host: form.customHost, port: port)
                    form.showAddCustom = false
                    form.customName = ""; form.customHost = ""; form.customPortStr = "53"
                }
                .buttonStyle(.borderedProminent)
                .disabled(form.customName.isEmpty || form.customHost.isEmpty)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.ultraThinMaterial))
    }
}

// MARK: - Engine Settings Card

private struct EngineSettingsCard: View {
    @EnvironmentObject var engine: JitterKillEngine
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Toggle("Auto-activate on streaming apps", isOn: $engine.autoActivateStreamingApps).toggleStyle(.switch)
            Text("Automatically enables lockdown when any configured streaming app launches. Customize apps in the Streaming tab.")
                .font(.caption).foregroundStyle(.secondary)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Helper Service & CLI").font(.subheadline.bold())
                HStack {
                    Label(
                        engine.isDaemonInstalled ? "Helper Daemon: Active & Running ✓" : "Helper Daemon: Not Installed",
                        systemImage: engine.isDaemonInstalled ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(engine.isDaemonInstalled ? .green : .orange)

                    Spacer()

                    Button("Reinstall Helper") {
                        Task { await engine.installOrRepairHelper() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(engine.isInstallingHelper)
                }

                HStack {
                    Label(
                        engine.isCLIInstalled ? "CLI Command: /usr/local/bin/jitterkill ✓" : "CLI: Not Installed",
                        systemImage: "terminal.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Spacer()

                    Button("Save Debug Logs…") {
                        engine.exportDebugReport()
                    }
                    .controlSize(.small)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Activity Log").font(.subheadline).foregroundStyle(.secondary)
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(engine.statusLog.reversed(), id: \.self) { line in
                            Text(line)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(height: 160).padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(.ultraThickMaterial))
            }
        }
        .glassCard()
    }
}
