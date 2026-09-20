// SettingsView.swift — Native macOS Settings window
// NOTE: @State is a SwiftUI macro, unavailable in CLI builds. Use @StateObject.

import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var engine: JitterKillEngine
    @EnvironmentObject var benchmark: DNSBenchmarkEngine
    @EnvironmentObject var appManager: StreamingAppManager

    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gearshape") }

            StreamingAppsSettingsTab()
                .tabItem { Label("Apps & Priority", systemImage: "gamecontroller") }

            TargetSettingsTab()
                .tabItem { Label("Targets", systemImage: "network") }

            DebugSettingsTab()
                .tabItem { Label("Debug & Helper", systemImage: "wrench.and.screwdriver") }

            AboutTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 580, height: 500)
    }
}

// MARK: - General Settings

private struct GeneralSettingsTab: View {
    @EnvironmentObject var engine: JitterKillEngine
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("probeInterval") private var probeInterval: Double = 2.0

    var body: some View {
        Form {
            Section("Behavior") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                Toggle("Auto-activate on streaming apps", isOn: $engine.autoActivateStreamingApps)
            }

            Section("Helper Service Status") {
                HStack {
                    if engine.isDaemonInstalled {
                        Label("Helper Service is INSTALLED", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("Helper Service NOT INSTALLED", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                    Spacer()
                    Button("Reinstall Helper") {
                        Task { await engine.installOrRepairHelper() }
                    }
                    .controlSize(.small)
                    .disabled(engine.isInstallingHelper)
                }

                HStack {
                    if engine.isCLIInstalled {
                        Label("CLI: /usr/local/bin/jitterkill", systemImage: "terminal.fill")
                            .foregroundStyle(.secondary)
                    } else {
                        Label("CLI not installed", systemImage: "terminal")
                            .foregroundStyle(.orange)
                    }
                }
            }

            Section("Probe Settings") {
                HStack {
                    Text("Probe interval")
                    Spacer()
                    Picker("", selection: $probeInterval) {
                        Text("1 second").tag(1.0)
                        Text("2 seconds").tag(2.0)
                        Text("5 seconds").tag(5.0)
                    }
                    .labelsHidden()
                    .frame(width: 140)
                    .onChange(of: probeInterval) { _, v in
                        LatencyEngine.shared.probeInterval = v
                    }
                }
            }

            Section("Engine") {
                HStack {
                    if engine.phase == .active {
                        Label("JitterKill is ACTIVE", systemImage: "bolt.shield.fill").foregroundStyle(.green)
                    } else if engine.phase == .activating {
                        Label("Activating JitterKill…", systemImage: "arrow.triangle.2.circlepath").foregroundStyle(.orange)
                    } else if engine.phase == .deactivating {
                        Label("Deactivating JitterKill…", systemImage: "arrow.triangle.2.circlepath").foregroundStyle(.orange)
                    } else {
                        Label("JitterKill is INACTIVE", systemImage: "shield.lefthalf.filled").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        Task { await engine.toggle() }
                    } label: {
                        HStack(spacing: 6) {
                            switch engine.phase {
                            case .activating:
                                ProgressView().controlSize(.small)
                                Text("Activating…")
                            case .deactivating:
                                ProgressView().controlSize(.small)
                                Text("Deactivating…")
                            case .active:
                                Text("Deactivate")
                            case .idle:
                                Text("Activate")
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(engine.phase == .active ? .red : (engine.phase == .idle ? .green : .secondary))
                    .disabled(engine.phase == .activating || engine.phase == .deactivating)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Streaming Apps & Priority Settings

private struct StreamingAppsSettingsTab: View {
    @EnvironmentObject var appManager: StreamingAppManager
    @StateObject private var formState = AddProcessFormState()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Game Streaming Apps & Priority").font(.headline)
                    Text("Apps with Auto-Lockdown trigger JitterKill. Apps with Real-Time receive -20 scheduling priority.")
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
            .padding(.horizontal)
            .padding(.top, 12)

            List {
                ForEach(appManager.apps) { rule in
                    let runningPIDs = appManager.runningPIDsByAppId[rule.id] ?? []
                    let isRunning = !runningPIDs.isEmpty

                    HStack(spacing: 12) {
                        Image(systemName: rule.iconSystemName ?? "gamecontroller")
                            .font(.title3)
                            .foregroundStyle(isRunning ? .green : .secondary)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(rule.name).font(.subheadline.weight(.medium))
                                if isRunning {
                                    Text("Running")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.green)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1.5)
                                        .background(Capsule().fill(Color.green.opacity(0.15)))
                                }
                                if !rule.isBuiltIn {
                                    Text("Custom")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundStyle(.teal)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Capsule().fill(Color.teal.opacity(0.12)))
                                }
                            }
                            if rule.id == "tailscale" {
                                Text(isRunning ? "Connected (Mesh Active)" : "Active connection required • Standby")
                                    .font(.caption2).foregroundStyle(isRunning ? .green : .secondary)
                            } else {
                                Text(rule.processPatterns.joined(separator: ", "))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        Toggle("Auto-Lockdown", isOn: Binding(
                            get: { rule.autoActivate },
                            set: { _ in appManager.toggleAutoActivate(id: rule.id) }
                        ))
                        .controlSize(.mini)

                        Toggle("Real-Time 🚀", isOn: Binding(
                            get: { rule.boostPriority },
                            set: { _ in appManager.toggleBoostPriority(id: rule.id) }
                        ))
                        .controlSize(.mini)

                        Button {
                            appManager.removeApp(id: rule.id)
                        } label: {
                            Image(systemName: "trash").foregroundStyle(.red.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                        .controlSize(.small)
                        .help("Remove rule")
                    }
                    .padding(.vertical, 3)
                }
            }
            .listStyle(.inset)
        }
        .sheet(isPresented: $formState.showSheet) {
            AddProcessSheetSettings(formState: formState)
        }
    }

    private func pickApplication() {
        let panel = NSOpenPanel()
        panel.title = "Select Application"
        panel.prompt = "Add App"
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

private struct AddProcessSheetSettings: View {
    @ObservedObject var formState: AddProcessFormState
    @EnvironmentObject var appManager: StreamingAppManager

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Custom Process").font(.headline)
            VStack(alignment: .leading, spacing: 10) {
                TextField("Display Name (e.g. Cemu)", text: $formState.appName)
                    .textFieldStyle(.roundedBorder)
                TextField("Process Name (e.g. Cemu)", text: $formState.processPattern)
                    .textFieldStyle(.roundedBorder)
                Toggle("Auto-activate on launch", isOn: $formState.autoActivate)
                Toggle("Elevate to Real-Time (-20)", isOn: $formState.boostPriority)
            }
            HStack {
                Spacer()
                Button("Cancel") { formState.reset() }.keyboardShortcut(.cancelAction)
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
                .disabled(formState.appName.isEmpty || formState.processPattern.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}

// MARK: - Target Settings

private struct TargetSettingsTab: View {
    @EnvironmentObject var benchmark: DNSBenchmarkEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Ping Targets").font(.headline).padding(.horizontal)

            List {
                if benchmark.targets.contains(where: { $0.isCustom }) {
                    Section("Custom Targets") {
                        ForEach(benchmark.targets.filter { $0.isCustom }) { target in
                            targetRow(target)
                        }
                    }
                }

                Section("DNS Resolvers") {
                    ForEach(benchmark.targets.filter { $0.category == .dns && !$0.isCustom }) { target in
                        targetRow(target)
                    }
                }

                Section("Game APIs & Services") {
                    ForEach(benchmark.targets.filter { $0.category == .gamingApi }) { target in
                        targetRow(target)
                    }
                }

                Section("GeForce NOW Edge Servers") {
                    ForEach(benchmark.targets.filter { $0.category == .geforceNow }) { target in
                        targetRow(target)
                    }
                }
            }
            .listStyle(.sidebar)

            HStack {
                Spacer()
                Button("Auto-Detect Fastest DNS") { benchmark.runAutoDetect() }
                    .buttonStyle(.borderedProminent).tint(.teal).padding(.horizontal)
            }
            .padding(.bottom)
        }
    }

    @ViewBuilder
    private func targetRow(_ target: PingTarget) -> some View {
        HStack {
            Image(systemName: target.category.iconSystemName)
                .font(.callout)
                .foregroundStyle(benchmark.selectedTarget.id == target.id ? .green : .secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(target.name).font(.subheadline)
                Text(target.displayAddress).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if benchmark.selectedTarget.id == target.id {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.teal)
            }
            if let avg = target.averageMs {
                Text(String(format: "%.0f ms", avg)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            if target.isCustom {
                Button(role: .destructive) {
                    benchmark.removeCustomTarget(id: target.id)
                } label: {
                    Image(systemName: "trash").foregroundStyle(.red.opacity(0.8))
                }
                .buttonStyle(.plain)
                .padding(.leading, 6)
                .help("Remove custom target")
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { benchmark.selectTarget(target) }
    }
}

// MARK: - Debug & Helper Settings

final class DebugTabState: ObservableObject {
    @Published var logOutput: String = ""
    @Published var statusContent: String = ""
    @Published var controlContent: String = ""
}

private struct DebugSettingsTab: View {
    @EnvironmentObject var engine: JitterKillEngine
    @EnvironmentObject var monitor: NetworkStatusMonitor
    @StateObject private var state = DebugTabState()

    var body: some View {
        Form {
            Section("Helper Service & CLI") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Service: com.psychostark.jitterkill.helper").font(.subheadline.bold())
                        Text(engine.isDaemonInstalled ? "Status: Installed & Running ✓" : "Status: Not Installed")
                            .font(.caption)
                            .foregroundStyle(engine.isDaemonInstalled ? .green : .orange)
                    }
                    Spacer()
                    Button("Reinstall Helper") {
                        Task {
                            await engine.installOrRepairHelper()
                            refresh()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(engine.isInstallingHelper)
                }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("CLI: /usr/local/bin/jitterkill").font(.subheadline.bold())
                        Text(engine.isCLIInstalled ? "Command available in Terminal without sudo ✓" : "CLI tool not installed")
                            .font(.caption)
                            .foregroundStyle(engine.isCLIInstalled ? .green : .orange)
                    }
                    Spacer()
                    Button("Reset Auto Mode") {
                        engine.restoreAutoMode()
                        refresh()
                    }
                    .controlSize(.small)
                }

                HStack {
                    Button("Uninstall Helper & CLI", role: .destructive) {
                        Task {
                            _ = await engine.uninstallHelper()
                            refresh()
                        }
                    }
                    .controlSize(.small)
                    Spacer()
                }
            }

            Section("Diagnostic Logs & Troubleshooting") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Export complete system state, network interface configuration, kernel settings, and helper logs to diagnose any issue.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button(action: { engine.exportDebugReport() }) {
                        Label("Save Full Debug Report to File…", systemImage: "arrow.down.doc.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                }
            }

            Section("IPC Status (/tmp/jitterkill.status)") {
                Text(state.statusContent.isEmpty ? "No status file detected" : state.statusContent)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Section("Helper Log (/var/log/jitterkill-helper.log)") {
                VStack(alignment: .leading, spacing: 6) {
                    ScrollView {
                        Text(state.logOutput.isEmpty ? "No log output available" : state.logOutput)
                            .font(.system(.caption2, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(6)
                    }
                    .frame(height: 110)
                    .background(RoundedRectangle(cornerRadius: 6).fill(.ultraThickMaterial))

                    HStack {
                        Spacer()
                        Button("Refresh Log") {
                            refresh()
                        }
                        .controlSize(.small)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            refresh()
        }
    }

    private func refresh() {
        state.logOutput = engine.readHelperLog()
        state.statusContent = engine.readDaemonStatusJSON()
        state.controlContent = engine.readControlFile()
    }
}

// MARK: - About

private struct AboutTab: View {
    var body: some View {
        VStack(spacing: 16) {
            AppAssets.logoSwiftUIImage
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 80, height: 80)
                .shadow(color: .green.opacity(0.3), radius: 8, y: 2)
            Text("JitterKill").font(.largeTitle.bold())
            Text("Version 1.0.0").font(.subheadline).foregroundStyle(.secondary)
            Text("Ultra-lightweight macOS game streaming optimizer.\nEliminates Wi-Fi jitter from AWDL, LLW, and NAN interfaces.\nIncludes native terminal CLI & menu bar companion.")
                .multilineTextAlignment(.center)
                .font(.body)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
