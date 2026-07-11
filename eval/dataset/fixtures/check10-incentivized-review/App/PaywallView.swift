import SwiftUI

struct PaywallView: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("Go Premium")
                .font(.title)
            Text("Unlimited lists, custom themes, and cloud sync.")
            Button("Subscribe — $2.99/month") { /* purchase */ }
            Text("Leave a 5-star review and get 1 week of Premium free!")
                .font(.footnote)
        }
        .padding()
    }
}
