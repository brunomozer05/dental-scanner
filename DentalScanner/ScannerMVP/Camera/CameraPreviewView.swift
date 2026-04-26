import AVFoundation
import SwiftUI
import UIKit

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    let orientation: CameraPreviewOrientation
    let orientationRevision: Int

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.setOrientation(orientation)
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        if uiView.previewLayer.session !== session {
            uiView.previewLayer.session = session
        }

        _ = orientationRevision
        uiView.setOrientation(orientation)
    }
}

final class PreviewView: UIView {
    private var desiredOrientation: CameraPreviewOrientation = .landscapeRight

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
        previewLayer.videoGravity = .resizeAspectFill
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

    private func configurePreviewLayer() {
        backgroundColor = .black
        clipsToBounds = true
        contentMode = .scaleAspectFill
        previewLayer.videoGravity = .resizeAspectFill
    }
}
