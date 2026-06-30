import SwiftUI
import Stripe
import HealthKit
import CloudKit
import PassKit
import NetworkExtension

@main
struct RiskyApp: App {
  var body: some Scene {
    WindowGroup {
      NavigationStack {
        ContentView()
      }
    }
  }
}

struct ContentView: View {
  let store = HKHealthStore()
  let container = CKContainer.default()

  var body: some View {
    VStack {
      Button("Post") { createPost(text: "hello") }
      // A direct write-review deep link instead of the system prompt.
      Link("Rate us", destination: URL(string: "https://apps.apple.com/app/id123?action=write-review")!)
    }
  }

  func createPost(text: String) {
    // publishes user content directly, with no safety affordance
    _ = text
  }

  // recurring billing through Apple Pay
  func payRecurring() {
    let req = PKRecurringPaymentRequest(paymentDescription: "Pro", regularBilling: .init(label: "Pro", amount: 5), managementURL: URL(string: "https://example.com")!)
    _ = req
  }

  func startTunnel() {
    let mgr = NEVPNManager.shared()
    _ = mgr
  }
}
