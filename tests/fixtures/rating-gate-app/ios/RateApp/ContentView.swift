import SwiftUI
import StoreKit

@main
struct RateApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                FeedbackGateView()
            }
        }
    }
}

struct FeedbackGateView: View {
    @Environment(\.requestReview) private var requestReview
    var body: some View {
        VStack {
            Text("Enjoying the app?")
            Button("Yes!") { requestReview() }
            Button("Not really") { openFeedbackForm() }
        }
    }

    func openFeedbackForm() {}
}
