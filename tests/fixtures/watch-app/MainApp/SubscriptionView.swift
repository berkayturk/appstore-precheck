import SwiftUI
import StoreKit
struct SubscriptionView: View {
    var body: some View {
        VStack {
            Button("Restore Purchases") { restorePurchases() }
            Link("Terms of Use", destination: URL(string: "https://example.com/terms")!)
            Link("Privacy Policy", destination: URL(string: "https://example.com/privacy")!)
        }
    }
    func restorePurchases() {}
}
