import StoreKit
import UIKit

enum ReviewPrompter {
    static func maybeRequestReview() {
        let launches = UserDefaults.standard.integer(forKey: "launchCount")
        guard launches >= 5 else { return }
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            SKStoreReviewController.requestReview(in: scene)
        }
    }
}
