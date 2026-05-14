import CoreGraphics
import Foundation
import simd

final class PoseEstimator {
    private enum DualArucoV2PoseSelection {
        static let maximumPreferredDualTagReprojectionError = 2.0
        static let minimumBottomAreaPixels = 80.0
        static let minimumAnyTagAreaPixels = 80.0
        static let minimumTopToBottomAreaRatio = 0.35
        static let maximumTopToBottomAreaRatio = 4.5
        static let minimumCenterDistanceRatio = 0.45
        static let maximumCenterDistanceRatio = 2.0
        static let minimumTopDownDirectionDot = 0.15
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
    private(set) var lastDualArucoV2RejectionReasonsByMarkerId: [Int: String] = [:]

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
        lastDualArucoV2RejectionReasonsByMarkerId = [:]

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
        if let topDetection,
           let bottomDetection {
            if let rejectionReason = dualTagPlausibilityRejectionReason(
                for: definition,
                topDetection: topDetection,
                bottomDetection: bottomDetection
            ) {
                lastDualArucoV2RejectionReasonsByMarkerId[
                    definition.physicalMarkerId
                ] = rejectionReason
            } else if let dualTagPose = try? estimateDualTagPose(
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

                lastDualArucoV2RejectionReasonsByMarkerId[
                    definition.physicalMarkerId
                ] = "reprojection error alto"
            } else {
                lastDualArucoV2RejectionReasonsByMarkerId[
                    definition.physicalMarkerId
                ] = "par top/bottom inconsistente"
            }
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

        return nil
    }

    private func dualTagPlausibilityRejectionReason(
        for definition: DualArucoMarkerDefinition,
        topDetection: ArUcoDetectionResult,
        bottomDetection: ArUcoDetectionResult
    ) -> String? {
        let topArea = Self.markerAreaPixels(for: topDetection.corners)
        let bottomArea = Self.markerAreaPixels(for: bottomDetection.corners)

        guard topArea >= DualArucoV2PoseSelection.minimumAnyTagAreaPixels,
              bottomArea >= DualArucoV2PoseSelection.minimumAnyTagAreaPixels
        else {
            return bottomArea < DualArucoV2PoseSelection.minimumBottomAreaPixels
                ? "bottom pequena"
                : "area baixa"
        }

        guard bottomArea >= DualArucoV2PoseSelection.minimumBottomAreaPixels else {
            return "bottom pequena"
        }

        let areaRatio = topArea / bottomArea
        guard areaRatio >= DualArucoV2PoseSelection.minimumTopToBottomAreaRatio,
              areaRatio <= DualArucoV2PoseSelection.maximumTopToBottomAreaRatio
        else {
            return "par top/bottom inconsistente"
        }

        let topCenter = Self.center(of: topDetection.corners)
        let bottomCenter = Self.center(of: bottomDetection.corners)
        let centerDelta = SIMD2<Double>(
            Double(bottomCenter.x - topCenter.x),
            Double(bottomCenter.y - topCenter.y)
        )
        let centerDistancePixels = simd_length(centerDelta)
        let topSideLength = Self.averageSideLengthPixels(for: topDetection.corners)
        let bottomSideLength = Self.averageSideLengthPixels(for: bottomDetection.corners)
        let expectedDistanceFromTop = topSideLength *
            abs(definition.bottomTagCenterInMarkerCoordinates.y) /
            definition.topTagSizeMm
        let expectedDistanceFromBottom = bottomSideLength *
            abs(definition.bottomTagCenterInMarkerCoordinates.y) /
            definition.bottomTagSizeMm
        let expectedCenterDistancePixels = (expectedDistanceFromTop + expectedDistanceFromBottom) / 2.0

        guard centerDistancePixels.isFinite,
              expectedCenterDistancePixels.isFinite,
              expectedCenterDistancePixels > 1e-6
        else {
            return "par top/bottom inconsistente"
        }

        let centerDistanceRatio = centerDistancePixels / expectedCenterDistancePixels
        guard centerDistanceRatio >= DualArucoV2PoseSelection.minimumCenterDistanceRatio,
              centerDistanceRatio <= DualArucoV2PoseSelection.maximumCenterDistanceRatio
        else {
            return "par top/bottom inconsistente"
        }

        guard let topDownDirection = Self.tagDownDirection(for: topDetection.corners),
              centerDistancePixels > 1e-6
        else {
            return "par top/bottom inconsistente"
        }

        let centerDirection = centerDelta / centerDistancePixels
        guard simd_dot(centerDirection, topDownDirection) >=
            DualArucoV2PoseSelection.minimumTopDownDirectionDot
        else {
            return "par top/bottom inconsistente"
        }

        return nil
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

    private static func center(of corners: [CGPoint]) -> CGPoint {
        guard !corners.isEmpty else {
            return .zero
        }

        let accumulated = corners.reduce(CGPoint.zero) { partialResult, corner in
            CGPoint(
                x: partialResult.x + corner.x,
                y: partialResult.y + corner.y
            )
        }

        return CGPoint(
            x: accumulated.x / CGFloat(corners.count),
            y: accumulated.y / CGFloat(corners.count)
        )
    }

    private static func averageSideLengthPixels(for corners: [CGPoint]) -> Double {
        guard corners.count == 4 else {
            return 0
        }

        let sideLengths = corners.indices.map { index in
            let nextIndex = (index + 1) % corners.count
            return hypot(
                Double(corners[nextIndex].x - corners[index].x),
                Double(corners[nextIndex].y - corners[index].y)
            )
        }

        let averageSideLength = sideLengths.reduce(0.0, +) / Double(sideLengths.count)
        return averageSideLength.isFinite ? averageSideLength : 0
    }

    private static func tagDownDirection(for corners: [CGPoint]) -> SIMD2<Double>? {
        guard corners.count == 4 else {
            return nil
        }

        let topEdgeCenter = CGPoint(
            x: (corners[0].x + corners[1].x) / 2.0,
            y: (corners[0].y + corners[1].y) / 2.0
        )
        let bottomEdgeCenter = CGPoint(
            x: (corners[2].x + corners[3].x) / 2.0,
            y: (corners[2].y + corners[3].y) / 2.0
        )
        let direction = SIMD2<Double>(
            Double(bottomEdgeCenter.x - topEdgeCenter.x),
            Double(bottomEdgeCenter.y - topEdgeCenter.y)
        )
        let length = simd_length(direction)

        guard length.isFinite, length > 1e-6 else {
            return nil
        }

        return direction / length
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
