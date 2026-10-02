import WebKit
class Bridge: WKScriptMessageHandler { func run() { web.evaluateJavaScript("document.title") } }