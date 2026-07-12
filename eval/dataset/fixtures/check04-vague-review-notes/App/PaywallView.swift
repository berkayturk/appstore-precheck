import SwiftUI

struct PaywallView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("FocusShield Premium")
                .font(.title2)
            Text("App blocking, schedules, and reports require a subscription.")
            Button("Subscribe — $4.99/month") { /* StoreKit purchase */ }
        }
    }
}
