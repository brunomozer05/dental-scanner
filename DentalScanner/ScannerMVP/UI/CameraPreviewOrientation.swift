import AVFoundation
import CoreGraphics
import UIKit

enum CameraPreviewOrientation: Equatable {
    case portrait
    case portraitUpsideDown
    case landscapeLeft
    case landscapeRight

    init?(deviceOrientation: UIDeviceOrientation) {
        switch deviceOrientation {
        case .portrait:
            self = .portrait
        case .portraitUpsideDown:
            self = .portraitUpsideDown
        case .landscapeLeft:
            self = .landscapeRight
        case .landscapeRight:
            self = .landscapeLeft
        default:
            return nil
        }
    }

    init?(interfaceOrientation: UIInterfaceOrientation) {
        switch interfaceOrientation {
        case .portrait:
            self = .portrait
        case .portraitUpsideDown:
            self = .portraitUpsideDown
        case .landscapeLeft:
            self = .landscapeLeft
        case .landscapeRight:
            self = .landscapeRight
        default:
            return nil
        }
    }

    var captureVideoOrientation: AVCaptureVideoOrientation {
        switch self {
        case .portrait:
            return .portrait
        case .portraitUpsideDown:
            return .portraitUpsideDown
        case .landscapeLeft:
            return .landscapeLeft
        case .landscapeRight:
            return .landscapeRight
        }
    }

    func orientedFrameSize(width: CGFloat, height: CGFloat) -> CGSize {
        switch self {
        case .portrait, .portraitUpsideDown:
            return CGSize(width: width, height: height)
        case .landscapeLeft, .landscapeRight:
            return CGSize(width: height, height: width)
        }
    }

    func orientedPoint(_ point: CGPoint, frameWidth: CGFloat, frameHeight: CGFloat) -> CGPoint {
        switch self {
        case .portrait:
            return point
        case .portraitUpsideDown:
            return CGPoint(x: frameWidth - point.x, y: frameHeight - point.y)
        case .landscapeLeft:
            return CGPoint(x: point.y, y: frameWidth - point.x)
        case .landscapeRight:
            return CGPoint(x: frameHeight - point.y, y: point.x)
        }
    }
}
