import SwiftUI
import AppKit

@main
struct FlowXApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Window("FlowX", id: "main") {
            MainWindowView()
                .environmentObject(appDelegate.pipelineState)
                .environmentObject(appDelegate.profileManager)
                .environmentObject(appDelegate.memoryManager)
                .environmentObject(appDelegate.settingsManager)
                .environmentObject(appDelegate.updateChecker)
        }
        .defaultSize(width: 750, height: 500)

        Settings {
            SettingsView()
                .environmentObject(appDelegate.profileManager)
                .environmentObject(appDelegate.memoryManager)
                .environmentObject(appDelegate.settingsManager)
        }
    }
}
