import SwiftUI
import AppKit

// MARK: - Processing Spinner

struct ProcessingSpinner: View {
    @State private var spin = false
    @State private var pulse = false

    var body: some View {
        ZStack {
            // Outer glow pulse
            Circle()
                .fill(NimbusColors.violet.opacity(0.15))
                .frame(width: 60, height: 60)
                .scaleEffect(pulse ? 1.3 : 0.9)

            Image(systemName: "sparkles")
                .font(.system(size: 36, weight: .light))
                .foregroundColor(NimbusColors.violet)
                .rotationEffect(.degrees(spin ? 360 : 0))
        }
        .onAppear {
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                spin = true
            }
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

// MARK: - Status Pill (sidebar footer)

struct StatusPill: View {
    let status: PipelineStatus

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusLabel)
                .font(NimbusFonts.caption.weight(.medium))
                .foregroundColor(NimbusColors.muted)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(statusColor.opacity(0.08))
        .cornerRadius(12)
    }

    private var statusLabel: String {
        switch status {
        case .idle: return "Ready"
        case .recording: return "Listening"
        case .processing: return "Thinking"
        case .error: return "Error"
        }
    }

    private var statusColor: Color {
        switch status {
        case .idle: return NimbusColors.ready
        case .recording: return NimbusColors.recording
        case .processing: return NimbusColors.processing
        case .error: return NimbusColors.error
        }
    }
}

// MARK: - Record Button

struct RecordButton: View {
    let status: PipelineStatus
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: buttonIcon)
                    .font(NimbusFonts.bodyMedium)
                Text(buttonLabel)
                    .font(NimbusFonts.bodyMedium)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 28)
            .padding(.vertical, 12)
            .background(buttonBackground)
            .cornerRadius(25)
            .scaleEffect(isHovering ? 1.04 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isHovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering in isHovering = hovering }
        .disabled(status == .processing)
    }

    private var buttonIcon: String {
        switch status {
        case .recording: return "stop.fill"
        case .processing: return "hourglass"
        default: return "mic.fill"
        }
    }

    private var buttonLabel: String {
        switch status {
        case .recording: return "Stop"
        case .processing: return "Working..."
        default: return "Speak"
        }
    }

    private var buttonBackground: some ShapeStyle {
        switch status {
        case .recording: return AnyShapeStyle(NimbusColors.recording)
        case .processing: return AnyShapeStyle(NimbusColors.muted)
        default: return AnyShapeStyle(NimbusGradients.primary)
        }
    }
}

// MARK: - Usage Meter

struct UsageMeter: View {
    @EnvironmentObject var usageTracker: UsageTracker

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(usageTracker.totalWordsUsed.formatted()) words used")
                    .font(NimbusFonts.caption)
                    .foregroundColor(NimbusColors.muted)
                Spacer()
                if usageTracker.isPro {
                    Label("Pro", systemImage: "checkmark.seal.fill")
                        .font(NimbusFonts.small.weight(.medium))
                        .foregroundColor(NimbusColors.indigo)
                } else {
                    Text("\(usageTracker.wordsRemaining.formatted()) left")
                        .font(NimbusFonts.caption)
                        .foregroundColor(usageTracker.usageRatio > 0.8 ? NimbusColors.processing : .secondary)
                }
            }

            if !usageTracker.isPro {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.secondary.opacity(0.15))
                            .frame(height: 4)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(usageTracker.usageRatio > 0.8 ? NimbusColors.processing : NimbusColors.indigo)
                            .frame(width: geo.size.width * usageTracker.usageRatio, height: 4)
                    }
                }
                .frame(height: 4)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - Paywall Banner

struct PaywallBanner: View {
    @State private var showUpgrade = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "bolt.shield.fill")
                .font(.system(size: 36))
                .foregroundStyle(NimbusGradients.primary)

            Text("You've hit the free limit")
                .font(NimbusFonts.sectionHeader)

            Text("Upgrade to Pro for unlimited dictation.\nStarting at just $3/month.")
                .font(NimbusFonts.body)
                .foregroundColor(NimbusColors.muted)
                .multilineTextAlignment(.center)
                .lineSpacing(2)

            Button(action: { showUpgrade = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "bolt.fill")
                    Text("Upgrade to Pro")
                        .font(NimbusFonts.bodyMedium)
                }
                .frame(maxWidth: 240)
                .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: NimbusLayout.cardRadius)
                .fill(NimbusColors.cardBg)
                .overlay(
                    RoundedRectangle(cornerRadius: NimbusLayout.cardRadius)
                        .strokeBorder(
                            LinearGradient(colors: [NimbusColors.indigo.opacity(0.3), NimbusColors.violet.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing),
                            lineWidth: 1
                        )
                )
        )
        .sheet(isPresented: $showUpgrade) {
            UpgradeView()
        }
    }
}

// MARK: - Update Banner

struct UpdateBanner: View {
    let version: String
    let notes: String?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.circle.fill")
                .foregroundColor(.white)
            VStack(alignment: .leading, spacing: 2) {
                Text("NimbusGlide \(version) available")
                    .font(NimbusFonts.bodyMedium)
                    .foregroundColor(.white)
                if let notes, !notes.isEmpty {
                    Text(notes)
                        .font(NimbusFonts.caption)
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(1)
                }
            }
            Spacer()
            Button("Update") {
                NSWorkspace.shared.open(URL(string: "https://nimbusglide.ai")!)
            }
            .buttonStyle(.bordered)
            .tint(.white)
            .controlSize(.small)
        }
        .padding(12)
        .background(NimbusColors.indigo)
        .cornerRadius(NimbusLayout.cardRadius)
    }
}

// MARK: - Error Banner

struct ErrorBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.white)
            Text(message)
                .font(NimbusFonts.body)
                .foregroundColor(.white)
                .lineLimit(2)
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .foregroundColor(.white.opacity(0.8))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(NimbusColors.error.opacity(0.9))
        .cornerRadius(NimbusLayout.cardRadius)
    }
}

// MARK: - Permission Row

struct PermissionRow: View {
    let name: String
    let icon: String
    let granted: Bool
    var hint: String? = nil
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: icon)
                    .frame(width: 24)
                    .foregroundColor(granted ? NimbusColors.ready : NimbusColors.processing)
                Text(name)
                Spacer()
                if granted {
                    Label("Granted", systemImage: "checkmark.circle.fill")
                        .font(NimbusFonts.caption)
                        .foregroundColor(NimbusColors.ready)
                } else {
                    Button("Grant Access", action: action)
                        .font(NimbusFonts.caption)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            if !granted, let hint {
                Text(hint)
                    .font(NimbusFonts.small)
                    .foregroundColor(NimbusColors.processing)
                    .padding(.leading, 32)
            }
        }
    }
}
