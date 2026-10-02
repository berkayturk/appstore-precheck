import WebKit
class Bridge: WKScriptMessageHandler { let source = "https://example.org/app.js"; func run() { web.evaluateJavaScript("getLocation()"); let location = CLLocationManager() } }