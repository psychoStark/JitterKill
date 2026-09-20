// StreamingAppManager.swift — Manages game streaming app rules & priority settings
// Synchronizes with LaunchDaemon helper via /Library/Application Support/JitterKill/apps.json

import Foundation
import AppKit

@MainActor
final class StreamingAppManager: ObservableObject {
    static let shared = StreamingAppManager()

    @Published private(set) var apps: [StreamingAppRule] = []
    @Published private(set) var runningPIDsByAppId: [String: [Int32]] = [:]
    @Published private(set) var activeTriggerAppName: String? = nil

    private let primaryConfigPath = "/Library/Application Support/JitterKill/apps.json"
    private let tmpConfigPath     = "/tmp/jitterkill.apps.json"
    private let userDefaultsKey   = "com.psychostark.jitterkill.streamingAppRules"

    init() {
        loadConfig()
    }

    // MARK: - Configuration Persistence

    func loadConfig() {
        var rawRules: [StreamingAppRule]? = nil

        // 1. Try reading from /Library/Application Support/JitterKill/apps.json
        if let data = try? Data(contentsOf: URL(fileURLWithPath: primaryConfigPath)),
           let decoded = try? JSONDecoder().decode([StreamingAppRule].self, from: data),
           !decoded.isEmpty {
            rawRules = decoded
        }
        // 2. Try reading from /tmp/jitterkill.apps.json
        else if let data = try? Data(contentsOf: URL(fileURLWithPath: tmpConfigPath)),
                let decoded = try? JSONDecoder().decode([StreamingAppRule].self, from: data),
                !decoded.isEmpty {
            rawRules = decoded
        }
        // 3. Try reading from UserDefaults
        else if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
                let decoded = try? JSONDecoder().decode([StreamingAppRule].self, from: data),
                !decoded.isEmpty {
            rawRules = decoded
        }

        if let loaded = rawRules {
            // Filter loaded rules so that ONLY actually-installed built-in apps remain (plus custom apps)
            self.apps = filterAndSyncInstalled(rules: loaded)
        } else {
            // Fallback to detected installed presets
            self.apps = StreamingAppRule.defaultPresets
        }

        saveConfig()
    }

    /// Retains custom user rules and only built-in rules for apps physically installed on this Mac.
    private func filterAndSyncInstalled(rules: [StreamingAppRule]) -> [StreamingAppRule] {
        var result: [StreamingAppRule] = []

        // 1. Always retain user-added custom rules
        let customRules = rules.filter { !$0.isBuiltIn }
        result.append(contentsOf: customRules)

        // 2. Auto-detect installed built-ins
        let installedPresets = StreamingAppRule.defaultPresets
        for preset in installedPresets {
            if let existing = rules.first(where: { $0.id == preset.id }) {
                var merged = preset
                // Preserve user preference overrides
                merged.autoActivate = existing.autoActivate
                merged.boostPriority = existing.boostPriority
                result.append(merged)
            } else {
                result.append(preset)
            }
        }

        // Sort: Moonlight first, then alphabetical
        result.sort { a, b in
            if a.id == "moonlight" { return true }
            if b.id == "moonlight" { return false }
            return a.name < b.name
        }

        return result
    }

    func scanForInstalledApps() {
        self.apps = filterAndSyncInstalled(rules: self.apps)
        saveConfig()
    }

    func saveConfig() {
        guard let data = try? JSONEncoder().encode(apps) else { return }

        // Save to UserDefaults as backup
        UserDefaults.standard.set(data, forKey: userDefaultsKey)

        // Save to /tmp/jitterkill.apps.json
        try? data.write(to: URL(fileURLWithPath: tmpConfigPath), options: .atomic)
        chmod(tmpConfigPath, 0o666)

        // Save to /Library/Application Support/JitterKill/apps.json
        let dirURL = URL(fileURLWithPath: "/Library/Application Support/JitterKill")
        try? FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true, attributes: [
            .posixPermissions: 0o777
        ])
        if (try? data.write(to: URL(fileURLWithPath: primaryConfigPath), options: .atomic)) != nil {
            chmod(primaryConfigPath, 0o666)
        }
    }

    // MARK: - App Actions

    func toggleAutoActivate(id: String) {
        if let idx = apps.firstIndex(where: { $0.id == id }) {
            apps[idx].autoActivate.toggle()
            saveConfig()
        }
    }

    func toggleBoostPriority(id: String) {
        if let idx = apps.firstIndex(where: { $0.id == id }) {
            apps[idx].boostPriority.toggle()
            saveConfig()
        }
    }

    func addAppFromBundle(url: URL) {
        let bundle = Bundle(url: url)
        let name = bundle?.infoDictionary?["CFBundleDisplayName"] as? String
            ?? bundle?.infoDictionary?["CFBundleName"] as? String
            ?? url.deletingPathExtension().lastPathComponent

        let bundleId = bundle?.bundleIdentifier
        let execName = bundle?.executableURL?.lastPathComponent ?? name
        let patterns = Array(Set([name, execName])).filter { !$0.isEmpty }

        let newId = "custom_" + UUID().uuidString.prefix(8).lowercased()
        let rule = StreamingAppRule(
            id: newId,
            name: name,
            processPatterns: patterns,
            bundleIdentifier: bundleId,
            autoActivate: true,
            boostPriority: true,
            isBuiltIn: false,
            iconSystemName: "gamecontroller"
        )

        apps.append(rule)
        saveConfig()
    }

    func addCustomProcess(name: String, processPattern: String, autoActivate: Bool, boostPriority: Bool) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPat = processPattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedPat.isEmpty else { return }

        let patterns = trimmedPat.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let newId = "custom_" + UUID().uuidString.prefix(8).lowercased()
        let rule = StreamingAppRule(
            id: newId,
            name: trimmedName,
            processPatterns: patterns,
            bundleIdentifier: nil,
            autoActivate: autoActivate,
            boostPriority: boostPriority,
            isBuiltIn: false,
            iconSystemName: "gamecontroller"
        )

        apps.append(rule)
        saveConfig()
    }

    func removeApp(id: String) {
        apps.removeAll { $0.id == id }
        saveConfig()
    }

    func resetToDefaults() {
        self.apps = StreamingAppRule.defaultPresets
        saveConfig()
    }

    // MARK: - Running Process Tracking

    func updateRunningState(pidsByAppId: [String: [Int32]], triggerApp: String?) {
        self.runningPIDsByAppId = pidsByAppId
        self.activeTriggerAppName = triggerApp
    }
}
