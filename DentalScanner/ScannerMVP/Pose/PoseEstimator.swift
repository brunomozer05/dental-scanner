import CoreGraphics
import Foundation
import simd

final class PoseEstimator {
    private enum DualArucoV2PoseSelection {
        static let maximumPreferredDualTagReprojectionError = 2.0
    }

    enum EstimatorError: LocalizedError {
        case missingCameraIntrinsics
        case invalidCameraIntrinsics
        case invalidMarkerSize
        case invalidBridgeVector(name: String, count: Int, expected: Int)

        var errorDescription: String? {
            switch self {
            case .missingCameraIntrinsics:
                return "Camera intrinsics are unavailable for this frame."
            case .invalidCameraIntrinsics:
                return "Camera intrinsics are invalid for pose estimation."
            case .invalidMarkerSize:
                return "Marker size must be greater than zero."
            case let .invalidBridgeVector(name, count, expected):
                return "OpenCV returned \(count) values for \(name); expected \(expected)."
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
        markerSizeMillimeters: Double,
        markerProfile: MarkerProfile = .singleArucoV1,
        dualMarkers: [DualArucoMarkerDefinition] = MarkerConfiguration.dualMarkers
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
            markerSizeMillimeters: markerSizeMillimeters,
            markerProfile: markerProfile,
            dualMarkers: dualMarkers
        )
    }

    func estimatePoses(
        for detections: [ArUcoDetectionResult],
        intrinsics: CameraIntrinsics,
        markerSizeMillimeters: Double,
        markerProfile: MarkerProfile = .singleArucoV1,
        dualMarkers: [DualArucoMarkerDefinition] = MarkerConfiguration.dualMarkers
    ) throws -> [PoseResult] {
        switch markerProfile {
        case .singleArucoV1:
            guard markerSizeMillimeters.isFinite, markerSizeMillimeters > 0 else {
                throw EstimatorError.invalidMarkerSize
            }

            return try detections.map { detection in
                try estimateSingleArucoV1Pose(
                    for: detection,
                    intrinsics: intrinsics,
                    markerSizeMillimeters: markerSizeMillimeters
                )
            }
        case .dualArucoV2:
            return try estimateDualArucoV2Poses(
                for: detections,
                intrinsics: intrinsics,
                dualMarkers: dualMarkers
            )
        }
    }

    private func estimateSingleArucoV1Pose(
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
            cameraMatrix: intrinsics.openCVCameraMatrixValues
        )

        return PoseResult(
            markerId: detection.markerId,
            markerProfile: .singleArucoV1,
            poseSource: .singleArucoV1,
            rotationVector: try vector3(from: bridgeResult.rotationVector, name: "rotationVector"),
            rotationMatrix: try matrix3x3(from: bridgeResult.rotationMatrix, name: "rotationMatrix"),
            translationVector: try vector3(from: bridgeResult.translationVector, name: "translationVector"),
            distanceMm: bridgeResult.distanceMm,
            reprojectionError: bridgeResult.reprojectionError,
            markerAreaPixels: Self.markerAreaPixels(for: detection.corners),
            usedPointCount: 4
        )
    }

    private func estimateDualArucoV2Poses(
        for detections: [ArUcoDetectionResult],
        intrinsics: CameraIntrinsics,
        dualMarkers: [DualArucoMarkerDefinition]
    ) throws -> [PoseResult] {
        var detectionsByTagId: [Int: ArUcoDetectionResult] = [:]
        for detection in detections {
            detectionsByTagId[detection.markerId] = detection
        }

        var poseResults: [PoseResult] = []
        poseResults.reserveCapacity(dualMarkers.count)

        for definition in dualMarkers {
            let topDetection = detectionsByTagId[definition.topTagId]
            let bottomDetection = detectionsByTagId[definition.bottomTagId]

            guard let poseResult = estimateBestDualArucoV2Pose(
                for: definition,
                topDetection: topDetection,
                bottomDetection: bottomDetection,
                intrinsics: intrinsics
            ) else {
                continue
            }

            poseResults.append(poseResult)
        }

        return poseResults
    }

    private func estimateBestDualArucoV2Pose(
        for definition: DualArucoMarkerDefinition,
        topDetection: ArUcoDetectionResult?,
        bottomDetection: ArUcoDetectionResult?,
        intrinsics: CameraIntrinsics
    ) -> PoseResult? {
        var dualTagPoseCandidate: PoseResult?

        if let topDetection,
           let bottomDetection,
           let dualTagPose = try? estimateDualTagPose(
                for: definition,
                topDetection: topDetection,
                bottomDetection: bottomDetection,
                intrinsics: intrinsics
           ) {
            if dualTagPose.reprojectionError.isFinite &&
                dualTagPose.reprojectionError <=
                DualArucoV2PoseSelection.maximumPreferredDualTagReprojectionError {
                return dualTagPose
            }

            dualTagPoseCandidate = dualTagPose
        }

        if let topDetection,
           let topFallbackPose = try? estimateSingleTagFallbackPose(
                for: definition,
                detection: topDetection,
                role: .top,
                intrinsics: intrinsics
           ) {
            return topFallbackPose
        }

        if let bottomDetection,
           let bottomFallbackPose = try? estimateSingleTagFallbackPose(
                for: definition,
                detection: bottomDetection,
                role: .bottom,
                intrinsics: intrinsics
           ) {
            return bottomFallbackPose
        }

        return dualTagPoseCandidate
    }

    private func estimateDualTagPose(
        for definition: DualArucoMarkerDefinition,
        topDetection: ArUcoDetectionResult,
        bottomDetection: ArUcoDetectionResult,
        intrinsics: CameraIntrinsics
    ) throws -> PoseResult {
        let objectPointValues = definition.dualObjectPoints.flatMap {
            [NSNumber(value: $0.x), NSNumber(value: $0.y), NSNumber(value: $0.z)]
        }
        let imagePoints = (topDetection.corners + bottomDetection.corners).map {
            OpenCVArucoImagePoint(x: Double($0.x), y: Double($0.y))
        }

        let bridgeResult = try bridge.refinePose(
            objectPoints: objectPointValues,
            imagePoints: imagePoints,
            cameraMatrix: intrinsics.openCVCameraMatrixValues
        )

        return PoseResult(
            markerId: definition.physicalMarkerId,
            markerProfile: .dualArucoV2,
            poseSource: .dualTag,
            rotationVector: try vector3(from: bridgeResult.rotationVector, name: "rotationVector"),
            rotationMatrix: try matrix3x3(from: bridgeResult.rotationMatrix, name: "rotationMatrix"),
            translationVector: try vector3(from: bridgeResult.translationVector, name: "translationVector"),
            distanceMm: bridgeResult.distanceMm,
            reprojectionError: bridgeResult.reprojectionError,
            markerAreaPixels: Self.markerAreaPixels(for: topDetection.corners) +
                Self.markerAreaPixels(for: bottomDetection.corners),
            usedPointCount: imagePoints.count,
            detectedTopTagId: definition.topTagId,
            detectedBottomTagId: definition.bottomTagId
        )
    }

    private func estimateSingleTagFallbackPose(
        for definition: DualArucoMarkerDefinition,
        detection: ArUcoDetectionResult,
        role: DualArucoTagRole,
        intrinsics: CameraIntrinsics
    ) throws -> PoseResult {
        let corners = detection.corners.map { corner in
            OpenCVArucoImagePoint(x: Double(corner.x), y: Double(corner.y))
        }

        let bridgeResult = try bridge.estimatePose(
            corners: corners,
            markerSizeMillimeters: definition.tagSizeMillimeters(for: role),
            cameraMatrix: intrinsics.openCVCameraMatrixValues
        )
        let rotationVector = try vector3(from: bridgeResult.rotationVector, name: "rotationVector")
        let rotationMatrix = try matrix3x3(from: bridgeResult.rotationMatrix, name: "rotationMatrix")
        let tagTranslationVector = try vector3(
            from: bridgeResult.translationVector,
            name: "translationVector"
        )
        let tagCenterInMarkerCoordinates = definition.tagCenterInMarkerCoordinates(for: role)
        let markerTranslationVector = tagTranslationVector -
            rotationMatrix * tagCenterInMarkerCoordinates

        return PoseResult(
            markerId: definition.physicalMarkerId,
            markerProfile: .dualArucoV2,
            poseSource: .singleFallback(tagId: detection.markerId, role: role),
            rotationVector: rotationVector,
            rotationMatrix: rotationMatrix,
            translationVector: markerTranslationVector,
            distanceMm: simd_length(markerTranslationVector),
            reprojectionError: bridgeResult.reprojectionError,
            markerAreaPixels: Self.markerAreaPixels(for: detection.corners),
            usedPointCount: corners.count,
            detectedTopTagId: role == .top ? definition.topTagId : nil,
            detectedBottomTagId: role == .bottom ? definition.bottomTagId : nil
        )
    }

    private static func markerAreaPixels(for corners: [CGPoint]) -> Double {
        guard corners.count >= 3 else {
            return 0.0
        }

        var signedArea = 0.0
        for index in corners.indices {
            let nextIndex = (index + 1) % corners.count
            let corner = corners[index]
            let nextCorner = corners[nextIndex]
            signedArea += Double(corner.x) * Double(nextCorner.y)
            signedArea -= Double(nextCorner.x) * Double(corner.y)
        }

        let area = abs(signedArea) * 0.5
        return area.isFinite ? area : 0.0
    }

    private func vector3(from values: [NSNumber], name: String) throws -> SIMD3<Double> {
        guard values.count == 3 else {
            throw EstimatorError.invalidBridgeVector(name: name, count: values.count, expected: 3)
        }

        return SIMD3(values[0].doubleValue, values[1].doubleValue, values[2].doubleValue)
    }

    private func matrix3x3(from values: [NSNumber], name: String) throws -> simd_double3x3 {
        guard values.count == 9 else {
            throw EstimatorError.invalidBridgeVector(name: name, count: values.count, expected: 9)
        }

        return PoseMath.matrixFromRows(
            SIMD3(values[0].doubleValue, values[1].doubleValue, values[2].doubleValue),
            SIMD3(values[3].doubleValue, values[4].doubleValue, values[5].doubleValue),
            SIMD3(values[6].doubleValue, values[7].doubleValue, values[8].doubleValue)
        )
    }
}
