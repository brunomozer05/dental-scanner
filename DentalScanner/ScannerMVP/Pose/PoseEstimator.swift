import CoreGraphics
import Foundation
import simd

final class PoseEstimator {
    enum EstimatorError: LocalizedError {
        case missingCameraIntrinsics
        case invalidCameraIntrinsics
        case invalidMarkerSize
        case invalidBridgeVector(name: String, count: Int)

        var errorDescription: String? {
            switch self {
            case .missingCameraIntrinsics:
                return "Camera intrinsics are unavailable for this frame."
            case .invalidCameraIntrinsics:
                return "Camera intrinsics are invalid for pose estimation."
            case .invalidMarkerSize:
                return "Marker size must be greater than zero."
            case let .invalidBridgeVector(name, count):
                return "OpenCV returned \(count) values for \(name); expected 3."
            }
        }
    }

    private let bridge: OpenCVArucoPoseBridge

    init(bridge: OpenCVArucoPoseBridge = OpenCVArucoPoseBridge()) {
        self.bridge = bridge
    }

    func estimatePoses(
        for detections: [ArUcoDetectionResult],
        in frame: CameraFrame,
        markerSizeMillimeters: Double
    ) throws -> [PoseResult] {
        guard !detections.isEmpty else {
            return []
        }

        guard let intrinsicMatrix = frame.metadata.intrinsicMatrix else {
            throw EstimatorError.missingCameraIntrinsics
        }

        guard let intrinsics = CameraIntrinsics(matrix: intrinsicMatrix) else {
            throw EstimatorError.invalidCameraIntrinsics
        }

        return try estimatePoses(
            for: detections,
            intrinsics: intrinsics,
            markerSizeMillimeters: markerSizeMillimeters
        )
    }

    func estimatePoses(
        for detections: [ArUcoDetectionResult],
        intrinsics: CameraIntrinsics,
        markerSizeMillimeters: Double
    ) throws -> [PoseResult] {
        guard markerSizeMillimeters.isFinite, markerSizeMillimeters > 0 else {
            throw EstimatorError.invalidMarkerSize
        }

        return try detections.map { detection in
            try estimatePose(
                for: detection,
                intrinsics: intrinsics,
                markerSizeMillimeters: markerSizeMillimeters
            )
        }
    }

    private func estimatePose(
        for detection: ArUcoDetectionResult,
        intrinsics: CameraIntrinsics,
        markerSizeMillimeters: Double
    ) throws -> PoseResult {
        let corners = detection.corners.map { corner in
            OpenCVArucoImagePoint(x: Double(corner.x), y: Double(corner.y))
        }

        let bridgeResult = try bridge.estimatePose(
            corners: corners,
            markerSizeMillimeters: markerSizeMillimeters,
            focalLengthX: intrinsics.focalLengthX,
            focalLengthY: intrinsics.focalLengthY,
            principalPointX: intrinsics.principalPointX,
            principalPointY: intrinsics.principalPointY
        )

        return PoseResult(
            markerId: detection.markerId,
            rotationVector: try vector3(from: bridgeResult.rotationVector, name: "rotationVector"),
            translationVector: try vector3(from: bridgeResult.translationVector, name: "translationVector"),
            distanceMm: bridgeResult.distanceMm,
            reprojectionError: bridgeResult.reprojectionError
        )
    }

    private func vector3(from values: [NSNumber], name: String) throws -> SIMD3<Double> {
        guard values.count == 3 else {
            throw EstimatorError.invalidBridgeVector(name: name, count: values.count)
        }

        return SIMD3(values[0].doubleValue, values[1].doubleValue, values[2].doubleValue)
    }
}
