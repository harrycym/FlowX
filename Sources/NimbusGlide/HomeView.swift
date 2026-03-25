import SwiftUI
import AppKit

struct HomeView: View {
    @EnvironmentObject var pipelineState: PipelineState
    @EnvironmentObject var profileManager: ProfileManager
    @EnvironmentObject var updateChecker: UpdateChecker
    @EnvironmentObject var usageTracker: UsageTracker
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var memoryManager: MemoryManager
    @EnvironmentObject var authManager: AuthManager

    @State private var showAccessibilityAlert = false
    @State private var micPulse = false
    @State private var copiedResult = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Accessibility warning
                if !pipelineState.isAccessibilityAuthorized {
                    AccessibilityWarningBanner()
                }

                // Error banner
                if let error = pipelineState.errorMessage {
                    ErrorBanner(message: error) {
                        pipelineState.clearError()
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                // Paywall if limit reached
                if usageTracker.hasReachedLimit || pipelineState.usageLimitHit {
                    PaywallBanner()
                } else {
                    // Welcome header + stats
                    welcomeHeader

                    // Instructional banner
                    instructionalBanner

                    // Mic button + hotkey hint
                    micButtonSection

                    // Test text area for latest result
                    resultTextArea

                    // Inline dictation history
                    dictationHistory
                }
            }
            .padding(NimbusLayout.contentPadding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(NimbusColors.warmBg)
        .animation(.easeInOut(duration: 0.25), value: pipelineState.errorMessage)
        .animation(.easeInOut(duration: 0.25), value: pipelineState.status)
        .animation(.easeInOut(duration: 0.25), value: pipelineState.isAccessibilityAuthorized)
        .onAppear {
            // Clear stale auth errors if user is actually signed in
            if authManager.isAuthenticated, let msg = pipelineState.errorMessage,
               msg.contains("sign in") || msg.contains("Not signed") || msg.contains("Session expired") {
                pipelineState.clearError()
            }
        }
        .onChange(of: pipelineState.status) { newStatus in
            if newStatus == .recording {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    micPulse = true
                }
            } else {
                withAnimation(.easeInOut(duration: 0.2)) {
                    micPulse = false
                }
            }
        }
        .alert("Accessibility Required", isPresented: $showAccessibilityAlert) {
            Button("Open Settings") {
                NSWorkspace.shared.open(
                    URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                )
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("NimbusGlide needs Accessibility access to paste text into your apps. Please grant it in System Settings.")
        }
    }

    // MARK: - Welcome Header

    private var welcomeHeader: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Welcome back, \(userName)")
                        .font(.title2.weight(.bold))
                        .foregroundColor(NimbusColors.heading)
                }
                Spacer()
                statusBadge
            }

            // Stats row
            HStack(spacing: 24) {
                StatBadge(
                    icon: "flame.fill",
                    color: .orange,
                    value: "\(streakDays)",
                    label: streakDays == 1 ? "day" : "days"
                )
                StatBadge(
                    icon: "pencil.line",
                    color: NimbusColors.violet,
                    value: usageTracker.totalWordsUsed.formatted(),
                    label: "words"
                )
                StatBadge(
                    icon: "bolt.fill",
                    color: NimbusColors.cyan,
                    value: "160",
                    label: "WPM"
                )
                Spacer()
            }
        }
    }

    private var statusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusDotColor)
                .frame(width: 8, height: 8)
            Text(statusLabel)
                .font(.caption.weight(.medium))
                .foregroundColor(statusDotColor)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(statusDotColor.opacity(0.1))
        .cornerRadius(12)
    }

    // MARK: - Instructional Banner

    private var instructionalBanner: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Hold ")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.white)
                +
                Text(hotkeyDisplay)
                    .font(.title3.weight(.bold))
                    .foregroundColor(.white)
                +
                Text(" → to dictate and let NimbusGlide format for you")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.white)

                Text("Press and hold \(hotkeyDisplay) to dictate in any app. NimbusGlide's Smart Formatting will handle punctuation, new lines, lists, and adjust when you change your mind mid-sentence.")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
                    .lineSpacing(2)

                Button(action: {
                    NotificationCenter.default.post(name: .nimbusglideNavigateToSettings, object: nil)
                }) {
                    Text("Show me how")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(NimbusColors.heading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Color.white)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(20)
        .background(
            NimbusGradients.banner
                .cornerRadius(NimbusLayout.cardRadius)
        )
    }

    // MARK: - Mic Button

    private var isRecording: Bool {
        pipelineState.status == .recording
    }

    private var micButtonSection: some View {
        VStack(spacing: 14) {
            // Big mic button
            Button(action: {
                pipelineState.onToggleRecording?()
            }) {
                ZStack {
                    // Outer pulse ring (visible only when recording)
                    Circle()
                        .stroke(NimbusColors.recording.opacity(micPulse ? 0.4 : 0), lineWidth: 4)
                        .frame(width: 100, height: 100)
                        .scaleEffect(micPulse ? 1.25 : 1.0)

                    // Main circle
                    Circle()
                        .fill(
                            isRecording
                                ? AnyShapeStyle(NimbusColors.recording)
                                : AnyShapeStyle(NimbusGradients.primary)
                        )
                        .frame(width: 80, height: 80)
                        .shadow(
                            color: (isRecording ? NimbusColors.recording : NimbusColors.indigo).opacity(0.35),
                            radius: micPulse ? 16 : 8,
                            x: 0, y: 4
                        )

                    // Mic icon
                    Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isRecording ? "Stop recording" : "Start recording")

            // Status label
            Text(isRecording ? "Listening..." : "Tap to dictate")
                .font(.callout.weight(.medium))
                .foregroundColor(isRecording ? NimbusColors.recording : NimbusColors.muted)

            // Hotkey hint
            HStack(spacing: 4) {
                Text("or hold")
                    .font(.caption)
                    .foregroundColor(NimbusColors.muted)

                Text(hotkeyDisplay)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(NimbusColors.heading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(NimbusColors.sidebarBg)
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(NimbusColors.muted.opacity(0.3), lineWidth: 1)
                    )

                Text("to dictate")
                    .font(.caption)
                    .foregroundColor(NimbusColors.muted)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    // MARK: - Result Text Area

    private var resultTextArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Latest Result")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(NimbusColors.muted)
                    .tracking(0.5)

                Spacer()

                if pipelineState.lastResult != nil {
                    Button(action: copyResult) {
                        HStack(spacing: 4) {
                            Image(systemName: copiedResult ? "checkmark" : "doc.on.doc")
                                .font(.caption2)
                            Text(copiedResult ? "Copied" : "Copy")
                                .font(.caption)
                        }
                        .foregroundColor(copiedResult ? NimbusColors.ready : NimbusColors.indigo)
                    }
                    .buttonStyle(.plain)
                }
            }

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: NimbusLayout.cardRadius)
                    .fill(NimbusColors.cardBg)
                    .overlay(
                        RoundedRectangle(cornerRadius: NimbusLayout.cardRadius)
                            .stroke(
                                isRecording
                                    ? NimbusColors.recording.opacity(0.4)
                                    : NimbusColors.muted.opacity(0.2),
                                lineWidth: 1
                            )
                    )

                if let result = pipelineState.lastResult, !result.isEmpty {
                    Text(result)
                        .font(.body)
                        .foregroundColor(NimbusColors.heading)
                        .textSelection(.enabled)
                        .padding(14)
                } else {
                    Text("Your text will appear here...")
                        .font(.body)
                        .foregroundColor(NimbusColors.muted.opacity(0.6))
                        .padding(14)
                }
            }
            .frame(minHeight: 80, alignment: .topLeading)
        }
        .padding(16)
        .nimbusCard()
    }

    private func copyResult() {
        guard let text = pipelineState.lastResult else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copiedResult = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copiedResult = false }
    }

    // MARK: - Dictation History (inline)

    private var dictationHistory: some View {
        VStack(alignment: .leading, spacing: 0) {
            // "TODAY" header
            if !memoryManager.entries.isEmpty {
                Text("TODAY")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(NimbusColors.muted)
                    .tracking(1)
                    .padding(.bottom, 12)

                VStack(spacing: 0) {
                    ForEach(memoryManager.entries.prefix(20)) { entry in
                        DictationRow(entry: entry)

                        if entry.id != memoryManager.entries.prefix(20).last?.id {
                            Divider()
                                .padding(.leading, 80)
                        }
                    }
                }
                .nimbusCard()
            } else {
                emptyHistoryState
            }
        }
    }

    private var emptyHistoryState: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(NimbusGradients.primary)

            Text("No dictations yet")
                .font(.callout.weight(.medium))
                .foregroundColor(NimbusColors.heading)

            Text("Hold \(hotkeyDisplay) to start your first dictation.\nYour history will appear here.")
                .font(.caption)
                .foregroundColor(NimbusColors.muted)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
        .nimbusCard()
    }

    // MARK: - Helpers

    private var userName: String {
        let name = authManager.currentUser?.displayName ?? authManager.currentUser?.email ?? "there"
        return name.split(separator: " ").first.map(String.init) ?? name
    }

    private var hotkeyDisplay: String {
        settingsManager.hotkey == .custom ? settingsManager.customKeyLabel : settingsManager.hotkey.rawValue
    }

    private var streakDays: Int {
        // Placeholder — compute from memoryManager entries
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var streak = 0
        var checkDate = today
        for _ in 0..<365 {
            if memoryManager.entries.contains(where: { calendar.isDate($0.timestamp, inSameDayAs: checkDate) }) {
                streak += 1
                checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate) ?? checkDate
            } else {
                break
            }
        }
        return max(streak, 1) // At least 1 if they're using the app today
    }

    private var statusLabel: String {
        switch pipelineState.status {
        case .idle: return "Ready"
        case .recording: return "Listening"
        case .processing: return "Thinking"
        case .error: return "Error"
        }
    }

    private var statusDotColor: Color {
        switch pipelineState.status {
        case .idle: return NimbusColors.ready
        case .recording: return NimbusColors.recording
        case .processing: return NimbusColors.processing
        case .error: return NimbusColors.error
        }
    }
}

// MARK: - Stat Badge

struct StatBadge: View {
    let icon: String
    let color: Color
    let value: String
    let label: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundColor(color)
            Text(value)
                .font(.callout.weight(.semibold))
                .foregroundColor(NimbusColors.heading)
            Text(label)
                .font(.caption)
                .foregroundColor(NimbusColors.muted)
        }
    }
}

// MARK: - Dictation History Row

struct DictationRow: View {
    let entry: MemoryEntry
    @State private var copied = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Timestamp
            Text(entry.timestamp, format: .dateTime.hour().minute())
                .font(.caption.monospaced())
                .foregroundColor(NimbusColors.muted)
                .frame(width: 60, alignment: .trailing)

            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.polishedText)
                    .font(.callout)
                    .foregroundColor(NimbusColors.heading)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }

            Spacer()

            // Copy
            Button(action: copyText) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.caption)
                    .foregroundColor(copied ? NimbusColors.ready : NimbusColors.muted)
            }
            .buttonStyle(.plain)
            .opacity(0.7)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func copyText() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.polishedText, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
    }
}

// MARK: - Accessibility Warning Banner (kept from original)

struct AccessibilityWarningBanner: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.white)
                .font(.body.weight(.semibold))
            VStack(alignment: .leading, spacing: 2) {
                Text("Accessibility Not Granted")
                    .font(.callout.weight(.semibold))
                    .foregroundColor(.white)
                Text("NimbusGlide can't paste text without this permission.")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.9))
            }
            Spacer()
            Button("Grant Access") {
                NSWorkspace.shared.open(
                    URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                )
            }
            .buttonStyle(.bordered)
            .tint(.white)
            .controlSize(.small)
        }
        .padding(12)
        .background(NimbusColors.error.opacity(0.9))
        .cornerRadius(NimbusLayout.cardRadius)
    }
}
