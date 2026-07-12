import SwiftUI
import HomeKit

struct WallpaperGridView: View {
    private let manager = HMHomeManager()
    let categories = ["Nature", "Abstract", "Minimal", "Space"]

    var body: some View {
        NavigationStack {
            List(categories, id: \.self) { category in
                Text(category)
            }
            .navigationTitle("Wallpapers")
        }
    }
}
