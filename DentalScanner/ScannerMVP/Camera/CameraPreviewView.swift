import AVFoundation
import SwiftUI
import UIKit

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    let orientation: CameraPreviewOrientation
    let orientationRevision: Int

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer?.session = session
        view.setOrientation(orientation)
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        if let previewLayer = uiView.previewLayer,
           previewLayer.session !== session {
            previewLayer.session = session
        }

        _ = orientationRevision
        uiView.setOrientation(orientation)
    }
}

final class PreviewView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer? {
        layer as? AVCaptureVideoPreviewLayer
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
        previewLayer?.frame = bounds
        previewLayer?.videoGravity = .resizeAspectFill
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
    }

    func setOrientation(_ orientation: CameraPreviewOrientation) {
        _ = orientation
    }

    private func configurePreviewLayer() {
        backgroundColor = .black
        clipsToBounds = true
        contentMode = .scaleAspectFill
        previewLayer?.videoGravity = .resizeAspectFill
    }
}
