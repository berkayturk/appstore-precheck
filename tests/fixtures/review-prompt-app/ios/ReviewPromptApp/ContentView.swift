import SwiftUI
import StoreKit

struct ContentView: View {
  var body: some View {
    VStack {
      Text("Welcome")
      Button("Rate us") { requestReview() }
    }
  }

  func requestReview() {
    if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
      SKStoreReviewController.requestReview(in: scene)
    }
  }
}
