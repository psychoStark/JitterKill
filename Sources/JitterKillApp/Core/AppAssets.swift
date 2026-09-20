// AppAssets.swift — Centralized asset provider for JitterKill
// Provides high-resolution logo, menu bar status icons, and app icons with multi-layer fallback.

import AppKit
import SwiftUI

public enum AppAssets {

    // MARK: - Logo Images

    public static var logoImage: NSImage {
        // 1. Try Asset Catalog
        if let img = NSImage(named: "AppLogo") {
            return img
        }
        // 2. Try Bundle.main resource
        if let url = Bundle.main.url(forResource: "logo", withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            return img
        }
        // 3. Try Bundle.module resource
        #if SWIFT_PACKAGE
        if let url = Bundle.module.url(forResource: "logo", withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            return img
        }
        #endif
        // 4. Try direct file path in development
        let devPaths = [
            "Sources/JitterKillApp/Resources/logo.png",
            "logo/logo_masked.png",
            "logo/logo.png"
        ]
        for path in devPaths {
            if let img = NSImage(contentsOfFile: path) {
                return img
            }
        }
        // 5. Fallback SF symbol
        return NSImage(systemSymbolName: "bolt.shield.fill", accessibilityDescription: "JitterKill") ?? NSImage()
    }

    public static var logoSwiftUIImage: Image {
        Image(nsImage: logoImage)
    }

    // MARK: - Menu Bar Icons

    /// Monochrome guarded shield icon (active service)
    public static var menuBarGuardedImage: NSImage {
        loadTemplateMenuBarIcon(name: "MenuBarGuarded", fallbackFile: "mono_guard")
    }

    /// Monochrome unguarded shield icon (deactivated service)
    public static var menuBarUnguardedImage: NSImage {
        loadTemplateMenuBarIcon(name: "MenuBarUnguarded", fallbackFile: "mono_unguard")
    }

    private static func loadTemplateMenuBarIcon(name: String, fallbackFile: String) -> NSImage {
        var image: NSImage?

        // 1. Try Asset Catalog
        if let assetImg = NSImage(named: name) {
            image = assetImg
        }
        // 2. Try Bundle.main
        if image == nil, let url = Bundle.main.url(forResource: fallbackFile, withExtension: "png") {
            image = NSImage(contentsOf: url)
        }
        // 3. Try Bundle.module
        #if SWIFT_PACKAGE
        if image == nil, let url = Bundle.module.url(forResource: fallbackFile, withExtension: "png") {
            image = NSImage(contentsOf: url)
        }
        #endif
        // 4. Try local relative path
        if image == nil {
            let candidates = [
                "Sources/JitterKillApp/Resources/\(fallbackFile).png",
                "logo/\(fallbackFile).png"
            ]
            for p in candidates {
                if let local = NSImage(contentsOfFile: p) {
                    image = local
                    break
                }
            }
        }

        // Fallback to system symbols if missing
        if image == nil {
            let symbol = (fallbackFile == "mono_guard") ? "bolt.shield.fill" : "shield.lefthalf.filled"
            image = NSImage(systemSymbolName: symbol, accessibilityDescription: "JitterKill")
        }

        guard let finalImg = image?.copy() as? NSImage else {
            return NSImage()
        }

        // Standard macOS menu bar dimensions: 18x18 pt
        finalImg.size = NSSize(width: 18, height: 18)
        finalImg.isTemplate = true
        return finalImg
    }

    // MARK: - App Icon for Dock

    public static var appIcon: NSImage {
        if let icnsURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let img = NSImage(contentsOf: icnsURL) {
            return img
        }
        #if SWIFT_PACKAGE
        if let icnsURL = Bundle.module.url(forResource: "AppIcon", withExtension: "icns"),
           let img = NSImage(contentsOf: icnsURL) {
            return img
        }
        #endif
        return logoImage
    }
}
