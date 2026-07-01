import SwiftUI
import UIKit

struct ContentView: View {
  @State private var s = 0
  var body: some View {
    Picker("x", selection: $s) {
      Text("One").tag(0)
      Text("Two").tag(1)
    }
    .pickerStyle(SegmentedPickerStyle())
  }
}

let seg = UISegmentedControl()
