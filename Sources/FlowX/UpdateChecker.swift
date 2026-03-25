import Foundation
import SwiftUI
import Sparkle

class UpdateChecker: ObservableObject {
    static let currentVersion = "1.0.1"

    let updaterController: SPUStandardUpdaterController

    @Published var canCheckForUpdates = false

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        // Observe when Sparkle is ready to check
        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)

        // Check automatically every 4 hours
        updaterController.updater.automaticallyChecksForUpdates = true
        updaterController.updater.updateCheckInterval = 4 * 60 * 60
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}
