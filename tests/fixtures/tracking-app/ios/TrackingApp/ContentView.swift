import SwiftUI
import GoogleMobileAds
import FirebaseAnalytics

struct ContentView: View {
    var body: some View {
        TabView {
            Text("Home")
                .onAppear {
                    Analytics.logEvent("home_open", parameters: nil)
                    GADMobileAds.sharedInstance().start(completionHandler: nil)
                }
        }
    }
}
