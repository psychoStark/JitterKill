// MenuBarController.swift — NSStatusItem + Popover controller
// Manages the clean menu bar icon with dynamic state indicator and popover.

import AppKit
import SwiftUI
import Combine

@MainActor
final class MenuBarController: NSObject {

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var dashboardWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    override init() {
        super.init()
        setupStatusItem()
        setupPopover()
        observeEngineState()
    }

    // MARK: - Status Item Setup

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateIcon(isActive: false)
        if let button = statusItem.button {
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.target = self
        }
    }

    private func updateIcon(isActive: Bool, isWarning: Bool = false) {
        guard let button = statusItem.button else { return }
        let img = isActive
            ? AppAssets.menuBarGuardedImage
            : AppAssets.menuBarUnguardedImage
        button.image = img
        button.needsDisplay = true
        button.toolTip = isActive ? "JitterKill Active (Guarded) — Click to open" : "JitterKill Standby (Unguarded) — Click to open"
    }

    // MARK: - Popover Setup

    private func setupPopover() {
        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(
            rootView: MenuBarPopoverView(openDashboard: { [weak self] in
                self?.openDashboard()
                self?.closePopover()
            })
            .environmentObject(LatencyEngine.shared)
            .environmentObject(JitterKillEngine.shared)
            .environmentObject(NetworkStatusMonitor.shared)
            .environmentObject(StreamingAppManager.shared)
        )
        popover.contentSize = NSSize(width: 320, height: 420)
    }

    // MARK: - Actions

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        if popover.isShown {
            closePopover()
        } else {
            if let button = statusItem.button {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                popover.contentViewController?.view.window?.makeKey()
            }
        }
    }

    private func closePopover() {
        popover.performClose(nil)
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open Dashboard", action: #selector(openDashboardMenu), keyEquivalent: "d"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit JitterKill", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func openDashboardMenu() { openDashboard() }

    private var settingsWindow: NSWindow?

    @objc func openSettings() {
        NSApp.setActivationPolicy(.regular)
        if let win = settingsWindow {
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hostingView = NSHostingView(
            rootView: SettingsView()
                .environmentObject(JitterKillEngine.shared)
                .environmentObject(DNSBenchmarkEngine.shared)
                .environmentObject(LatencyEngine.shared)
                .environmentObject(StreamingAppManager.shared)
                .environmentObject(NetworkStatusMonitor.shared)
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 540),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "JitterKill Settings"
        window.contentView = hostingView
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }

    // MARK: - Dashboard Window

    func openDashboard() {
        NSApp.setActivationPolicy(.regular)
        if let win = dashboardWindow {
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hostingView = NSHostingView(
            rootView: DashboardView()
                .environmentObject(LatencyEngine.shared)
                .environmentObject(JitterKillEngine.shared)
                .environmentObject(NetworkStatusMonitor.shared)
                .environmentObject(DNSBenchmarkEngine.shared)
                .environmentObject(StreamingAppManager.shared)
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "JitterKill"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.contentView = hostingView
        window.center()
        window.minSize = NSSize(width: 760, height: 580)
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        dashboardWindow = window
    }

    // MARK: - State Observation

    private func observeEngineState() {
        // 1. Combine subscription to JitterKillEngine.shared.$isActive
        JitterKillEngine.shared.$isActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self] active in
                let isWarning = NetworkStatusMonitor.shared.streamingMode.isWarning
                self?.updateIcon(isActive: active, isWarning: isWarning)
            }
            .store(in: &cancellables)

        // 2. Combine subscription to JitterKillEngine.shared.$phase
        JitterKillEngine.shared.$phase
            .receive(on: DispatchQueue.main)
            .sink { [weak self] phase in
                let active = (phase == .active) || JitterKillEngine.shared.isActive
                let isWarning = NetworkStatusMonitor.shared.streamingMode.isWarning
                self?.updateIcon(isActive: active, isWarning: isWarning)
            }
            .store(in: &cancellables)

        // 3. NotificationCenter subscription
        NotificationCenter.default.publisher(for: .jitterKillStateChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                let isActive = JitterKillEngine.shared.isActive
                let isWarning = NetworkStatusMonitor.shared.streamingMode.isWarning
                self?.updateIcon(isActive: isActive, isWarning: isWarning)
            }
            .store(in: &cancellables)
    }
}

extension Notification.Name {
    static let jitterKillStateChanged = Notification.Name("jitterKillStateChanged")
}
