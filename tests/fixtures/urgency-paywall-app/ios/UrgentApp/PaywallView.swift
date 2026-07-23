import SwiftUI
import StoreKit

struct PaywallView: View {
    @State private var timeRemaining = 3600
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack {
            Text("Limited time offer — 50% off ends soon!")
            Text("Only today: unlock everything.")
            Button("Subscribe") { purchase() }
            Button("Restore Purchases") { restore() }
            Link("Terms of Use", destination: URL(string: "https://example.app/legal/tos")!)
            Link("Privacy Policy", destination: URL(string: "https://example.app/legal/privacy")!)
        }
        .onReceive(timer) { _ in timeRemaining -= 1 }
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
