import StoreKit
import SwiftUI

struct FeedbackBanner: View {
    @Environment(\.requestReview) private var requestReview

    var body: some View {
        VStack(spacing: 8) {
            Text("Enjoying GardenLog?")
                .font(.headline)
            Text("We'd love to hear what you think.")
                .font(.subheadline)
            Button("Leave a review") {
                requestReview()
            }
        }
        .padding()
    }
}
