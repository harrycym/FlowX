import SwiftUI
import AppKit

@main
struct NimbusGlideApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Window("NimbusGlide", id: "main") {
            MainWindowView()
                .preferredColorScheme(.light)
                .environmentObject(appDelegate.pipelineState)
                .environmentObject(appDelegate.profileManager)
                .environmentObject(appDelegate.memoryManager)
                .environmentObject(appDelegate.settingsManager)
                .environmentObject(appDelegate.updateChecker)
                .environmentObject(appDelegate.usageTracker)
                .environmentObject(appDelegate.authManager)
                .environmentObject(appDelegate.snippetsManager)
                .environmentObject(appDelegate.dictionaryManager)
                .onOpenURL { url in
                    appDelegate.authManager.handleCallback(url: url)
                }
        }
        .defaultSize(width: 960, height: 680)

        Settings {
            SettingsView()
                .environmentObject(appDelegate.profileManager)
                .environmentObject(appDelegate.memoryManager)
                .environmentObject(appDelegate.settingsManager)
                .environmentObject(appDelegate.updateChecker)
                .environmentObject(appDelegate.pipelineState)
                .environmentObject(appDelegate.usageTracker)
                .environmentObject(appDelegate.authManager)
        }
    }
}
