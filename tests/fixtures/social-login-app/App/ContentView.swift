import SwiftUI
import GoogleSignIn

struct ContentView: View {
    var body: some View {
        TabView {
            Button("Sign in with Google") {
                GIDSignIn.sharedInstance.signIn(withPresenting: UIViewController()) { _, _ in }
            }
        }
    }
}
