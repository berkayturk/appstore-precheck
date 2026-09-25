import Shared
import SwiftUI

@main
struct PrecheckApp: App {
    let corpus = CorpusStatus()
    @State private var status = "Ready"
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                List {
                    Text(corpus.title())
                    Button(corpus.accountAction()) { status = "Account deleted" }
                    Button(corpus.communityAction()) { status = "Report submitted" }
                    Button("Restore Purchases") { status = "Restore request completed" }
                    Text(status)
                }.navigationTitle("KMP Clean")
            }
        }
    }
}
