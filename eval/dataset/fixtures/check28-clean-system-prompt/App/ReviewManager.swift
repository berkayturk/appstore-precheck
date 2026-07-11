import StoreKit
import UIKit

enum ReviewManager {
    /// Ask for a review through the system sheet after the user
    /// completes their tenth workout. Apple throttles frequency.
    static func maybeRequestReview(completedWorkouts: Int) {
        guard completedWorkouts == 10 else { return }
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            SKStoreReviewController.requestReview(in: scene)
        }
    }
}
