import CoreGraphics
import CoreVideo
import Foundation

final class ArUcoDetector {
    enum DetectorError: LocalizedError {
        case invalidCornerCount(markerId: Int, count: Int)

        var errorDescription: String? {
            switch self {
            case let .invalidCornerCount(markerId, count):
                return "ArUco marker \(markerId) returned \(count) corners instead of 4."
            }
        }
    }

    private let bridge: OpenCVArucoPoseBridge

    init(bridge: OpenCVArucoPoseBridge = OpenCVArucoPoseBridge()) {
        self.bridge = bridge
    }

    func detectMarkers(in frame: CameraFrame) throws -> [ArUcoDetectionResult] {
        guard bridge.isOpenCVAvailable else {
            return []
        }

        let detections = try bridge.detectAruco4x4Markers(in: frame.pixelBuffer)

        return try detections.map { detection in
            let corners = detection.corners.map { corner in
                CGPoint(x: corner.x, y: corner.y)
            }

            guard corners.count == 4 else {
                throw DetectorError.invalidCornerCount(markerId: detection.markerId, count: corners.count)
            }

            return ArUcoDetectionResult(markerId: detection.markerId, corners: corners)
        }
    }
}
