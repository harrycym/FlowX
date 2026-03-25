import Foundation
import SwiftUI

class UsageTracker: ObservableObject {
    @Published var totalWordsUsed: Int = 0
    @Published var wordLimit: Int? = 2000
    @Published var plan: String = "free"

    var wordsRemaining: Int {
        guard let limit = wordLimit else { return 0 } // unlimited (pro) — not displayed
        return max(0, limit - totalWordsUsed)
    }

    var usageRatio: Double {
        guard let limit = wordLimit, limit > 0 else { return 0.0 }
        return min(1.0, Double(totalWordsUsed) / Double(limit))
    }

    var hasReachedLimit: Bool {
        guard let limit = wordLimit else { return false } // unlimited (pro)
        return totalWordsUsed >= limit
    }

    var isPro: Bool {
        plan == "pro"
    }

    /// Sync full state from server user-status response
    func syncFromServer(_ status: UserStatus) {
        self.totalWordsUsed = status.wordsUsed
        self.plan = status.plan
        // Only update wordLimit if server returned a value; keep default 2000 otherwise
        if status.plan == "pro" {
            self.wordLimit = nil // unlimited
        } else {
            self.wordLimit = status.wordLimit ?? 2000
        }
    }

    /// Update usage counters after a process call
    func updateAfterProcess(_ result: ProcessResult) {
        self.totalWordsUsed = result.wordsUsed
        if let limit = result.wordLimit {
            self.wordLimit = limit
        }
    }
}
