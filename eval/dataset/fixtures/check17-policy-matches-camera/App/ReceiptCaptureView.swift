import AVFoundation
import SwiftUI
import Vision

struct ReceiptCaptureView: View {
    var body: some View {
        VStack {
            Text("Scan a receipt")
            Rectangle()
                .fill(.black.opacity(0.85))
                .frame(height: 320)
                .overlay(Text("camera preview").foregroundStyle(.white))
            Button("Capture") {
                AVCaptureDevice.requestAccess(for: .video) { _ in }
            }
        }
    }

    /// On-device OCR of the captured receipt; nothing leaves the device.
    func recognizeTotals(in image: CGImage) {
        let request = VNRecognizeTextRequest()
        try? VNImageRequestHandler(cgImage: image).perform([request])
    }
}
