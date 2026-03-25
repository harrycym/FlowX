import SwiftUI
import AppKit

// MARK: - Status Pill (sidebar footer)

struct StatusPill: View {
    let status: PipelineStatus

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(status.rawValue)
                .font(.caption.weight(.medium))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(statusColor.opacity(0.1))
        .cornerRadius(12)
    }

    private var statusColor: Color {
        switch status {
        case .idle: return .green
        case .recording: return .red
        case .processing: return .orange
        case .error: return .red
        }
    }
}

// MARK: - Status Section (home dashboard)

struct StatusSection: View {
    let status: PipelineStatus
    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.1))
                    .frame(width: 120, height: 120)

                Circle()
                    .fill(statusColor.opacity(0.2))
                    .frame(width: 90, height: 90)
                    .scaleEffect(status == .recording && isAnimating ? 1.25 : 1.0)
                    .animation(
                        status == .recording
                            ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                            : .default,
                        value: isAnimating
                    )

                if status == .processing {
                    ProgressView()
                        .scaleEffect(1.5)
                        .progressViewStyle(.circular)
                } else {
                    Image(systemName: statusIcon)
                        .font(.system(size: 36))
                        .foregroundColor(statusColor)
                }
            }

            Text(status.rawValue)
                .font(.title2.weight(.semibold))
                .foregroundColor(statusColor)
        }
        .onAppear { isAnimating = true }
        .onChange(of: status) { _ in isAnimating = true }
    }

    private var statusColor: Color {
        switch status {
        case .idle: return .green
        case .recording: return .red
        case .processing: return .orange
        case .error: return .red
        }
    }

    private var statusIcon: String {
        switch status {
        case .idle: return "checkmark.circle.fill"
        case .recording: return "mic.fill"
        case .processing: return "gear"
        case .error: return "exclamationmark.triangle.fill"
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
                    .font(.body.weight(.semibold))
                Text(buttonLabel)
                    .font(.body.weight(.semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(buttonColor)
            .cornerRadius(25)
            .scaleEffect(isHovering ? 1.05 : 1.0)
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
        case .recording: return "Stop Recording"
        case .processing: return "Processing…"
        default: return "Start Recording"
        }
    }

    private var buttonColor: Color {
        switch status {
        case .recording: return .red
        case .processing: return .gray
        default: return .accentColor
        }
    }
}

// MARK: - Instruction Card

struct InstructionCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("How to Use", systemImage: "questionmark.circle")
                .font(.headline)

            InstructionRow(
                icon: "option",
                text: "Hold the **Right Option** key to record, release to process"
            )
            InstructionRow(
                icon: "mic.fill",
                text: "Or click the **Start Recording** button above"
            )
            InstructionRow(
                icon: "text.quote",
                text: "Say **\"FlowX\"** followed by a command to edit selected text"
            )
            InstructionRow(
                icon: "doc.on.clipboard",
                text: "Processed text is **automatically pasted** into your active app"
            )
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }
}

private struct InstructionRow: View {
    let icon: String
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundColor(.accentColor)
            Text(text)
                .font(.callout)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Quick Info Row

struct QuickInfoRow: View {
    let activeProfile: Profile?
    let apiConfigured: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Active Profile
            GroupBox {
                HStack(spacing: 8) {
                    Image(systemName: "person.circle.fill")
                        .foregroundColor(.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Active Profile")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(activeProfile?.name ?? "None")
                            .font(.callout.weight(.medium))
                    }
                    Spacer()
                }
                .padding(4)
            }

            // API Status
            GroupBox {
                HStack(spacing: 8) {
                    Image(systemName: apiConfigured ? "checkmark.shield.fill" : "xmark.shield.fill")
                        .foregroundColor(apiConfigured ? .green : .red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("APIs")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(apiConfigured ? "Connected" : "Keys Missing")
                            .font(.callout.weight(.medium))
                            .foregroundColor(apiConfigured ? .primary : .red)
                    }
                    Spacer()
                }
                .padding(4)
            }
        }
    }
}

// MARK: - Last Result Card

struct LastResultCard: View {
    let transcript: String
    let result: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Last Dictation", systemImage: "text.bubble")
                    .font(.headline)
                Spacer()
                Button(action: copyResult) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .foregroundColor(copied ? .green : .secondary)
                }
                .buttonStyle(.plain)
                .help("Copy result")
            }

            Text("You said:")
                .font(.caption)
                .foregroundColor(.secondary)
            Text(transcript)
                .font(.callout)
                .foregroundColor(.secondary)
                .lineLimit(3)

            Divider()

            Text("Output:")
                .font(.caption)
                .foregroundColor(.secondary)
            Text(result)
                .font(.body)
                .textSelection(.enabled)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }

    private func copyResult() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(result, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copied = false
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
                Text("FlowX \(version) available")
                    .font(.callout.weight(.semibold))
                    .foregroundColor(.white)
                if let notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(1)
                }
            }
            Spacer()
            Button("Update") {
                // Open the repo so user can pull & rebuild
                NSWorkspace.shared.open(URL(string: "https://github.com/harrycym/FlowX")!)
            }
            .buttonStyle(.bordered)
            .tint(.white)
            .controlSize(.small)
        }
        .padding(12)
        .background(Color.accentColor)
        .cornerRadius(10)
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
                .font(.callout)
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
        .background(Color.red.opacity(0.9))
        .cornerRadius(10)
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
                    .foregroundColor(granted ? .green : .red)
                Text(name)
                Spacer()
                if granted {
                    Label("Granted", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                } else {
                    Button("Open System Settings", action: action)
                        .font(.caption)
                }
            }
            if !granted, let hint {
                Text(hint)
                    .font(.caption2)
                    .foregroundColor(.orange)
                    .padding(.leading, 32)
            }
        }
    }
}
