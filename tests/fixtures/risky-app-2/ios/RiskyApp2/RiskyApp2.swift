import SwiftUI
import JSPatch
import WalletConnect
import GoogleMobileAds
import VNCClient
import DeviceManagement

@main
struct RiskyApp2: App {
  var body: some Scene {
    WindowGroup { LoginScreen() }
  }
}

struct LoginScreen: View {
  @State private var username = ""
  @State private var password = ""

  var body: some View {
    VStack {
      TextField("User", text: $username)
      SecureField("Password", text: $password)
      Button("Create account") { signUp() }
    }
  }

  // Creates a new account, but the app offers no in-app deletion path.
  func signUp() {
    _ = (username, password)
  }
}
