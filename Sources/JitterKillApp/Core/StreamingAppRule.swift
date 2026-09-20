// StreamingAppRule.swift — Game streaming application configuration rule
// Defines auto-activation triggers, kernel priority boosting rules, and installed app detection.

import Foundation
import AppKit

public struct StreamingAppRule: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var processPatterns: [String]
    public var bundleIdentifier: String?
    public var autoActivate: Bool
    public var boostPriority: Bool
    public var isBuiltIn: Bool
    public var iconSystemName: String?

    public init(
        id: String,
        name: String,
        processPatterns: [String],
        bundleIdentifier: String? = nil,
        autoActivate: Bool = true,
        boostPriority: Bool = true,
        isBuiltIn: Bool = false,
        iconSystemName: String? = nil
    ) {
        self.id = id
        self.name = name
        self.processPatterns = processPatterns
        self.bundleIdentifier = bundleIdentifier
        self.autoActivate = autoActivate
        self.boostPriority = boostPriority
        self.isBuiltIn = isBuiltIn
        self.iconSystemName = iconSystemName
    }
}

extension StreamingAppRule {
    /// Comprehensive catalog of supported game streaming apps and tools on macOS.
    public static let supportedCatalog: [StreamingAppRule] = [
        StreamingAppRule(
            id: "moonlight",
            name: "Moonlight",
            processPatterns: ["Moonlight", "Moonlight Legacy", "Moonlight V+"],
            bundleIdentifier: "com.moonlight-stream.Moonlight",
            autoActivate: true,
            boostPriority: true,
            isBuiltIn: true,
            iconSystemName: "gamecontroller.fill"
        ),
        StreamingAppRule(
            id: "geforcenow",
            name: "GeForce NOW",
            processPatterns: ["GeForceNOW", "GeForce NOW", "GeForceNOWStreamer"],
            bundleIdentifier: "com.nvidia.gfnpc.mall",
            autoActivate: true,
            boostPriority: true,
            isBuiltIn: true,
            iconSystemName: "play.tv.fill"
        ),
        StreamingAppRule(
            id: "parsec",
            name: "Parsec",
            processPatterns: ["Parsec"],
            bundleIdentifier: "com.parsec.client",
            autoActivate: true,
            boostPriority: true,
            isBuiltIn: true,
            iconSystemName: "display.2"
        ),
        StreamingAppRule(
            id: "steam",
            name: "Steam / Steam Link",
            processPatterns: ["streaming_client", "Steam Link", "steam_osx", "steam"],
            bundleIdentifier: "com.valvesoftware.steam",
            autoActivate: true,
            boostPriority: true,
            isBuiltIn: true,
            iconSystemName: "gamecontroller"
        ),
        StreamingAppRule(
            id: "psremoteplay",
            name: "PS Remote Play",
            processPatterns: ["RemotePlay", "PS Remote Play"],
            bundleIdentifier: "com.playstation.RemotePlay",
            autoActivate: true,
            boostPriority: true,
            isBuiltIn: true,
            iconSystemName: "gamecontroller.fill"
        ),
        StreamingAppRule(
            id: "chiaki",
            name: "Chiaki / Chiaki-ng",
            processPatterns: ["chiaki", "chiaki-ng", "Chiaki", "Chiaki-ng"],
            bundleIdentifier: "com.stream.chiaki",
            autoActivate: true,
            boostPriority: true,
            isBuiltIn: true,
            iconSystemName: "gamecontroller"
        ),
        StreamingAppRule(
            id: "xbox",
            name: "Xbox Cloud Gaming",
            processPatterns: ["Xbox Cloud Gaming", "Better xCloud", "Xbox"],
            bundleIdentifier: "com.microsoft.xbox",
            autoActivate: true,
            boostPriority: true,
            isBuiltIn: true,
            iconSystemName: "gamecontroller"
        ),
        StreamingAppRule(
            id: "shadow",
            name: "Shadow PC",
            processPatterns: ["Shadow", "ShadowPC"],
            bundleIdentifier: "com.blade.shadow",
            autoActivate: true,
            boostPriority: true,
            isBuiltIn: true,
            iconSystemName: "pc"
        ),
        StreamingAppRule(
            id: "luna",
            name: "Amazon Luna",
            processPatterns: ["Amazon Luna", "Luna"],
            bundleIdentifier: "com.amazon.luna",
            autoActivate: true,
            boostPriority: true,
            isBuiltIn: true,
            iconSystemName: "moon.stars.fill"
        ),
        StreamingAppRule(
            id: "sunshine",
            name: "Sunshine Server",
            processPatterns: ["sunshine", "Sunshine"],
            bundleIdentifier: nil,
            autoActivate: true,
            boostPriority: true,
            isBuiltIn: true,
            iconSystemName: "sun.max.fill"
        ),
        StreamingAppRule(
            id: "tailscale",
            name: "Tailscale (Mesh VPN)",
            processPatterns: ["tailscaled", "Tailscale", "IPNExtension"],
            bundleIdentifier: "io.tailscale.ipn.macos",
            autoActivate: false,
            boostPriority: true,
            isBuiltIn: true,
            iconSystemName: "shield.lefthalf.filled"
        )
    ]

    /// Checks if a streaming app rule is physically installed on this Mac.
    public static func isAppInstalled(_ rule: StreamingAppRule) -> Bool {
        // 1. LaunchServices bundle identifier check
        if let bid = rule.bundleIdentifier {
            if NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) != nil {
                return true
            }
            // Tailscale bundle ID fallback
            if rule.id == "tailscale" {
                if NSWorkspace.shared.urlForApplication(withBundleIdentifier: "io.tailscale.ipn.mac") != nil {
                    return true
                }
            }
        }

        // 2. Direct application file checks
        let home = NSHomeDirectory()
        let fm = FileManager.default

        // App-specific candidate paths
        var pathsToCheck: [String] = [
            "/Applications/\(rule.name).app",
            "\(home)/Applications/\(rule.name).app"
        ]

        if rule.id == "moonlight" {
            pathsToCheck.append(contentsOf: [
                "/Applications/Moonlight.app",
                "/Applications/Moonlight Legacy.app",
                "/Applications/Moonlight V+.app",
                "\(home)/Applications/Moonlight.app"
            ])
        } else if rule.id == "tailscale" {
            pathsToCheck.append("/Applications/Tailscale.app")
            pathsToCheck.append("\(home)/Applications/Tailscale.app")
        } else if rule.id == "sunshine" {
            pathsToCheck.append(contentsOf: [
                "/opt/homebrew/bin/sunshine",
                "/usr/local/bin/sunshine",
                "/usr/bin/sunshine"
            ])
        } else if rule.id == "geforcenow" {
            pathsToCheck.append("/Applications/GeForceNOW.app")
        } else if rule.id == "steam" {
            pathsToCheck.append("/Applications/Steam.app")
        } else if rule.id == "chiaki" {
            pathsToCheck.append(contentsOf: [
                "/Applications/Chiaki.app",
                "/Applications/Chiaki-ng.app"
            ])
        } else if rule.id == "psremoteplay" {
            pathsToCheck.append("/Applications/PS Remote Play.app")
            pathsToCheck.append("/Applications/RemotePlay.app")
        } else if rule.id == "shadow" {
            pathsToCheck.append("/Applications/Shadow.app")
            pathsToCheck.append("/Applications/Shadow PC.app")
        }

        for path in pathsToCheck {
            if fm.fileExists(atPath: path) {
                return true
            }
        }

        return false
    }

    /// Default presets returned to the user: ONLY apps that are auto-detected as installed on the Mac!
    public static var defaultPresets: [StreamingAppRule] {
        let installed = supportedCatalog.filter { isAppInstalled($0) }
        // Fallback: If no streaming apps found at all, include Moonlight as a template
        return installed.isEmpty ? [supportedCatalog[0]] : installed
    }
}

// MARK: - Shared Add Process Form State

public final class AddProcessFormState: ObservableObject {
    @Published public var showSheet: Bool = false
    @Published public var appName: String = ""
    @Published public var processPattern: String = ""
    @Published public var autoActivate: Bool = true
    @Published public var boostPriority: Bool = true

    public init() {}

    public func reset() {
        showSheet = false
        appName = ""
        processPattern = ""
        autoActivate = true
        boostPriority = true
    }
}
