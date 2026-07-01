import SwiftUI
import AVFoundation

final class VoiceRecorderController: NSObject {
  var recorder: AVAudioRecorder?

  func configure() {
    let session = AVAudioSession.sharedInstance()
    try? session.setCategory(.playAndRecord, mode: .default)
    try? session.setActive(true)

    let url = FileManager.default.temporaryDirectory.appendingPathComponent("recording.m4a")
    let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC]
    recorder = try? AVAudioRecorder(url: url, settings: settings)
    recorder?.record()
  }
}

struct ContentView: View {
  let recorder = VoiceRecorderController()

  var body: some View {
    TabView {
      Text("Record")
    }
    .onAppear { recorder.configure() }
  }
}
