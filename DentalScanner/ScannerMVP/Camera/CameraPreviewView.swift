import AVFoundation
import SwiftUI
import UIKit

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    let videoOrientation: AVCaptureVideoOrientation

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.applyVideoOrientation(videoOrientation)
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        if uiView.previewLayer.session !== session {
            uiView.previewLayer.session = session
        }

        uiView.applyVideoOrientation(videoOrientation)
    }
}

final class PreviewView: UIView {
    private var desiredVideoOrientation: AVCaptureVideoOrientation = .landscapeRight

    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configurePreviewLayer()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configurePreviewLayer()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.frame = bounds
        applyDesiredVideoOrientationIfAvailable()
    }

    private func configurePreviewLayer() {
        backgroundColor = .black
        clipsToBounds = true
        previewLayer.videoGravity = .resizeAspectFill
    }

    func applyVideoOrientation(_ videoOrientation: AVCaptureVideoOrientation) {
        desiredVideoOrientation = videoOrientation
        applyDesiredVideoOrientationIfAvailable()
    }

    private func applyDesiredVideoOrientationIfAvailable() {
        guard let connection = previewLayer.connection,
              connection.isVideoOrientationSupported
        else {
            return
        }

        connection.videoOrientation = desiredVideoOrientation
    }
}
