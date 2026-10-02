import SwiftUI

@main
struct PrecheckApp: App {
    init() {
        // Intentional deterministic launch crash for dyn-launch's N=3 quorum.
        fatalError("corpus intentional launch crash")
    }

    var body: some Scene {
        WindowGroup { Text("Unreachable") }
    }
}
