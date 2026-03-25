import SwiftUI

struct AppSettingsView: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var pipelineState: PipelineState
    @EnvironmentObject var usageTracker: UsageTracker
    @EnvironmentObject var updateChecker: UpdateChecker

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Hotkey
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Hotkey", systemImage: "keyboard")
                            .font(.headline)

                        Text("Hold this key to dictate, release to process.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Picker("", selection: $settingsManager.hotkey) {
                            ForEach(HotkeyChoice.allCases) { choice in
                                Text(choice.rawValue).tag(choice)
                            }
                        }
                        .pickerStyle(.radioGroup)
                        .labelsHidden()

                        if settingsManager.hotkey == .custom {
                            HotkeyRecorderRow()
                                .environmentObject(settingsManager)
                        }
                    }
                    .padding(4)
                }

                // Permissions
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Permissions", systemImage: "lock.shield")
                            .font(.headline)

                        PermissionRow(
                            name: "Microphone",
                            icon: "mic.fill",
                            granted: pipelineState.isMicrophoneAuthorized
                        ) {
                            NSWorkspace.shared.open(
                                URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
                            )
                        }

                        PermissionRow(
                            name: "Accessibility",
                            icon: "accessibility",
                            granted: pipelineState.isAccessibilityAuthorized,
                            hint: "If listed but not working, toggle it off and on"
                        ) {
                            PermissionsManager.checkAccessibilityAccess()
                            NSWorkspace.shared.open(
                                URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                            )
                        }
                    }
                    .padding(4)
                }

                // Appearance
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Appearance", systemImage: "paintbrush")
                            .font(.headline)

                        Toggle(isOn: $settingsManager.showStatusIndicator) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Floating status indicator")
                                Text("Shows a small pill at the bottom center when recording or processing")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(4)
                }

                // Usage
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Usage", systemImage: "chart.bar")
                            .font(.headline)

                        HStack {
                            Text("\(usageTracker.totalWordsUsed.formatted()) words used")
                                .font(.callout)
                            Spacer()
                            if usageTracker.isPro {
                                Label("Pro", systemImage: "checkmark.seal.fill")
                                    .font(.caption.weight(.medium))
                                    .foregroundColor(.accentColor)
                            } else if let limit = usageTracker.wordLimit {
                                Text("\(max(0, limit - usageTracker.totalWordsUsed).formatted()) remaining")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        if !usageTracker.isPro {
                            ProgressView(value: usageTracker.usageRatio)
                                .tint(usageTracker.usageRatio > 0.8 ? .orange : .accentColor)
                        }
                    }
                    .padding(4)
                }

                // About & Updates
                GroupBox {
                    // About
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("NimbusGlide")
                                .font(.callout.weight(.medium))
                            Text("Version \(UpdateChecker.currentVersion)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button("Check for Updates") {
                            updateChecker.checkForUpdates()
                        }
                        .disabled(!updateChecker.canCheckForUpdates)
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(4)
                }
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
