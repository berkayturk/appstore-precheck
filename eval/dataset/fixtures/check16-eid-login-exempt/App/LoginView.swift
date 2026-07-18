import SwiftUI
import BankIDSDK

struct LoginView: View {
    @State private var isAuthenticating = false

    var body: some View {
        VStack(spacing: 24) {
            Image("skattefil-logo")
            Text("Skattefil")
                .font(.largeTitle.bold())
            Text("File your Swedish tax return securely. Identify yourself with BankID to continue.")
                .multilineTextAlignment(.center)
            Button {
                isAuthenticating = true
                BankIDClient.shared.authenticate(personalNumber: nil) { result in
                    isAuthenticating = false
                    handle(result)
                }
            } label: {
                Label("Identify with BankID", image: "bankid-glyph")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isAuthenticating)
        }
        .padding()
    }

    private func handle(_ result: BankIDResult) {
        // Session established from the BankID identity token only.
    }
}
