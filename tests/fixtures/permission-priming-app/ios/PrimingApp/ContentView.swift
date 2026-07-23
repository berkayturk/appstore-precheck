import SwiftUI
import AVFoundation

// Fixture: a permission-priming onboarding screen whose consent CTA steers the
// user toward granting access. §42 permission-priming-cta must flag both the
// String Catalog CTA ("Allow and continue") and the hardcoded literal below,
// while leaving the post-denial Settings guidance string alone.
struct ContentView: View {
    var body: some View {
        NavigationStack {
            VStack {
                Text(String(localized: "onboarding.permissions.title"))
                Button(String(localized: "onboarding.permissions.cta")) {
                    requestMicAccess()
                }
                Button("Grant access to start") {
                    requestMicAccess()
                }
                Button("İzin ver ve devam et") {
                    requestMicAccess()
                }
            }
        }
    }

    private func requestMicAccess() {
        AVAudioApplication.requestRecordPermission { _ in }
    }
}
