import Foundation
import SwiftUI
import Combine

enum PipelineStatus: String {
    case idle = "Ready"
    case recording = "Recording"
    case processing = "Processing"
    case error = "Error"
}

class PipelineState: ObservableObject {
    @Published var status: PipelineStatus = .idle
    @Published var lastTranscript: String?
    @Published var lastResult: String?
    @Published var errorMessage: String?
    @Published var isAuthenticated: Bool = false
    @Published var usageLimitHit: Bool = false
    @Published var isMicrophoneAuthorized: Bool = false
    @Published var isAccessibilityAuthorized: Bool = false

    /// Closure wired by AppDelegate to toggle recording on the pipeline
    var onToggleRecording: (() -> Void)?

    private var permissionTimer: Timer?
    private var activationObserver: Any?

    func clearError() {
        errorMessage = nil
        if status == .error { status = .idle }
    }

    @MainActor
    func recordSuccess(transcript: String, result: String) {
        lastTranscript = transcript
        lastResult = result
        status = .idle
    }

    @MainActor
    func refreshPermissions() {
        isMicrophoneAuthorized = PermissionsManager.isMicrophoneAuthorized
        isAccessibilityAuthorized = PermissionsManager.isAccessibilityAuthorized
    }

    /// Start watching for permission changes — call once from AppDelegate
    func startMonitoringPermissions() {
        // Refresh when app becomes active (e.g. user returns from System Settings)
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.isMicrophoneAuthorized = PermissionsManager.isMicrophoneAuthorized
            self.isAccessibilityAuthorized = PermissionsManager.isAccessibilityAuthorized
        }

        // Poll every 3 seconds until both are granted, then stop
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] timer in
            DispatchQueue.main.async {
                guard let self else { timer.invalidate(); return }
                self.isMicrophoneAuthorized = PermissionsManager.isMicrophoneAuthorized
                self.isAccessibilityAuthorized = PermissionsManager.isAccessibilityAuthorized
                if self.isMicrophoneAuthorized && self.isAccessibilityAuthorized {
                    timer.invalidate()
                    self.permissionTimer = nil
                }
            }
        }
    }

    deinit {
        permissionTimer?.invalidate()
        if let observer = activationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
