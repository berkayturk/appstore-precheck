import SwiftUI
import StoreKit

// StoreKit 2 paywall: AppStore.sync() behind a capitalized button label, and
// legal links carrying human-readable labels with nonstandard URL paths.
// A compliant paywall — the scanner must not FAIL any 3.1.2 link check.
struct PaywallView: View {
  // Plain model property; NOT a filesystem timestamp API. Must not trip the
  // FileTimestamp Required Reason check.
  let creationDate = Date()

  var body: some View {
    VStack {
      Text("Go Pro")
      Button("Subscribe") {
        Task { _ = try? await Product.products(for: ["pro.yearly"]) }
      }
      Button("Restore Purchases") {
        Task { try? await AppStore.sync() }
      }
      Link("Terms of Use", destination: URL(string: "https://example.com/legal/tos")!)
      Link("Privacy Policy", destination: URL(string: "https://example.com/datenschutz")!)
    }
  }
}
