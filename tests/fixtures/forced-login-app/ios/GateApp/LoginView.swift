import SwiftUI

@main
struct GateApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                LoginView()
            }
        }
    }
}

struct LoginView: View {
    @State private var email = ""
    @State private var password = ""
    var body: some View {
        VStack {
            TextField("Email", text: $email)
            SecureField("Password", text: $password)
            Button("Sign In") { signIn() }
        }
    }

    func signIn() {}
}
