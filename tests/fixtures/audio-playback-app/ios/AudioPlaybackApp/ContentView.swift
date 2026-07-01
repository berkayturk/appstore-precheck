import SwiftUI
import AVFoundation

struct ContentView: View {
  @AppStorage("seen") var seen = false
  let player = try? AVAudioPlayer(contentsOf: Bundle.main.url(forResource: "chime", withExtension: "m4a")!)

  var body: some View {
    TabView {
      Text("Home")
    }
    .onAppear {
      try? AVAudioSession.sharedInstance().setCategory(.playback)
      try? AVAudioSession.sharedInstance().setActive(true)
      player?.play()
    }
  }
}
