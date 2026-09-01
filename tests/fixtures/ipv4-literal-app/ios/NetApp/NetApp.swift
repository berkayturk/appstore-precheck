import SwiftUI
import Darwin

@main
struct NetApp: App {
    var body: some Scene { WindowGroup { ContentView() } }
}

struct ContentView: View {
    var body: some View {
        NavigationStack { Text("Hello") }
    }
}

// Legacy IPv4-only socket setup — fails on Apple's IPv6-only NAT64 review network.
func connectLegacy() {
    var addr = sockaddr_in()
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_addr.s_addr = inet_addr("198.51.100.7")
    let host = gethostbyname("api.example.com")
    _ = host
}

let telemetryHost = "http://203.0.113.10:8080/collect"
