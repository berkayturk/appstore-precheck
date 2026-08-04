import UnityAds
import PostHog

// Ad mediation + product analytics, the pairing most consumer apps ship.
enum Mediation {
    static func start() {
        UnityAds.initialize(gameId: "1234567", testMode: false)
        PostHogSDK.shared.setup(PostHogConfig(apiKey: "phc_demo"))
    }
}
