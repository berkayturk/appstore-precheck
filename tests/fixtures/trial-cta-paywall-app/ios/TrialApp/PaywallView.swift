import SwiftUI
import StoreKit

struct PaywallView: View {
    @State private var trialEnabled = true
    var body: some View {
        VStack {
            Text("Unlock everything with Premium.")
            // The 2026 rejection pattern: a trial switch on the paywall.
            Toggle("Free trial enabled", isOn: $trialEnabled)
            Button("Start your free trial") { purchase() }
            Button("Ücretsiz denemeyi başlat") { purchase() }
            Button("Subscribe — $29.99/year") { purchase() }
            Text(String(localized: "common.continue"))
            Button("Restore Purchases") { restore() }
            Link("Terms of Use", destination: URL(string: "https://example.app/legal/tos")!)
            Link("Privacy Policy", destination: URL(string: "https://example.app/legal/privacy")!)
        }
    }

    func purchase() {
        Task {
            let products = try await Product.products(for: ["premium.yearly"])
            _ = try await products.first?.purchase()
        }
    }

    func restore() {
        Task { try await AppStore.sync() }
    }
}
