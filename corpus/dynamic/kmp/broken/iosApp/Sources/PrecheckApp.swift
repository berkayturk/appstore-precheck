import Shared
import SwiftUI

@main
struct PrecheckApp: App {
    let corpus = CorpusStatus()
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                List {
                    Text(corpus.title())
                    Text(corpus.accountAction())
                    Text(corpus.communityAction())
                    Button("Restore Purchases") {}
                }.navigationTitle("KMP Broken")
            }
        }
    }
}
