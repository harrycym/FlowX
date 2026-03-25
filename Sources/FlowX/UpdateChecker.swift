import Foundation
import SwiftUI

class UpdateChecker: ObservableObject {
    static let currentVersion = "1.0.0"
    private let versionURL = "https://raw.githubusercontent.com/harrycym/FlowX/main/version.json"

    @Published var updateAvailable = false
    @Published var latestVersion: String?
    @Published var releaseNotes: String?

    func checkForUpdate() {
        guard let url = URL(string: versionURL) else { return }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 10

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let latest = json["latest_version"] as? String else {
                return
            }

            let notes = json["release_notes"] as? String

            DispatchQueue.main.async {
                self?.latestVersion = latest
                self?.releaseNotes = notes
                self?.updateAvailable = self?.isNewer(latest, than: Self.currentVersion) ?? false
            }
        }.resume()
    }

    private func isNewer(_ remote: String, than local: String) -> Bool {
        let r = remote.split(separator: ".").compactMap { Int($0) }
        let l = local.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(r.count, l.count) {
            let rv = i < r.count ? r[i] : 0
            let lv = i < l.count ? l[i] : 0
            if rv > lv { return true }
            if rv < lv { return false }
        }
        return false
    }
}
