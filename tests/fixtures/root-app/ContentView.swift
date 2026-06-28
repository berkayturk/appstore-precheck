import SwiftUI
struct ContentView: View {
  @AppStorage("seen") var seen = false
  var body: some View { TabView { Text("Home") } }
}
