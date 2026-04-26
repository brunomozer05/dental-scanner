import AVFoundation
import SwiftUI
import UIKit

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    let orientation: CameraPreviewOrientation
    let orientationRevision: Int

    func makeUIView(context: Context) -> PreviewContainerView {
        let view = PreviewContainerView()
        view.previewLayer.videoGravity = .resizeAspectFill
        view.previewLayer.session = session
        view.setOrientation(orientation)
        return view
    }

    func updateUIView(_ uiView: PreviewContainerView, context: Context) {
        if uiView.previewLayer.session !== session {
            uiView.previewLayer.session = session
        }

        _ = orientationRevision
        uiView.setOrientation(orientation)
    }
}

final class PreviewContainerView: UIView {
    private var desiredOrientation: CameraPreviewOrientation = .landscapeRight

    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        guard let layer = layer as? AVCaptureVideoPreviewLayer else {
            fatalError("Expected AVCaptureVideoPreviewLayer")
        }

        return layer
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.frame = bounds
        applyDesiredOrientation()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        applyDesiredOrientation()
    }

    func setOrientation(_ orientation: CameraPreviewOrientation) {
        desiredOrientation = orientation
        applyDesiredOrientation()
    }

    private func applyDesiredOrientation() {
        guard let connection = previewLayer.connection,
              connection.isVideoOrientationSupported
        else {
            return
        }

        connection.videoOrientation = desiredOrientation.captureVideoOrientation
    }
}
