import AppKit
import SwiftUI
import Combine

class MenuBarManager: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let pipeline: FlowXPipeline
    private let settingsManager: SettingsManager
    private let profileManager: ProfileManager
    var updateChecker: UpdateChecker?
    private var cancellables = Set<AnyCancellable>()
    private var profileSubmenu: NSMenu!

    // Animation properties
    private var animationTimer: Timer?
    private var animationFrame = 0

    init(pipeline: FlowXPipeline, settingsManager: SettingsManager, profileManager: ProfileManager) {
        self.pipeline = pipeline
        self.settingsManager = settingsManager
        self.profileManager = profileManager
        super.init()
        setupMenuBar()
        setupStateObserver()
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: 28)

        if let button = statusItem.button {
            let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
            button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "FlowX")?.withSymbolConfiguration(config)
        }

        let menu = NSMenu()

        let statusMenuItem = NSMenuItem(title: "FlowX — Ready", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        menu.addItem(NSMenuItem.separator())

        // Profiles
        let profileMenuItem = NSMenuItem(title: "Profiles", action: nil, keyEquivalent: "")
        profileMenuItem.image = NSImage(systemSymbolName: "person.2", accessibilityDescription: nil)
        profileSubmenu = NSMenu()
        profileSubmenu.delegate = self
        buildProfileSubmenu(profileSubmenu)
        profileMenuItem.submenu = profileSubmenu
        menu.addItem(profileMenuItem)

        // History
        let historyItem = NSMenuItem(title: "History", action: #selector(openHistory), keyEquivalent: "h")
        historyItem.image = NSImage(systemSymbolName: "clock", accessibilityDescription: nil)
        historyItem.target = self
        menu.addItem(historyItem)

        menu.addItem(NSMenuItem.separator())

        // Auto-copy toggle
        let autoCopyItem = NSMenuItem(title: "Auto-Copy to Clipboard", action: #selector(toggleAutoCopy(_:)), keyEquivalent: "")
        autoCopyItem.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: nil)
        autoCopyItem.target = self
        autoCopyItem.state = settingsManager.autoCopyToClipboard ? .on : .off
        menu.addItem(autoCopyItem)

        menu.addItem(NSMenuItem.separator())

        // Show FlowX
        let showWindowItem = NSMenuItem(title: "Show FlowX", action: #selector(showMainWindow), keyEquivalent: "o")
        showWindowItem.image = NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)
        showWindowItem.target = self
        menu.addItem(showWindowItem)

        // Settings
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.image = NSImage(systemSymbolName: "gear", accessibilityDescription: nil)
        settingsItem.target = self
        menu.addItem(settingsItem)

        // Check for Updates
        let updateItem = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        updateItem.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil)
        updateItem.target = self
        menu.addItem(updateItem)

        // About
        let aboutItem = NSMenuItem(title: "About FlowX", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(title: "Quit FlowX", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }
    
    private func setupStateObserver() {
        pipeline.pipelineState?.$status
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                self?.handleStatusChange(status)
            }
            .store(in: &cancellables)
    }
    
    private func handleStatusChange(_ status: PipelineStatus) {
        animationTimer?.invalidate()
        animationFrame = 0
        updateStatus(status.rawValue)
        
        guard let button = statusItem.button else { return }
        
        switch status {
        case .idle:
            button.contentTintColor = nil
            setSymbol("waveform")
            
            // Show a brief checkmark if we just finished processing
            if pipeline.pipelineState?.lastResult != nil {
                button.contentTintColor = .systemGreen
                setSymbol("checkmark")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                    if self?.pipeline.pipelineState?.status == .idle {
                        button.contentTintColor = nil
                        self?.setSymbol("waveform")
                    }
                }
            }
            
        case .recording:
            button.contentTintColor = .systemRed
            setSymbol("mic.fill")
            // Smooth pulse animation
            animationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                self.animationFrame += 1
                let alpha = 0.5 + 0.5 * sin(Double(self.animationFrame) * 0.2)
                button.alphaValue = CGFloat(alpha)
            }
            
        case .processing:
            button.alphaValue = 1.0
            button.contentTintColor = .systemBlue
            // Spin animation
            let frames = ["arrow.2.circlepath", "arrow.3.trianglepath"]
            setSymbol(frames[0])
            animationTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                self.animationFrame += 1
                self.setSymbol(frames[self.animationFrame % 2])
            }
            
        case .error:
            button.alphaValue = 1.0
            button.contentTintColor = .systemOrange
            setSymbol("exclamationmark.triangle.fill")
        }
        
        if status != .recording {
            button.alphaValue = 1.0
        }
    }
    
    private func setSymbol(_ name: String) {
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        statusItem.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: "FlowX")?.withSymbolConfiguration(config)
    }

    func menuWillOpen(_ menu: NSMenu) {
        if menu == profileSubmenu {
            menu.removeAllItems()
            buildProfileSubmenu(menu)
        }
    }

    private func buildProfileSubmenu(_ menu: NSMenu) {
        let profiles = profileManager.profiles
        let activeId = profileManager.activeProfileId
        if profiles.isEmpty {
            let noProfiles = NSMenuItem(title: "No profiles configured", action: nil, keyEquivalent: "")
            noProfiles.isEnabled = false
            menu.addItem(noProfiles)
        } else {
            for profile in profiles {
                let item = NSMenuItem(title: profile.name, action: #selector(selectProfile(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = profile.id.uuidString
                item.state = (profile.id == activeId) ? .on : .off
                menu.addItem(item)
            }
        }
    }

    @objc private func selectProfile(_ sender: NSMenuItem) {
        guard let idString = sender.representedObject as? String,
              let uuid = UUID(uuidString: idString) else { return }
        profileManager.activeProfileId = uuid
        setupMenuBar()
    }

    @objc private func showMainWindow() {
        if let window = NSApp.windows.first(where: { $0.title == "FlowX" }) {
            window.makeKeyAndOrderFront(nil)
        } else if let url = URL(string: "flowx://main") {
            NSWorkspace.shared.open(url)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openHistory() {
        showMainWindow()
        NotificationCenter.default.post(name: .flowxNavigateToHistory, object: nil)
    }

    @objc private func toggleAutoCopy(_ sender: NSMenuItem) {
        settingsManager.autoCopyToClipboard.toggle()
        sender.state = settingsManager.autoCopyToClipboard ? .on : .off
    }

    @objc private func openSettings() {
        showMainWindow()
        NotificationCenter.default.post(name: .flowxNavigateToSettings, object: nil)
    }

    @objc private func checkForUpdates() {
        updateChecker?.checkForUpdates()
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "FlowX"
        alert.informativeText = "Version 1.0\n\nAI-powered voice dictation for macOS."
        alert.alertStyle = .informational
        alert.runModal()
    }

    @objc private func quitApp() { NSApp.terminate(nil) }

    // Left for backwards compatibility if Pipeline calls it directly
    func updateStatus(_ text: String) {
        if let menu = statusItem.menu, let firstItem = menu.items.first {
            firstItem.title = "FlowX — \(text)"
        }
    }
    func setRecordingIndicator(_ recording: Bool) { /* Stubbed: Handled by StateObserver now */ }
}
