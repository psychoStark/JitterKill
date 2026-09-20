// JitterKillApp.swift — Main entry point
// Full native macOS application with Dock icon, Application Menu Bar, and Menu Bar companion item.
// Opens a Liquid Glass native Dashboard window on launch, Dock click, or menu bar click.

import SwiftUI
import AppKit
import UserNotifications

@main
struct JitterKillApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

// MARK: - App Delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    static weak var shared: AppDelegate?
    var menuBarController: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        NSApp.setActivationPolicy(.regular)
        NSApp.applicationIconImage = AppAssets.appIcon

        // Setup standard application Menu Bar
        setupMainMenu()

        // Request notification permission
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }

        // Activate menu bar item
        menuBarController = MenuBarController()

        // Start background engines
        Task { @MainActor in
            NetworkStatusMonitor.shared.start()
            LatencyEngine.shared.start()
            JitterKillEngine.shared.startAutoWatch()

            // Open Dashboard window on launch
            self.menuBarController?.openDashboard()

            // Check if helper service is installed
            JitterKillEngine.shared.checkAndPromptHelperInstallOnLaunch()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        menuBarController?.openDashboard()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false // Stay alive in Dock and Menu Bar
    }

    func applicationWillTerminate(_ notification: Notification) {
        Task { @MainActor in
            if JitterKillEngine.shared.isActive {
                await JitterKillEngine.shared.deactivate()
            }
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        return [.banner, .sound]
    }

    // MARK: - Native Application Menu Bar

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // 1. JitterKill App Menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "JitterKill")
        appMenu.addItem(NSMenuItem(title: "About JitterKill", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(title: "Preferences…", action: #selector(openPreferences), keyEquivalent: ","))
        appMenu.addItem(NSMenuItem.separator())

        let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu(title: "Services")
        servicesItem.submenu = servicesMenu
        NSApp.servicesMenu = servicesMenu
        appMenu.addItem(servicesItem)
        appMenu.addItem(NSMenuItem.separator())

        appMenu.addItem(NSMenuItem(title: "Hide JitterKill", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        let hideOthers = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(NSMenuItem(title: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: ""))
        appMenu.addItem(NSMenuItem.separator())

        appMenu.addItem(NSMenuItem(title: "Quit JitterKill", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // 2. File Menu
        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(NSMenuItem(title: "Open Dashboard", action: #selector(openDashboardAction), keyEquivalent: "d"))
        fileMenu.addItem(NSMenuItem(title: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        // 3. Optimization Menu
        let optMenuItem = NSMenuItem()
        let optMenu = NSMenu(title: "Optimization")
        optMenu.addItem(NSMenuItem(title: "Activate Lockdown", action: #selector(activateLockdownAction), keyEquivalent: "o"))
        let deactItem = NSMenuItem(title: "Deactivate Lockdown", action: #selector(deactivateLockdownAction), keyEquivalent: "o")
        deactItem.keyEquivalentModifierMask = [.command, .shift]
        optMenu.addItem(deactItem)
        optMenu.addItem(NSMenuItem(title: "Auto-Detection Mode", action: #selector(autoModeAction), keyEquivalent: "a"))
        optMenu.addItem(NSMenuItem.separator())
        optMenu.addItem(NSMenuItem(title: "Scan Installed Streaming Apps", action: #selector(scanAppsAction), keyEquivalent: "r"))
        optMenuItem.submenu = optMenu
        mainMenu.addItem(optMenuItem)

        // 4. Window Menu
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(NSMenuItem(title: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        windowMenu.addItem(NSMenuItem(title: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: ""))
        windowMenu.addItem(NSMenuItem.separator())
        windowMenu.addItem(NSMenuItem(title: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: ""))
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)
        NSApp.windowsMenu = windowMenu

        // 5. Help Menu
        let helpMenuItem = NSMenuItem()
        let helpMenu = NSMenu(title: "Help")
        helpMenu.addItem(NSMenuItem(title: "JitterKill Documentation", action: #selector(openDocsAction), keyEquivalent: "?"))
        helpMenuItem.submenu = helpMenu
        mainMenu.addItem(helpMenuItem)

        NSApp.mainMenu = mainMenu
    }

    @objc private func openDashboardAction() {
        menuBarController?.openDashboard()
    }

    @objc func openPreferences() {
        menuBarController?.openSettings()
    }

    @objc private func activateLockdownAction() {
        Task { await JitterKillEngine.shared.activate() }
    }

    @objc private func deactivateLockdownAction() {
        Task { await JitterKillEngine.shared.deactivate() }
    }

    @objc private func autoModeAction() {
        JitterKillEngine.shared.restoreAutoMode()
    }

    @objc private func scanAppsAction() {
        StreamingAppManager.shared.scanForInstalledApps()
    }

    @objc private func openDocsAction() {
        if let url = URL(string: "https://github.com/psychostark/JitterKill#readme") {
            NSWorkspace.shared.open(url)
        }
    }
}
