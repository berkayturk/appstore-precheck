import SwiftUI

// A remote-config downloader. `fetchAssets` here means JSON config assets, not
// photos: no PhotoKit type is referenced anywhere in the app.
final class ConfigurationLoader {
    private var assets: [String] = []

    func fetchAssets() {
        assets = ["rules.json", "tds.json"]
    }

    func fetchAssetsFor(_ name: String) -> String? {
        assets.first { $0 == name }
    }
}

struct ContentView: View {
    private let loader = ConfigurationLoader()

    var body: some View {
        TabView {
            Text("Home").onAppear { loader.fetchAssets() }
            Text("Settings")
        }
    }
}
