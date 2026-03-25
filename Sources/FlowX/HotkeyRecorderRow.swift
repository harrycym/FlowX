import SwiftUI
import AppKit

struct HotkeyRecorderRow: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 10) {
            Text("Current Key:")
                .font(.callout)
                .foregroundColor(.secondary)

            Text(settingsManager.customKeyLabel)
                .font(.system(.body, design: .monospaced).weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.15))
                .cornerRadius(6)

            Spacer()

            Button(isRecording ? "Press any key…" : "Record Key") {
                if isRecording { stopRecording() } else { startRecording() }
            }
            .buttonStyle(.borderedProminent)
            .tint(isRecording ? .red : .accentColor)
        }
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let chars = event.charactersIgnoringModifiers?.uppercased() ?? ""
            let label: String
            switch event.keyCode {
            case 122: label = "F1"
            case 120: label = "F2"
            case 99:  label = "F3"
            case 118: label = "F4"
            case 96:  label = "F5"
            case 97:  label = "F6"
            case 98:  label = "F7"
            case 100: label = "F8"
            case 101: label = "F9"
            case 109: label = "F10"
            case 103: label = "F11"
            case 111: label = "F12"
            default:  label = chars.isEmpty ? "Key \(event.keyCode)" : chars
            }
            self.settingsManager.customKeyCode  = event.keyCode
            self.settingsManager.customKeyLabel = label
            self.stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }
}
