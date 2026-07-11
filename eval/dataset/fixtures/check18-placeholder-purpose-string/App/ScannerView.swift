import AVFoundation
import SwiftUI

struct ScannerView: View {
    var body: some View {
        VStack {
            Text("Point the camera at a document")
            Rectangle()
                .fill(.black.opacity(0.85))
                .frame(height: 320)
                .overlay(Text("camera preview").foregroundStyle(.white))
            Button("Scan") {
                AVCaptureDevice.requestAccess(for: .video) { _ in }
            }
        }
    }
}
