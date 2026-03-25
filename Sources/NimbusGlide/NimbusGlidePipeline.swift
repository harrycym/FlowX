import Foundation
import AppKit

class NimbusGlidePipeline {
    private let audioRecorder: AudioRecorder
    private let aiService: AIService
    private let appTracker: AppTracker
    private let keystrokeSimulator: KeystrokeSimulator
    private let profileManager: ProfileManager
    private let memoryManager: MemoryManager

    private var isProcessing = false
    weak var menuBarManager: MenuBarManager?
    var pipelineState: PipelineState?
    var settingsManager: SettingsManager?

    /// Tracks the last non-NimbusGlide frontmost app (for manual record button)
    private var lastExternalApp: String = "Unknown"

    init(
        audioRecorder: AudioRecorder,
        aiService: AIService,
        appTracker: AppTracker,
        keystrokeSimulator: KeystrokeSimulator,
        profileManager: ProfileManager,
        memoryManager: MemoryManager
    ) {
        self.audioRecorder = audioRecorder
        self.aiService = aiService
        self.appTracker = appTracker
        self.keystrokeSimulator = keystrokeSimulator
        self.profileManager = profileManager
        self.memoryManager = memoryManager
    }

    func toggleRecording() {
        if audioRecorder.isRecording {
            stopRecordingAndProcess()
        } else {
            startRecording()
        }
    }

    func startRecording() {
        guard !isProcessing else {
            print("[NimbusGlide] Already processing, ignoring record request")
            return
        }

        // Capture frontmost app before NimbusGlide potentially takes focus
        let currentApp = appTracker.frontmostAppName()
        if currentApp != "NimbusGlide" {
            lastExternalApp = currentApp
        }

        audioRecorder.startRecording()
        menuBarManager?.setRecordingIndicator(true)
        menuBarManager?.updateStatus("Recording…")

        DispatchQueue.main.async {
            self.pipelineState?.status = .recording
            CursorManager.showRecordingCursor()
        }
    }

    func stopRecordingAndProcess() {
        guard let recordingURL = audioRecorder.stopRecording() else {
            print("[NimbusGlide] No recording to process")
            menuBarManager?.setRecordingIndicator(false)
            menuBarManager?.updateStatus("Ready")
            DispatchQueue.main.async {
                self.pipelineState?.status = .idle
            }
            return
        }

        menuBarManager?.setRecordingIndicator(false)
        menuBarManager?.updateStatus("Processing…")
        isProcessing = true

        DispatchQueue.main.async {
            CursorManager.showProcessingCursor()
            self.pipelineState?.status = .processing
        }

        // Use the last external app if NimbusGlide is frontmost (manual record button case)
        let currentApp = appTracker.frontmostAppName()
        let activeApp = (currentApp == "NimbusGlide") ? lastExternalApp : currentApp
        let profileInstructions = profileManager.activeProfile?.instructions
        let memoryExamples = memoryManager.recentExamples()

        Task {
            do {
                let transcript = try await aiService.transcribeAudio(fileURL: recordingURL)
                #if DEBUG
                print("[NimbusGlide] Transcript: \(transcript)")
                #endif

                guard !transcript.isEmpty, !Self.isWhisperHallucination(transcript) else {
                    print("[NimbusGlide] Empty or hallucinated transcript, skipping")
                    await finish(status: .idle)
                    return
                }

                let result = try await aiService.processWithLLM(
                    transcript: transcript,
                    activeApp: activeApp,
                    profileInstructions: profileInstructions,
                    memoryExamples: memoryExamples
                )
                #if DEBUG
                print("[NimbusGlide] Result: \(result)")
                #endif

                guard !result.isEmpty else {
                    print("[NimbusGlide] Empty LLM result, skipping")
                    await finish(status: .idle)
                    return
                }

                // Save to memory for few-shot learning
                await MainActor.run {
                    memoryManager.addEntry(rawTranscript: transcript, polishedText: result)
                    pipelineState?.recordSuccess(transcript: transcript, result: result)
                }

                // Auto-copy to clipboard if enabled
                if self.settingsManager?.autoCopyToClipboard == true {
                    await MainActor.run {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(result, forType: .string)
                    }
                }

                // Paste into frontmost app
                await MainActor.run {
                    keystrokeSimulator.pasteText(result)
                }

                await finish(status: .idle)

            } catch let error as NimbusGlideError where error == .usageLimitReached {
                print("[NimbusGlide] Usage limit reached")
                await MainActor.run {
                    pipelineState?.status = .idle
                    pipelineState?.usageLimitHit = true
                    // Bring app window to front immediately
                    if let window = NSApp.windows.first(where: { $0.title == "NimbusGlide" }) {
                        window.makeKeyAndOrderFront(nil)
                    } else {
                        // Window might be hidden — open it
                        for window in NSApp.windows where window.canBecomeKey {
                            window.makeKeyAndOrderFront(nil)
                            break
                        }
                    }
                    NSApp.activate(ignoringOtherApps: true)
                }
                await finish(status: .idle)
            } catch {
                print("[NimbusGlide] Pipeline error: \(error.localizedDescription)")
                await MainActor.run {
                    pipelineState?.status = .error
                    pipelineState?.errorMessage = error.localizedDescription
                }
                await finish(status: .error)
            }

            audioRecorder.cleanup()
        }
    }

    /// Whisper hallucinates short phrases on silence — filter them out
    private static func isWhisperHallucination(_ text: String) -> Bool {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // Too short to be real speech (under 4 words)
        let wordCount = cleaned.split(separator: " ").count
        if wordCount > 4 { return false }

        let hallucinations: Set<String> = [
            "thank you", "thank you.", "thanks.", "thanks",
            "bye", "bye.", "bye bye", "bye-bye", "goodbye", "goodbye.",
            "thanks for watching", "thanks for watching.",
            "thank you for watching", "thank you for watching.",
            "see you", "see you.", "see you next time",
            "subscribe", "like and subscribe",
            "you", "the end", "the end.",
            "so", "okay", "okay.", "ok", "ok.",
            "yeah", "yeah.", "yes", "yes.", "no", "no.",
            "hmm", "hmm.", "hm", "um", "uh",
            "...", ".", "",
        ]
        return hallucinations.contains(cleaned)
    }

    @MainActor
    private func finish(status: PipelineStatus) {
        isProcessing = false
        CursorManager.restoreCursor()
        menuBarManager?.updateStatus(status.rawValue)
        // Only set idle if we're finishing successfully — error state is set in catch
        if status == .idle {
            pipelineState?.status = .idle
        }
    }
}
