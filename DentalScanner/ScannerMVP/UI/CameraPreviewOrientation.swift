import AVFoundation
import CoreGraphics
import UIKit

enum CameraPreviewOrientation: Equatable {
    case portrait
    case portraitUpsideDown
    case landscapeLeft
    case landscapeRight

    init?(deviceOrientation: UIDeviceOrientation) {
        guard let resolvedVideoOrientation = videoOrientation(from: deviceOrientation) else {
            return nil
        }

        self.init(videoOrientation: resolvedVideoOrientation)
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

    init(videoOrientation: AVCaptureVideoOrientation) {
        switch videoOrientation {
        case .portrait:
            self = .portrait
        case .portraitUpsideDown:
            self = .portraitUpsideDown
        case .landscapeLeft:
            self = .landscapeLeft
        case .landscapeRight:
            self = .landscapeRight
        @unknown default:
            self = .landscapeRight
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
}

func videoOrientation(from deviceOrientation: UIDeviceOrientation) -> AVCaptureVideoOrientation? {
    switch deviceOrientation {
    case .landscapeLeft:
        return .landscapeRight
    case .landscapeRight:
        return .landscapeLeft
    case .portrait:
        return .portrait
    case .portraitUpsideDown:
        return .portraitUpsideDown
    default:
        return nil
    }
}
