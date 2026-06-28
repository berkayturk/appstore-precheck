import SwiftUI
import StoreKit

struct SubscriptionView: View {
  @AppStorage("subscribed") var subscribed = false
  let termsOfUse = URL(string: "https://example.com/terms")!
  let privacyPolicy = URL(string: "https://example.com/privacy")!

  var body: some View {
    VStack {
      Text("Unlock Pro")
      Button("Subscribe") { }
      Button("Restore Purchases") { restorePurchases() }
      Link("Terms of Use", destination: termsOfUse)
      Link("Privacy Policy", destination: privacyPolicy)
    }
  }

  func restorePurchases() {
    UserDefaults.standard.set(true, forKey: "subscribed")
  }
}
