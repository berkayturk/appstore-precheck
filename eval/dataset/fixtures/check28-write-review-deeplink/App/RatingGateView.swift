import SwiftUI

struct RatingGateView: View {
    @State private var stars = 0
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 16) {
            Text("How would you rate FitPulse?")
                .font(.headline)
            HStack {
                ForEach(1...5, id: \.self) { star in
                    Image(systemName: star <= stars ? "star.fill" : "star")
                        .onTapGesture { stars = star }
                }
            }
            Button("Submit") {
                if stars >= 4 {
                    // happy users go straight to the App Store review sheet
                    openURL(URL(string: "itms-apps://itunes.apple.com/app/id987654321?action=write-review")!)
                } else {
                    // unhappy users are kept off the App Store
                    openURL(URL(string: "https://fitpulse.example/feedback")!)
                }
            }
        }
    }
}
