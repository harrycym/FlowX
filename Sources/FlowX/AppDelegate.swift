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
    var pipeline: FlowXPipeline!

    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        PermissionsManager.requestMicrophoneAccess { [weak self] granted in
            DispatchQueue.main.async {
                self?.pipelineState.isMicrophoneAuthorized = granted
            }
            if !granted {
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "Microphone Access Required"
                    alert.informativeText = "FlowX needs microphone access to record audio for transcription. Please grant access in System Settings > Privacy & Security > Microphone."
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

        appTracker = AppTracker()
        keystrokeSimulator = KeystrokeSimulator()
        audioRecorder = AudioRecorder()
        aiService = AIService(settingsManager: settingsManager)

        pipeline = FlowXPipeline(
            audioRecorder: audioRecorder,
            aiService: aiService,
            appTracker: appTracker,
            keystrokeSimulator: keystrokeSimulator,
            profileManager: profileManager,
            memoryManager: memoryManager
        )

        menuBarManager = MenuBarManager(pipeline: pipeline, settingsManager: settingsManager, profileManager: profileManager)
        pipeline.menuBarManager = menuBarManager
        pipeline.pipelineState = pipelineState

        // Wire toggle recording closure for the UI record button
        pipelineState.onToggleRecording = { [weak self] in
            self?.pipeline.toggleRecording()
        }

        // Keep pipelineState.isAPIKeyConfigured in sync with settingsManager
        pipelineState.isAPIKeyConfigured = settingsManager.hasValidAPIKey
        settingsManager.$apiKey
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.pipelineState.isAPIKeyConfigured = self?.settingsManager.hasValidAPIKey ?? false
            }
            .store(in: &cancellables)

        // Start monitoring permissions (refreshes on activation + polls until granted)
        pipelineState.refreshPermissions()
        pipelineState.startMonitoringPermissions()

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

        // Check for updates
        updateChecker.checkForUpdate()

        // Auto-show main window on launch
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if let window = NSApp.windows.first(where: { $0.title == "FlowX" }) {
                window.makeKeyAndOrderFront(nil)
            }
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
