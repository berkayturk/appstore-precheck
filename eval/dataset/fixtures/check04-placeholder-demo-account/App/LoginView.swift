import SwiftUI

struct LoginView: View {
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        Form {
            TextField("Email", text: $email)
            SecureField("Password", text: $password)
            Button("Sign In") { /* auth request */ }
        }
        .navigationTitle("Sign In")
    }
}
