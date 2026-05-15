import CoreGraphics
import Foundation
import simd

struct FinalPoseObservation {
    let markerId: Int
    let poseSource: MarkerPoseSource
    let objectPoints: [SIMD3<Double>]
    let imagePoints: [CGPoint]
    let cameraMatrix: simd_double3x3
    let frameSizePixels: CGSize
    let rotationMatrix: simd_double3x3
    let translationVector: SIMD3<Double>
    let reprojectionError: Double
    let markerAreaPixels: Double
    let topTagAreaPixels: Double?
    let bottomTagAreaPixels: Double?
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

enum FinalPoseMarkerConfidence: String, Equatable {
    case high = "Alta"
    case medium = "Media"
    case low = "Baixa"
}

struct FinalPoseObservationSelectionDiagnostics: Equatable {
    let markerId: Int
    let totalObservationCount: Int
    let observationsBeforeOutlierRejectionCount: Int
    let selectedObservationCount: Int
    let discardedObservationCount: Int
    let outlierRemovedCount: Int
    let finalAverageReprojectionError: Double?
    let finalAverageQualityScore: Double?
    let finalConfidence: FinalPoseMarkerConfidence
    let finalConfidenceReason: String?
    let edgeDiscardedObservationCount: Int
    let smallBottomDiscardedObservationCount: Int
    let reprojectionDiscardedObservationCount: Int
    let lowPriorityFallbackDiscardedObservationCount: Int
    let finalDominantPoseSource: MarkerPoseSource?
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
        let finalTopObservationRatio: Double
        let minimumObservationMarkerAreaPixels: Double
        let minimumBottomTagAreaForFinalDualUse: Double
        let minimumImageEdgeMarginPixels: Double
        let idealImageEdgeMarginPixels: Double
        let idealMinimumDistanceMm: Double
        let idealMaximumDistanceMm: Double
        let maximumDistanceMm: Double
        let maximumFinalPositionOutlierMm: Double
        let maximumFinalRotationOutlierDegrees: Double
        let minimumFinalObservationsAfterOutlierRejection: Int
        let minimumRobustReferenceObservations: Int

        static let scannerDefault = Configuration(
            maximumObservationReprojectionError: 2.0,
            minimumObservationsPerMarker: 2,
            maximumAcceptedReprojectionError: 2.0,
            maximumAcceptedErrorMultiplier: 1.25,
            maximumCameraMatrixDelta: 0.5,
            minimumFinalObservationsPerMarker: 8,
            finalTopObservationRatio: 0.4,
            minimumObservationMarkerAreaPixels: 80.0,
            minimumBottomTagAreaForFinalDualUse: 120.0,
            minimumImageEdgeMarginPixels: 12.0,
            idealImageEdgeMarginPixels: 80.0,
            idealMinimumDistanceMm: 80.0,
            idealMaximumDistanceMm: 180.0,
            maximumDistanceMm: 250.0,
            maximumFinalPositionOutlierMm: 1.0,
            maximumFinalRotationOutlierDegrees: 5.0,
            minimumFinalObservationsAfterOutlierRejection: 5,
            minimumRobustReferenceObservations: 3
        )
    }

    private struct ObservationSelection {
        let observations: [FinalPoseObservation]
        let diagnostics: FinalPoseObservationSelectionDiagnostics
    }

    private struct OutlierRejectionResult {
        let indexedObservations: [(offset: Int, element: FinalPoseObservation)]
        let removedCount: Int
        let discardReasonCounts: [String: Int]
        let wasRelaxed: Bool
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
        currentPoseResults: [PoseResult],
        preferDualTagForFinalExport: Bool = true
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
            currentPosesByMarkerId: currentPosesByMarkerId,
            preferDualTagForFinalExport: preferDualTagForFinalExport
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
        observations: [FinalPoseObservation],
        preferDualTagForFinalExport: Bool = true
    ) -> [Int: FinalPoseObservationSelectionDiagnostics] {
        let observationsByMarkerId = Dictionary(grouping: observations, by: \.markerId)

        return observationsByMarkerId.reduce(into: [:]) { partialResult, item in
            partialResult[item.key] = selectedObservationSelection(
                markerId: item.key,
                observations: item.value,
                preferDualTagForFinalExport: preferDualTagForFinalExport
            ).diagnostics
        }
    }

    private func refinedCameraPoses(
        observations: [FinalPoseObservation],
        currentPosesByMarkerId: [Int: PoseResult],
        preferDualTagForFinalExport: Bool
    ) -> [Int: PoseResult] {
        let observationsByMarkerId = Dictionary(grouping: observations, by: \.markerId)
        var refinedPosesByMarkerId: [Int: PoseResult] = [:]

        for (markerId, markerObservations) in observationsByMarkerId {
            guard let currentPose = currentPosesByMarkerId[markerId],
                  let refinedPose = refinedCameraPose(
                    markerId: markerId,
                    observations: markerObservations,
                    currentPose: currentPose,
                    preferDualTagForFinalExport: preferDualTagForFinalExport
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
        currentPose: PoseResult,
        preferDualTagForFinalExport: Bool
    ) -> PoseResult? {
        let selection = selectedObservationSelection(
            markerId: markerId,
            observations: observations,
            preferDualTagForFinalExport: preferDualTagForFinalExport
        )
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
        observations: [FinalPoseObservation],
        preferDualTagForFinalExport: Bool
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
            from: validIndexedObservations,
            preferDualTagForFinalExport: preferDualTagForFinalExport
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
        let preOutlierSelectedIndices = Set(selectedIndexedObservations.map(\.offset))
        for item in candidateIndexedObservations where !preOutlierSelectedIndices.contains(item.offset) {
            discardReasonCounts["baixa qualidade", default: 0] += 1
        }

        let outlierResult = selectedIndexedObservationsAfterOutlierRejection(
            from: selectedIndexedObservations
        )
        for (reason, count) in outlierResult.discardReasonCounts {
            discardReasonCounts[reason, default: 0] += count
        }

        let selectedObservations = outlierResult.indexedObservations.map(\.element)
        let discardedObservationCount = max(observations.count - selectedObservations.count, 0)
        let averageReprojectionError = averageReprojectionError(in: selectedObservations)
        let averageQualityScore = averageQualityScore(in: selectedObservations)
        let confidence = finalConfidence(
            selectedObservations: selectedObservations,
            observationsBeforeOutlierRejectionCount: selectedIndexedObservations.count,
            outlierRemovedCount: outlierResult.removedCount,
            averageReprojectionError: averageReprojectionError,
            wasOutlierFilterRelaxed: outlierResult.wasRelaxed
        )

        return ObservationSelection(
            observations: selectedObservations,
            diagnostics: FinalPoseObservationSelectionDiagnostics(
                markerId: markerId,
                totalObservationCount: observations.count,
                observationsBeforeOutlierRejectionCount: selectedIndexedObservations.count,
                selectedObservationCount: selectedObservations.count,
                discardedObservationCount: discardedObservationCount,
                outlierRemovedCount: outlierResult.removedCount,
                finalAverageReprojectionError: averageReprojectionError,
                finalAverageQualityScore: averageQualityScore,
                finalConfidence: confidence.value,
                finalConfidenceReason: confidence.reason,
                edgeDiscardedObservationCount: discardReasonCounts["borda da imagem"] ?? 0,
                smallBottomDiscardedObservationCount: discardReasonCounts["bottom pequena"] ?? 0,
                reprojectionDiscardedObservationCount:
                    discardReasonCounts["reprojection error alto"] ?? 0,
                lowPriorityFallbackDiscardedObservationCount:
                    lowPriorityFallbackDiscardCount(in: discardReasonCounts),
                finalDominantPoseSource: dominantPoseSource(in: selectedObservations),
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
                observationsBeforeOutlierRejectionCount: selectedObservations.count,
                selectedObservationCount: selectedObservations.count,
                discardedObservationCount: discardedObservationCount,
                outlierRemovedCount: 0,
                finalAverageReprojectionError: averageReprojectionError(in: selectedObservations),
                finalAverageQualityScore: averageQualityScore(in: selectedObservations),
                finalConfidence: selectedObservations.isEmpty ? .low : .medium,
                finalConfidenceReason: selectedObservations.isEmpty ? "sem observacoes finais" : nil,
                edgeDiscardedObservationCount: 0,
                smallBottomDiscardedObservationCount: 0,
                reprojectionDiscardedObservationCount: discardedObservationCount,
                lowPriorityFallbackDiscardedObservationCount: 0,
                finalDominantPoseSource: dominantPoseSource(in: selectedObservations),
                dominantDiscardReason: discardedObservationCount > 0
                    ? "reprojection error alto"
                    : nil
            )
        )
    }

    private func preferredIndexedObservations(
        from indexedObservations: [(offset: Int, element: FinalPoseObservation)],
        preferDualTagForFinalExport: Bool
    ) -> [(offset: Int, element: FinalPoseObservation)] {
        guard preferDualTagForFinalExport else {
            return indexedObservations
        }

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

        let ratioCount = Int(ceil(Double(candidateCount) * configuration.finalTopObservationRatio))
        let desiredCount = max(configuration.minimumFinalObservationsPerMarker, ratioCount)

        return min(candidateCount, desiredCount)
    }

    private func selectedIndexedObservationsAfterOutlierRejection(
        from indexedObservations: [(offset: Int, element: FinalPoseObservation)]
    ) -> OutlierRejectionResult {
        guard indexedObservations.count >= configuration.minimumFinalObservationsAfterOutlierRejection,
              configuration.maximumFinalPositionOutlierMm.isFinite,
              configuration.maximumFinalPositionOutlierMm > 0,
              configuration.maximumFinalRotationOutlierDegrees.isFinite,
              configuration.maximumFinalRotationOutlierDegrees > 0,
              let referenceTranslation = medianTranslation(
                from: robustReferenceIndexedObservations(from: indexedObservations)
              ),
              let referenceRotation = referenceRotationMatrix(
                from: robustReferenceIndexedObservations(from: indexedObservations)
              )
        else {
            return OutlierRejectionResult(
                indexedObservations: indexedObservations,
                removedCount: 0,
                discardReasonCounts: [:],
                wasRelaxed: false
            )
        }

        var keptObservations: [(offset: Int, element: FinalPoseObservation)] = []
        var discardReasonCounts: [String: Int] = [:]

        for item in indexedObservations {
            let positionDistanceMm = simd_distance(
                item.element.translationVector,
                referenceTranslation
            )
            let rotationDistanceDegrees = Self.rotationAngularDistanceDegrees(
                item.element.rotationMatrix,
                referenceRotation
            )
            let isPositionOutlier = positionDistanceMm.isFinite &&
                positionDistanceMm > configuration.maximumFinalPositionOutlierMm
            let isRotationOutlier = rotationDistanceDegrees.isFinite &&
                rotationDistanceDegrees > configuration.maximumFinalRotationOutlierDegrees

            if isPositionOutlier && isRotationOutlier {
                discardReasonCounts["outlier posicao/rotacao", default: 0] += 1
            } else if isPositionOutlier {
                discardReasonCounts["outlier posicao", default: 0] += 1
            } else if isRotationOutlier {
                discardReasonCounts["outlier rotacao", default: 0] += 1
            } else {
                keptObservations.append(item)
            }
        }

        let removedCount = indexedObservations.count - keptObservations.count
        guard removedCount > 0 else {
            return OutlierRejectionResult(
                indexedObservations: indexedObservations,
                removedCount: 0,
                discardReasonCounts: [:],
                wasRelaxed: false
            )
        }

        guard keptObservations.count >= configuration.minimumFinalObservationsAfterOutlierRejection else {
            return OutlierRejectionResult(
                indexedObservations: indexedObservations,
                removedCount: 0,
                discardReasonCounts: ["filtro outlier relaxado": removedCount],
                wasRelaxed: true
            )
        }

        return OutlierRejectionResult(
            indexedObservations: keptObservations,
            removedCount: removedCount,
            discardReasonCounts: discardReasonCounts,
            wasRelaxed: false
        )
    }

    private func robustReferenceIndexedObservations(
        from indexedObservations: [(offset: Int, element: FinalPoseObservation)]
    ) -> [(offset: Int, element: FinalPoseObservation)] {
        let dualTagObservations = indexedObservations.filter {
            isDualTagObservation($0.element)
        }
        if dualTagObservations.count >= configuration.minimumRobustReferenceObservations {
            return dualTagObservations
        }

        let topFallbackObservations = indexedObservations.filter {
            isTopFallbackObservation($0.element)
        }
        let dualAndTopObservations = dualTagObservations + topFallbackObservations
        if dualAndTopObservations.count >= configuration.minimumRobustReferenceObservations {
            return dualAndTopObservations
        }

        return indexedObservations
    }

    private func medianTranslation(
        from indexedObservations: [(offset: Int, element: FinalPoseObservation)]
    ) -> SIMD3<Double>? {
        guard let x = median(indexedObservations.map(\.element.translationVector.x)),
              let y = median(indexedObservations.map(\.element.translationVector.y)),
              let z = median(indexedObservations.map(\.element.translationVector.z))
        else {
            return nil
        }

        let translation = SIMD3<Double>(x, y, z)
        return PoseMath.isFinite(translation) ? translation : nil
    }

    private func referenceRotationMatrix(
        from indexedObservations: [(offset: Int, element: FinalPoseObservation)]
    ) -> simd_double3x3? {
        guard !indexedObservations.isEmpty else {
            return nil
        }

        if indexedObservations.count == 1 {
            let matrix = indexedObservations[0].element.rotationMatrix
            return PoseMath.isFinite(matrix) ? matrix : nil
        }

        let medoid = indexedObservations.min { lhs, rhs in
            totalRotationDistanceDegrees(
                from: lhs.element.rotationMatrix,
                to: indexedObservations
            ) < totalRotationDistanceDegrees(
                from: rhs.element.rotationMatrix,
                to: indexedObservations
            )
        }
        let matrix = medoid?.element.rotationMatrix

        guard let matrix = matrix,
              PoseMath.isFinite(matrix)
        else {
            return nil
        }

        return matrix
    }

    private func totalRotationDistanceDegrees(
        from rotationMatrix: simd_double3x3,
        to indexedObservations: [(offset: Int, element: FinalPoseObservation)]
    ) -> Double {
        indexedObservations.reduce(0.0) {
            $0 + Self.rotationAngularDistanceDegrees(
                rotationMatrix,
                $1.element.rotationMatrix
            )
        }
    }

    private func qualityRejectionReason(for observation: FinalPoseObservation) -> String? {
        guard isValidObservationPose(observation) else {
            return "pose invalida"
        }

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

        if case .dualTag = observation.poseSource,
           (observation.bottomTagAreaPixels ?? 0) < configuration.minimumBottomTagAreaForFinalDualUse {
            return "bottom pequena"
        }

        guard imageEdgeMarginPixels(for: observation) >= configuration.minimumImageEdgeMarginPixels else {
            return "borda da imagem"
        }

        return nil
    }

    private func isValidObservationPose(_ observation: FinalPoseObservation) -> Bool {
        PoseMath.isFinite(observation.rotationMatrix) &&
            PoseMath.isFinite(observation.translationVector) &&
            observation.distanceMm.isFinite &&
            observation.markerAreaPixels.isFinite &&
            observation.frameSizePixels.width.isFinite &&
            observation.frameSizePixels.height.isFinite &&
            observation.frameSizePixels.width > 0 &&
            observation.frameSizePixels.height > 0 &&
            observation.imagePoints.allSatisfy { $0.x.isFinite && $0.y.isFinite }
    }

    private func averageReprojectionError(in observations: [FinalPoseObservation]) -> Double? {
        let errors = observations
            .map(\.reprojectionError)
            .filter { $0.isFinite }

        guard !errors.isEmpty else {
            return nil
        }

        return errors.reduce(0.0, +) / Double(errors.count)
    }

    private func averageQualityScore(in observations: [FinalPoseObservation]) -> Double? {
        let scores = observations
            .map { qualityScore(for: $0) }
            .filter { $0.isFinite }

        guard !scores.isEmpty else {
            return nil
        }

        return scores.reduce(0.0, +) / Double(scores.count)
    }

    private func dominantPoseSource(in observations: [FinalPoseObservation]) -> MarkerPoseSource? {
        var weightedSources: [(source: MarkerPoseSource, weight: Double)] = []
        for observation in observations {
            let weight = max(qualityScore(for: observation), 0.01)
            if let index = weightedSources.firstIndex(where: { $0.source == observation.poseSource }) {
                weightedSources[index].weight += weight
            } else {
                weightedSources.append((source: observation.poseSource, weight: weight))
            }
        }

        return weightedSources.max {
            if $0.weight == $1.weight {
                return $0.source.debugTitle > $1.source.debugTitle
            }

            return $0.weight < $1.weight
        }?.source
    }

    private func lowPriorityFallbackDiscardCount(in counts: [String: Int]) -> Int {
        (counts["fallback baixa prioridade"] ?? 0) +
            (counts["bottom baixa prioridade"] ?? 0)
    }

    private func finalConfidence(
        selectedObservations: [FinalPoseObservation],
        observationsBeforeOutlierRejectionCount: Int,
        outlierRemovedCount: Int,
        averageReprojectionError: Double?,
        wasOutlierFilterRelaxed: Bool
    ) -> (value: FinalPoseMarkerConfidence, reason: String?) {
        guard !selectedObservations.isEmpty else {
            return (.low, "sem observacoes finais")
        }

        if selectedObservations.count < configuration.minimumFinalObservationsAfterOutlierRejection {
            return (.low, "poucas observacoes finais")
        }

        if wasOutlierFilterRelaxed {
            return (.low, "filtro outlier relaxado")
        }

        let outlierRatio = observationsBeforeOutlierRejectionCount > 0
            ? Double(outlierRemovedCount) / Double(observationsBeforeOutlierRejectionCount)
            : 0
        if outlierRatio > 0.40 {
            return (.low, "muitos outliers")
        }

        if let averageReprojectionError = averageReprojectionError,
           averageReprojectionError > configuration.maximumObservationReprojectionError {
            return (.low, "erro alto")
        }

        let dualTagObservationCount = selectedObservations.filter {
            isDualTagObservation($0)
        }.count
        if selectedObservations.count >= configuration.minimumFinalObservationsPerMarker,
           dualTagObservationCount >= configuration.minimumFinalObservationsPerMarker,
           (averageReprojectionError ?? .infinity) <= 1.2,
           outlierRatio <= 0.20 {
            return (.high, nil)
        }

        return (.medium, nil)
    }

    private func isDualTagObservation(_ observation: FinalPoseObservation) -> Bool {
        if case .dualTag = observation.poseSource {
            return true
        }

        return false
    }

    private func isTopFallbackObservation(_ observation: FinalPoseObservation) -> Bool {
        if case let .singleFallback(_, role) = observation.poseSource {
            return role == .top
        }

        return false
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
        guard isValidObservationPose(observation) else {
            return 0
        }

        let reprojectionScore = qualityScoreForReprojectionError(observation.reprojectionError)
        let areaScore = qualityScoreForMarkerArea(observation)
        let distanceScore = qualityScoreForDistance(observation.distanceMm)
        let imageCenterScore = qualityScoreForImagePosition(observation)
        let sourceScore: Double
        switch observation.poseSource {
        case .dualTag:
            sourceScore = 2.2
        case let .singleFallback(_, role):
            sourceScore = role == .top ? 0.45 : 0.18
        case .singleArucoV1:
            sourceScore = 1.0
        }

        return sourceScore * reprojectionScore * areaScore * distanceScore * imageCenterScore
    }

    private func qualityScoreForReprojectionError(_ reprojectionError: Double) -> Double {
        guard reprojectionError.isFinite,
              reprojectionError <= configuration.maximumObservationReprojectionError
        else {
            return 0
        }

        let normalized = 1.0 - min(
            max(reprojectionError / configuration.maximumObservationReprojectionError, 0.0),
            1.0
        )

        return max(0.20, normalized)
    }

    private func qualityScoreForMarkerArea(_ observation: FinalPoseObservation) -> Double {
        let topAreaScore = qualityScoreForArea(
            observation.topTagAreaPixels ?? observation.markerAreaPixels
        )
        let bottomAreaScore = qualityScoreForArea(
            observation.bottomTagAreaPixels ?? observation.markerAreaPixels
        )

        switch observation.poseSource {
        case .dualTag:
            return min(topAreaScore, bottomAreaScore) * 0.65 +
                ((topAreaScore + bottomAreaScore) / 2.0) * 0.35
        case let .singleFallback(_, role):
            switch role {
            case .top:
                return topAreaScore
            case .bottom:
                return bottomAreaScore
            }
        case .singleArucoV1:
            return qualityScoreForArea(observation.markerAreaPixels)
        }
    }

    private func qualityScoreForArea(_ areaPixels: Double?) -> Double {
        guard let areaPixels = areaPixels,
              areaPixels.isFinite,
              areaPixels > 0
        else {
            return 0.25
        }

        let normalized = log10(max(areaPixels, 1.0)) / 4.0
        return min(max(normalized, 0.25), 1.0)
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

    private func qualityScoreForImagePosition(_ observation: FinalPoseObservation) -> Double {
        let edgeMargin = imageEdgeMarginPixels(for: observation)
        guard edgeMargin.isFinite else {
            return 0
        }

        guard edgeMargin >= configuration.minimumImageEdgeMarginPixels else {
            return 0
        }

        let normalized = edgeMargin / max(configuration.idealImageEdgeMarginPixels, 1.0)
        return min(max(normalized, 0.25), 1.0)
    }

    private func imageEdgeMarginPixels(for observation: FinalPoseObservation) -> Double {
        guard !observation.imagePoints.isEmpty,
              observation.frameSizePixels.width.isFinite,
              observation.frameSizePixels.height.isFinite,
              observation.frameSizePixels.width > 0,
              observation.frameSizePixels.height > 0
        else {
            return 0
        }

        let minX = observation.imagePoints.map(\.x).min() ?? 0
        let minY = observation.imagePoints.map(\.y).min() ?? 0
        let maxX = observation.imagePoints.map(\.x).max() ?? 0
        let maxY = observation.imagePoints.map(\.y).max() ?? 0
        let frameWidth = observation.frameSizePixels.width
        let frameHeight = observation.frameSizePixels.height
        let margin = min(minX, minY, frameWidth - maxX, frameHeight - maxY)

        return Double(margin)
    }

    private func dominantReason(in counts: [String: Int]) -> String? {
        counts.max {
            if $0.value == $1.value {
                return $0.key > $1.key
            }

            return $0.value < $1.value
        }?.key
    }

    private func median(_ values: [Double]) -> Double? {
        let sortedValues = values
            .filter { $0.isFinite }
            .sorted()
        guard !sortedValues.isEmpty else {
            return nil
        }

        let middleIndex = sortedValues.count / 2
        if sortedValues.count.isMultiple(of: 2) {
            return (sortedValues[middleIndex - 1] + sortedValues[middleIndex]) / 2.0
        }

        return sortedValues[middleIndex]
    }

    private static func rotationAngularDistanceDegrees(
        _ lhs: simd_double3x3,
        _ rhs: simd_double3x3
    ) -> Double {
        guard PoseMath.isFinite(lhs), PoseMath.isFinite(rhs) else {
            return .infinity
        }

        let delta = simd_transpose(lhs) * rhs
        let trace = PoseMath.matrixElement(delta, row: 0, column: 0) +
            PoseMath.matrixElement(delta, row: 1, column: 1) +
            PoseMath.matrixElement(delta, row: 2, column: 2)
        let cosineTheta = min(max((trace - 1.0) / 2.0, -1.0), 1.0)
        let radians = acos(cosineTheta)

        guard radians.isFinite else {
            return .infinity
        }

        return radians * 180.0 / Double.pi
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
