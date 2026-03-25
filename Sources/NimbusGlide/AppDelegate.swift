import AppKit
import SwiftUI
import AVFoundation
import Combine

class AppDelegate: NSObject, NSApplicationDelegate {
    var menuBarManager: MenuBarManager!
    var audioRecorder: AudioRecorder!
    var hotkeyManager: HotkeyManager!
    var appTracker: AppTracker!
    var keystrokeSimulator: KeystrokeSimulator!
    var aiService: AIService!
    let profileManager = ProfileManager()
    let memoryManager = MemoryManager()
    let settingsManager = SettingsManager()
    let pipelineState = PipelineState()
    let updateChecker = UpdateChecker()
    let usageTracker = UsageTracker()
    let authManager = AuthManager()
    var apiClient: APIClient!
    var pipeline: NimbusGlidePipeline!
    var statusIndicator: StatusIndicatorPanel!

    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Migrate plaintext token files to Keychain (one-time, from pre-1.1 builds)
        KeychainHelper.migrateFromFilesIfNeeded()

        PermissionsManager.requestMicrophoneAccess { [weak self] granted in
            DispatchQueue.main.async {
                self?.pipelineState.isMicrophoneAuthorized = granted
            }
            if !granted {
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "Microphone Access Required"
                    alert.informativeText = "NimbusGlide needs microphone access to record audio for transcription. Please grant access in System Settings > Privacy & Security > Microphone."
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "Open Settings")
                    alert.addButton(withTitle: "OK")
                    if alert.runModal() == .alertFirstButtonReturn {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
                    }
                }
            }
        }

        PermissionsManager.checkAccessibilityAccess()

        // Auth + API client
        apiClient = APIClient(authManager: authManager)
        authManager.restoreSession()

        // Sync auth state to pipeline
        authManager.$isAuthenticated
            .receive(on: RunLoop.main)
            .sink { [weak self] authenticated in
                self?.pipelineState.isAuthenticated = authenticated
            }
            .store(in: &cancellables)

        appTracker = AppTracker()
        keystrokeSimulator = KeystrokeSimulator()
        audioRecorder = AudioRecorder()
        audioRecorder.cleanupStaleRecordings()
        audioRecorder.onMaxDurationReached = { [weak self] in
            self?.pipeline.stopRecordingAndProcess()
        }
        aiService = AIService(settingsManager: settingsManager, apiClient: apiClient)
        aiService.usageTracker = usageTracker

        pipeline = NimbusGlidePipeline(
            audioRecorder: audioRecorder,
            aiService: aiService,
            appTracker: appTracker,
            keystrokeSimulator: keystrokeSimulator,
            profileManager: profileManager,
            memoryManager: memoryManager
        )

        menuBarManager = MenuBarManager(pipeline: pipeline, settingsManager: settingsManager, profileManager: profileManager)
        menuBarManager.updateChecker = updateChecker
        pipeline.menuBarManager = menuBarManager
        pipeline.pipelineState = pipelineState
        pipeline.settingsManager = settingsManager

        // Wire toggle recording closure for the UI record button
        pipelineState.onToggleRecording = { [weak self] in
            self?.pipeline.toggleRecording()
        }

        // Auth state is synced via Combine publisher above
        pipelineState.isAuthenticated = authManager.isAuthenticated

        // Sync usage from server on sign-in
        authManager.$isAuthenticated
            .filter { $0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                Task {
                    if let status = try? await self.apiClient.getUserStatus() {
                        await MainActor.run {
                            self.usageTracker.syncFromServer(status)
                        }
                    }
                }
            }
            .store(in: &cancellables)

        pipelineState.refreshPermissions()
        pipelineState.startMonitoringPermissions()

        // Floating status indicator
        statusIndicator = StatusIndicatorPanel()
        statusIndicator.bind(to: pipelineState)

        hotkeyManager = HotkeyManager(
            hotkey: settingsManager.hotkey,
            onKeyDown: { [weak self] in
                self?.pipeline.startRecording()
            },
            onKeyUp: { [weak self] in
                self?.pipeline.stopRecordingAndProcess()
            }
        )

        // Sync hotkey choice changes
        settingsManager.$hotkey
            .receive(on: RunLoop.main)
            .sink { [weak self] newHotkey in
                self?.hotkeyManager.hotkey = newHotkey
            }
            .store(in: &cancellables)

        // Sync custom key code changes
        settingsManager.$customKeyCode
            .receive(on: RunLoop.main)
            .sink { [weak self] code in
                self?.hotkeyManager.customKeyCode = code
            }
            .store(in: &cancellables)
        hotkeyManager.customKeyCode = settingsManager.customKeyCode

        // Sparkle handles automatic update checks

        // Auto-show main window on launch and set delegate on all windows
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            for window in NSApp.windows {
                window.delegate = self
            }
            if let window = NSApp.windows.first(where: { $0.title == "NimbusGlide" }) {
                window.makeKeyAndOrderFront(nil)
            }
            NSApp.activate(ignoringOtherApps: true)
        }

        // Also watch for new windows being created (SwiftUI can create them late)
        NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] note in
            if let window = note.object as? NSWindow, window.delegate == nil || !(window.delegate is AppDelegate) {
                window.delegate = self
            }
        }
    }
}

// MARK: - NSWindowDelegate

extension AppDelegate: NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool {
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // If user hits Cmd+Q or Quit from menu, actually quit
        // If it's just the window closing, don't quit (handled by windowShouldClose)
        return .terminateNow
    }
}
