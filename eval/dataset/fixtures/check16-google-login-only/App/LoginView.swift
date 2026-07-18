import SwiftUI
import GoogleSignIn

struct LoginView: View {
    var body: some View {
        VStack(spacing: 24) {
            Image("recipebox-logo")
            Text("RecipeBox")
                .font(.largeTitle.bold())
            Text("Sign in to sync your recipes, meal plans, and shopping lists across devices.")
                .multilineTextAlignment(.center)
            GoogleSignInButton {
                GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController()) { result, error in
                    guard let profile = result?.user.profile else { return }
                    SessionStore.shared.start(email: profile.email, name: profile.name)
                }
            }
        }
        .padding()
    }
}
