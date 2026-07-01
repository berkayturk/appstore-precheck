import AVFoundation

struct CameraView {
    func makeCaptureDevice() -> AVCaptureDevice? {
        AVCaptureDevice.default(for: .video)
    }
}
