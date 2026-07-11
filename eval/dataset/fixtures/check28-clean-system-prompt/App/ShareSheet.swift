import SwiftUI

struct ShareSheet: View {
    // plain store page link used by the "Share with a friend" feature
    private let appStoreLink = URL(string: "https://apps.apple.com/app/id987654321")!

    var body: some View {
        ShareLink(item: appStoreLink) {
            Label("Share TrailRun with a friend", systemImage: "square.and.arrow.up")
        }
    }
}
