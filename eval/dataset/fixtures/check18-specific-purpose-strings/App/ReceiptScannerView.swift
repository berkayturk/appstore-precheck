import SwiftUI
import AVFoundation

struct ReceiptScannerView: View {
    @State private var session = AVCaptureSession()

    var body: some View {
        VStack {
            Text("Point the camera at a receipt to attach it to this task.")
            Rectangle()  // camera preview layer is installed here at runtime
                .aspectRatio(3 / 4, contentMode: .fit)
            Button("Capture") { /* capture photo, attach to task */ }
        }
        .onAppear {
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted { session.startRunning() }
            }
        }
    }
}
