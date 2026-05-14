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
    let distanceMm: Double

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

struct FinalPoseObservationSelectionDiagnostics: Equatable {
    let markerId: Int
    let totalObservationCount: Int
    let selectedObservationCount: Int
    let discardedObservationCount: Int
    let dominantDiscardReason: String?
}

final class FinalPoseRefiner {
    struct Configuration {
        let maximumObservationReprojectionError: Double
        let minimumObservationsPerMarker: Int
        let maximumAcceptedReprojectionError: Double
        let maximumAcceptedErrorMultiplier: Double
        let maximumCameraMatrixDelta: Double
        let minimumFinalObservationsPerMarker: Int
        let topQualityObservationRatio: Double
        let minimumObservationMarkerAreaPixels: Double
        let idealMinimumDistanceMm: Double
        let idealMaximumDistanceMm: Double
        let maximumDistanceMm: Double

        static let scannerDefault = Configuration(
            maximumObservationReprojectionError: 2.0,
            minimumObservationsPerMarker: 2,
            maximumAcceptedReprojectionError: 2.0,
            maximumAcceptedErrorMultiplier: 1.25,
            maximumCameraMatrixDelta: 0.5,
            minimumFinalObservationsPerMarker: 10,
            topQualityObservationRatio: 0.5,
            minimumObservationMarkerAreaPixels: 80.0,
            idealMinimumDistanceMm: 80.0,
            idealMaximumDistanceMm: 180.0,
            maximumDistanceMm: 250.0
        )
    }

    private struct ObservationSelection {
        let observations: [FinalPoseObservation]
        let diagnostics: FinalPoseObservationSelectionDiagnostics
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

    func selectionDiagnostics(
        observations: [FinalPoseObservation]
    ) -> [Int: FinalPoseObservationSelectionDiagnostics] {
        let observationsByMarkerId = Dictionary(grouping: observations, by: \.markerId)

        return observationsByMarkerId.reduce(into: [:]) { partialResult, item in
            partialResult[item.key] = selectedObservationSelection(
                markerId: item.key,
                observations: item.value
            ).diagnostics
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
        let selection = selectedObservationSelection(markerId: markerId, observations: observations)
        let preferredObservations = selection.observations

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

    private func selectedObservationSelection(
        markerId: Int,
        observations: [FinalPoseObservation]
    ) -> ObservationSelection {
        if observations.allSatisfy({ observation in
            if case .singleArucoV1 = observation.poseSource {
                return true
            }

            return false
        }) {
            return singleArucoV1ObservationSelection(
                markerId: markerId,
                observations: observations
            )
        }

        let indexedObservations = Array(observations.enumerated())
        var discardReasonCounts: [String: Int] = [:]
        let validIndexedObservations = indexedObservations.filter { item in
            if let reason = qualityRejectionReason(for: item.element) {
                discardReasonCounts[reason, default: 0] += 1
                return false
            }

            return true
        }
        let candidateIndexedObservations = preferredIndexedObservations(
            from: validIndexedObservations
        )
        let candidateIndices = Set(candidateIndexedObservations.map(\.offset))
        for item in validIndexedObservations where !candidateIndices.contains(item.offset) {
            discardReasonCounts[sourcePriorityRejectionReason(for: item.element), default: 0] += 1
        }

        let sortedCandidates = candidateIndexedObservations.sorted {
            qualityScore(for: $0.element) > qualityScore(for: $1.element)
        }
        let selectedCount = selectedObservationCount(from: sortedCandidates.count)
        let selectedIndexedObservations = Array(sortedCandidates.prefix(selectedCount))
        let selectedIndices = Set(selectedIndexedObservations.map(\.offset))
        for item in candidateIndexedObservations where !selectedIndices.contains(item.offset) {
            discardReasonCounts["baixa qualidade", default: 0] += 1
        }

        let selectedObservations = selectedIndexedObservations.map(\.element)
        let discardedObservationCount = max(observations.count - selectedObservations.count, 0)

        return ObservationSelection(
            observations: selectedObservations,
            diagnostics: FinalPoseObservationSelectionDiagnostics(
                markerId: markerId,
                totalObservationCount: observations.count,
                selectedObservationCount: selectedObservations.count,
                discardedObservationCount: discardedObservationCount,
                dominantDiscardReason: dominantReason(in: discardReasonCounts)
            )
        )
    }

    private func singleArucoV1ObservationSelection(
        markerId: Int,
        observations: [FinalPoseObservation]
    ) -> ObservationSelection {
        let selectedObservations = observations.filter {
            $0.reprojectionError.isFinite &&
                $0.reprojectionError <= configuration.maximumObservationReprojectionError
        }
        let discardedObservationCount = max(observations.count - selectedObservations.count, 0)

        return ObservationSelection(
            observations: selectedObservations,
            diagnostics: FinalPoseObservationSelectionDiagnostics(
                markerId: markerId,
                totalObservationCount: observations.count,
                selectedObservationCount: selectedObservations.count,
                discardedObservationCount: discardedObservationCount,
                dominantDiscardReason: discardedObservationCount > 0
                    ? "reprojection error alto"
                    : nil
            )
        )
    }

    private func preferredIndexedObservations(
        from indexedObservations: [(offset: Int, element: FinalPoseObservation)]
    ) -> [(offset: Int, element: FinalPoseObservation)] {
        let dualTagObservations = indexedObservations.filter {
            if case .dualTag = $0.element.poseSource {
                return true
            }

            return false
        }
        if dualTagObservations.count >= configuration.minimumFinalObservationsPerMarker {
            return dualTagObservations
        }

        let topFallbackObservations = indexedObservations.filter {
            if case let .singleFallback(_, role) = $0.element.poseSource {
                return role == .top
            }

            return false
        }
        let dualAndTopObservations = dualTagObservations + topFallbackObservations
        if dualAndTopObservations.count >= configuration.minimumFinalObservationsPerMarker ||
            !dualAndTopObservations.isEmpty {
            return dualAndTopObservations
        }

        let bottomFallbackObservations = indexedObservations.filter {
            if case let .singleFallback(_, role) = $0.element.poseSource {
                return role == .bottom
            }

            return false
        }
        if !bottomFallbackObservations.isEmpty {
            return bottomFallbackObservations
        }

        return indexedObservations
    }

    private func selectedObservationCount(from candidateCount: Int) -> Int {
        guard candidateCount > 0 else {
            return 0
        }

        let ratioCount = Int(ceil(Double(candidateCount) * configuration.topQualityObservationRatio))
        let desiredCount = max(configuration.minimumFinalObservationsPerMarker, ratioCount)

        return min(candidateCount, desiredCount)
    }

    private func qualityRejectionReason(for observation: FinalPoseObservation) -> String? {
        guard observation.reprojectionError.isFinite,
              observation.reprojectionError <= configuration.maximumObservationReprojectionError
        else {
            return "reprojection error alto"
        }

        guard observation.markerAreaPixels.isFinite,
              observation.markerAreaPixels >= configuration.minimumObservationMarkerAreaPixels
        else {
            return "area baixa"
        }

        return nil
    }

    private func sourcePriorityRejectionReason(for observation: FinalPoseObservation) -> String {
        switch observation.poseSource {
        case .dualTag:
            return "baixa qualidade"
        case let .singleFallback(_, role):
            switch role {
            case .top:
                return "fallback baixa prioridade"
            case .bottom:
                return "bottom baixa prioridade"
            }
        case .singleArucoV1:
            return "baixa qualidade"
        }
    }

    private func qualityScore(for observation: FinalPoseObservation) -> Double {
        let reprojectionScore = 1.0 / max(observation.reprojectionError, 0.05)
        let areaScore = min(max(log10(max(observation.markerAreaPixels, 1.0)) / 4.0, 0.0), 1.0)
        let distanceScore = qualityScoreForDistance(observation.distanceMm)
        let sourceScore: Double
        switch observation.poseSource {
        case .dualTag:
            sourceScore = 2.0
        case let .singleFallback(_, role):
            sourceScore = role == .top ? 0.65 : 0.25
        case .singleArucoV1:
            sourceScore = 1.0
        }

        return sourceScore * 2.0 + reprojectionScore * 1.5 + areaScore + distanceScore
    }

    private func qualityScoreForDistance(_ distanceMm: Double) -> Double {
        guard distanceMm.isFinite, distanceMm > 0 else {
            return 0
        }

        if distanceMm >= configuration.idealMinimumDistanceMm &&
            distanceMm <= configuration.idealMaximumDistanceMm {
            return 1.0
        }

        if distanceMm <= configuration.maximumDistanceMm {
            return 0.45
        }

        return 0
    }

    private func dominantReason(in counts: [String: Int]) -> String? {
        counts.max {
            if $0.value == $1.value {
                return $0.key > $1.key
            }

            return $0.value < $1.value
        }?.key
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
