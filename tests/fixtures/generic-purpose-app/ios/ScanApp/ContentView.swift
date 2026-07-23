import SwiftUI
import AVFoundation

@main
struct ScanApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                Text("Documents")
            }
        }
    }
}

final class Recorder {
    let session = AVCaptureSession()

    func startCapture() {
        AVCaptureDevice.requestAccess(for: .video) { _ in }
    }

    func record() {
        let recorder = try? AVAudioRecorder(url: URL(fileURLWithPath: "/tmp/a.m4a"), settings: [:])
        recorder?.record()
    }
}
