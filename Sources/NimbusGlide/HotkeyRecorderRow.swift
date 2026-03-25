import SwiftUI
import AppKit
import Carbon

struct HotkeyRecorderRow: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @State private var isRecording = false
    @State private var keyMonitor: Any?
    @State private var flagsMonitor: Any?

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

        // Capture regular keys (letters, numbers, F-keys, Enter, Tab, Backspace, Space, Escape, arrows)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let code = event.keyCode
            let label = Self.labelForKeyCode(code, characters: event.charactersIgnoringModifiers)
            settingsManager.customKeyCode = code
            settingsManager.customKeyLabel = label
            stopRecording()
            return nil // swallow the event
        }

        // Capture modifier-only keys (Shift, Ctrl, Caps Lock)
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            let code = event.keyCode
            // Only capture standalone modifier presses, not combos
            if let label = Self.labelForModifierKeyCode(code) {
                settingsManager.customKeyCode = code
                settingsManager.customKeyLabel = label
                stopRecording()
                return nil
            }
            return event
        }
    }

    private func stopRecording() {
        isRecording = false
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        if let m = flagsMonitor { NSEvent.removeMonitor(m); flagsMonitor = nil }
    }

    // MARK: - Key Labels

    static func labelForKeyCode(_ code: UInt16, characters: String?) -> String {
        switch code {
        // F-keys
        case 122: return "F1"
        case 120: return "F2"
        case 99:  return "F3"
        case 118: return "F4"
        case 96:  return "F5"
        case 97:  return "F6"
        case 98:  return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        // Special keys
        case 36:  return "Return ↩"
        case 76:  return "Enter ⌤"
        case 48:  return "Tab ⇥"
        case 51:  return "Delete ⌫"
        case 117: return "Forward Delete ⌦"
        case 53:  return "Escape ⎋"
        case 49:  return "Space ␣"
        // Arrow keys
        case 123: return "← Left"
        case 124: return "→ Right"
        case 125: return "↓ Down"
        case 126: return "↑ Up"
        // Home/End/Page
        case 115: return "Home"
        case 119: return "End"
        case 116: return "Page Up"
        case 121: return "Page Down"
        default:
            let chars = characters?.uppercased() ?? ""
            if !chars.isEmpty && chars != "\r" && chars != "\t" {
                return chars
            }
            return "Key \(code)"
        }
    }

    static func labelForModifierKeyCode(_ code: UInt16) -> String? {
        switch code {
        case 56, 60:  return "Shift ⇧"      // Left/Right Shift
        case 59, 62:  return "Control ⌃"     // Left/Right Control
        case 58, 61:  return "Option ⌥"      // Left/Right Option
        case 55, 54:  return "Command ⌘"     // Left/Right Command
        case 57:      return "Caps Lock ⇪"
        case 63:      return "fn Globe 🌐"
        default:      return nil
        }
    }
}
