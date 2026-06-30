import SwiftUI
import WebKit

struct WebView: UIViewRepresentable {
  func makeUIView(context: Context) -> WKWebView { WKWebView() }
  func updateUIView(_ view: WKWebView, context: Context) {
    view.load(URLRequest(url: URL(string: "https://example.com")!))
  }
}

@main
struct WebApp: App {
  var body: some Scene {
    WindowGroup { WebView() }
  }
}
