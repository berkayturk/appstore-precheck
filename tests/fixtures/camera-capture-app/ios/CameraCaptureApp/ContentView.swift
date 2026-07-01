import SwiftUI
import AVFoundation

final class CameraController: NSObject {
  let session = AVCaptureSession()

  func configure() {
    guard let device = AVCaptureDevice.default(for: .video) else { return }
    if let input = try? AVCaptureDeviceInput(device: device) {
      session.addInput(input)
    }
    session.startRunning()
  }
}

struct ContentView: View {
  let camera = CameraController()

  var body: some View {
    TabView {
      Text("Camera")
    }
    .onAppear { camera.configure() }
  }
}
