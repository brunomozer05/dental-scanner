import CoreGraphics
import Foundation
import simd

struct FinalPoseObservation {
    let markerId: Int
    let poseSource: MarkerPoseSource
    let objectPoints: [SIMD3<Double>]
    let imagePoints: [CGPoint]
    let cameraMatrix: simd_double3x3
    let reprojectionError: Double
    let markerAreaPixels: Double

    static func markerObjectPoints(markerSizeMillimeters: Double) -> [SIMD3<Double>] {
        let halfSize = markerSizeMillimeters / 2.0

        return [
            SIMD3(-halfSize, halfSize, 0.0),
            SIMD3(halfSize, halfSize, 0.0),
            SIMD3(halfSize, -halfSize, 0.0),
            SIMD3(-halfSize, -halfSize, 0.0)
        ]
    }
}

final class FinalPoseRefiner {
    struct Configuration {
        let maximumObservationReprojectionError: Double
        let minimumObservationsPerMarker: Int
        let maximumAcceptedReprojectionError: Double
        let maximumAcceptedErrorMultiplier: Double
        let maximumCameraMatrixDelta: Double

        static let scannerDefault = Configuration(
            maximumObservationReprojectionError: 2.0,
            minimumObservationsPerMarker: 2,
            maximumAcceptedReprojectionError: 2.0,
            maximumAcceptedErrorMultiplier: 1.25,
            maximumCameraMatrixDelta: 0.5
        )
    }

    private let configuration: Configuration
    private let bridge: OpenCVArucoPoseBridge

    init(
        configuration: Configuration = .scannerDefault,
        bridge: OpenCVArucoPoseBridge = OpenCVArucoPoseBridge()
    ) {
        self.configuration = configuration
        self.bridge = bridge
    }

    func refine(
        observations: [FinalPoseObservation],
        currentPoseResults: [PoseResult]
    ) -> [PoseResult] {
        let currentPoseResults = currentPoseResults.sorted { $0.markerId < $1.markerId }
        guard let anchorMarkerId = currentPoseResults.first?.markerId else {
            return currentPoseResults
        }

        let currentPosesByMarkerId = Dictionary(uniqueKeysWithValues: currentPoseResults.map {
            ($0.markerId, $0)
        })
        let refinedCameraPosesByMarkerId = refinedCameraPoses(
            observations: observations,
            currentPosesByMarkerId: currentPosesByMarkerId
        )

        guard let refinedAnchorPose = refinedCameraPosesByMarkerId[anchorMarkerId] else {
            return currentPoseResults
        }

        return currentPoseResults.map { currentPose in
            guard let refinedCameraPose = refinedCameraPosesByMarkerId[currentPose.markerId],
                  let relativePose = Self.pose(
                    refinedCameraPose,
                    relativeTo: refinedAnchorPose,
                    fallbackMetadata: currentPose
                  )
            else {
                return currentPose
            }

            return relativePose
        }
    }

    private func refinedCameraPoses(
        observations: [FinalPoseObservation],
        currentPosesByMarkerId: [Int: PoseResult]
    ) -> [Int: PoseResult] {
        let observationsByMarkerId = Dictionary(grouping: observations, by: \.markerId)
        var refinedPosesByMarkerId: [Int: PoseResult] = [:]

        for (markerId, markerObservations) in observationsByMarkerId {
            guard let currentPose = currentPosesByMarkerId[markerId],
                  let refinedPose = refinedCameraPose(
                    markerId: markerId,
                    observations: markerObservations,
                    currentPose: currentPose
                  )
            else {
                continue
            }

            refinedPosesByMarkerId[markerId] = refinedPose
        }

        return refinedPosesByMarkerId
    }

    private func refinedCameraPose(
        markerId: Int,
        observations: [FinalPoseObservation],
        currentPose: PoseResult
    ) -> PoseResult? {
        let lowErrorObservations = observations.filter {
            $0.reprojectionError.isFinite &&
                $0.reprojectionError <= configuration.maximumObservationReprojectionError
        }
        let preferredObservations = preferredObservations(from: lowErrorObservations)

        guard let referenceCameraMatrix = preferredObservations.last?.cameraMatrix else {
            return nil
        }

        let compatibleObservations = preferredObservations.filter {
            Self.maximumMatrixDelta($0.cameraMatrix, referenceCameraMatrix) <=
                configuration.maximumCameraMatrixDelta
        }
        guard compatibleObservations.count >= configuration.minimumObservationsPerMarker,
              let intrinsics = CameraIntrinsics(matrix: referenceCameraMatrix)
        else {
            return nil
        }

        let objectPointValues = compatibleObservations.flatMap(\.objectPoints).flatMap {
            [NSNumber(value: $0.x), NSNumber(value: $0.y), NSNumber(value: $0.z)]
        }
        let imagePoints = compatibleObservations.flatMap(\.imagePoints).map {
            OpenCVArucoImagePoint(x: Double($0.x), y: Double($0.y))
        }

        guard objectPointValues.count / 3 == imagePoints.count else {
            return nil
        }

        guard let bridgeResult = try? bridge.refinePose(
            objectPoints: objectPointValues,
            imagePoints: imagePoints,
            cameraMatrix: intrinsics.openCVCameraMatrixValues
        ) else {
            return nil
        }

        let acceptedReprojectionError = max(
            min(
                configuration.maximumAcceptedReprojectionError,
                currentPose.reprojectionError * configuration.maximumAcceptedErrorMultiplier
            ),
            configuration.maximumObservationReprojectionError
        )
        guard bridgeResult.reprojectionError.isFinite,
              bridgeResult.reprojectionError <= acceptedReprojectionError,
              let rotationVector = Self.vector3(from: bridgeResult.rotationVector),
              let rotationMatrix = Self.matrix3x3(from: bridgeResult.rotationMatrix),
              let translationVector = Self.vector3(from: bridgeResult.translationVector)
        else {
            return nil
        }

        return PoseResult(
            markerId: markerId,
            markerProfile: currentPose.markerProfile,
            poseSource: currentPose.poseSource,
            rotationVector: rotationVector,
            rotationMatrix: rotationMatrix,
            translationVector: translationVector,
            distanceMm: bridgeResult.distanceMm,
            reprojectionError: bridgeResult.reprojectionError,
            markerAreaPixels: averageMarkerAreaPixels(in: compatibleObservations),
            usedPointCount: currentPose.usedPointCount,
            detectedTopTagId: currentPose.detectedTopTagId,
            detectedBottomTagId: currentPose.detectedBottomTagId
        )
    }

    private func averageMarkerAreaPixels(in observations: [FinalPoseObservation]) -> Double {
        let areas = observations
            .map(\.markerAreaPixels)
            .filter { $0.isFinite && $0 > 0 }

        guard !areas.isEmpty else {
            return 0.0
        }

        return areas.reduce(0.0, +) / Double(areas.count)
    }

    private static func pose(
        _ pose: PoseResult,
        relativeTo anchorPose: PoseResult,
        fallbackMetadata: PoseResult
    ) -> PoseResult? {
        let inverseAnchorRotation = simd_transpose(anchorPose.rotationMatrix)
        let relativeRotationMatrix = inverseAnchorRotation * pose.rotationMatrix
        let relativeTranslation = inverseAnchorRotation * (pose.translationVector - anchorPose.translationVector)

        guard let relativeRotationVector = PoseMath.rotationVector(from: relativeRotationMatrix),
              PoseMath.isFinite(relativeRotationVector),
              PoseMath.isFinite(relativeTranslation)
        else {
            return nil
        }

        return PoseResult(
            markerId: pose.markerId,
            markerProfile: fallbackMetadata.markerProfile,
            poseSource: fallbackMetadata.poseSource,
            rotationVector: relativeRotationVector,
            rotationMatrix: relativeRotationMatrix,
            translationVector: relativeTranslation,
            distanceMm: simd_length(relativeTranslation),
            reprojectionError: pose.reprojectionError,
            markerAreaPixels: fallbackMetadata.markerAreaPixels,
            usedPointCount: fallbackMetadata.usedPointCount,
            detectedTopTagId: fallbackMetadata.detectedTopTagId,
            detectedBottomTagId: fallbackMetadata.detectedBottomTagId
        )
    }

    private func preferredObservations(
        from observations: [FinalPoseObservation]
    ) -> [FinalPoseObservation] {
        let dualTagObservations = observations.filter {
            if case .dualTag = $0.poseSource {
                return true
            }

            return false
        }
        if dualTagObservations.count >= configuration.minimumObservationsPerMarker {
            return dualTagObservations
        }

        let topFallbackObservations = observations.filter {
            if case let .singleFallback(_, role) = $0.poseSource {
                return role == .top
            }

            return false
        }
        if topFallbackObservations.count >= configuration.minimumObservationsPerMarker {
            return topFallbackObservations
        }

        let dualAndTopObservations = dualTagObservations + topFallbackObservations
        if dualAndTopObservations.count >= configuration.minimumObservationsPerMarker {
            return dualAndTopObservations
        }

        let bottomFallbackObservations = observations.filter {
            if case let .singleFallback(_, role) = $0.poseSource {
                return role == .bottom
            }

            return false
        }
        if bottomFallbackObservations.count >= configuration.minimumObservationsPerMarker {
            return bottomFallbackObservations
        }

        return observations
    }

    private static func vector3(from values: [NSNumber]) -> SIMD3<Double>? {
        guard values.count == 3 else {
            return nil
        }

        let vector = SIMD3(values[0].doubleValue, values[1].doubleValue, values[2].doubleValue)
        return PoseMath.isFinite(vector) ? vector : nil
    }

    private static func matrix3x3(from values: [NSNumber]) -> simd_double3x3? {
        guard values.count == 9 else {
            return nil
        }

        let matrix = PoseMath.matrixFromRows(
            SIMD3(values[0].doubleValue, values[1].doubleValue, values[2].doubleValue),
            SIMD3(values[3].doubleValue, values[4].doubleValue, values[5].doubleValue),
            SIMD3(values[6].doubleValue, values[7].doubleValue, values[8].doubleValue)
        )

        return PoseMath.isFinite(matrix) ? matrix : nil
    }

    private static func maximumMatrixDelta(
        _ lhs: simd_double3x3,
        _ rhs: simd_double3x3
    ) -> Double {
        let deltas = [
            abs(lhs.columns.0.x - rhs.columns.0.x),
            abs(lhs.columns.0.y - rhs.columns.0.y),
            abs(lhs.columns.0.z - rhs.columns.0.z),
            abs(lhs.columns.1.x - rhs.columns.1.x),
            abs(lhs.columns.1.y - rhs.columns.1.y),
            abs(lhs.columns.1.z - rhs.columns.1.z),
            abs(lhs.columns.2.x - rhs.columns.2.x),
            abs(lhs.columns.2.y - rhs.columns.2.y),
            abs(lhs.columns.2.z - rhs.columns.2.z)
        ]

        return deltas.max() ?? .infinity
    }
}
