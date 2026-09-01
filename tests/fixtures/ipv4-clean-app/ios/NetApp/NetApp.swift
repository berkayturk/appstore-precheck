import SwiftUI
import Network

@main
struct NetApp: App {
    var body: some Scene { WindowGroup { ContentView() } }
}

struct ContentView: View {
    var body: some View {
        NavigationStack { Text("Hello") }
    }
}

// Everything here must stay silent under §55:
//   127.0.0.1 in a comment, and 10.0.0.0/8 as a CIDR in prose.
func connectModern() {
    var addr6 = sockaddr_in6()
    addr6.sin6_family = sa_family_t(AF_INET6)
    let loopback = "127.0.0.1"          // loopback is never the review network's problem
    let any = "0.0.0.0"                 // bind-any, not a destination
    let cidr = "192.0.2.0/24"           // a CIDR range, not a host
    let version = "Client/1.2.3.4"      // a version string that merely looks like an address
    let bogus = "999.1.1.1"             // not a valid dotted quad
    let conn = NWConnection(host: "api.example.com", port: 443, using: .tls)
    _ = (addr6, loopback, any, cidr, version, bogus, conn)
}
