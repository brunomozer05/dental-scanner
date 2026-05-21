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
    let motionQuality: MotionFrameQuality?
    let cameraQuality: CameraFrameQuality?

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

struct PoseObservationQuality: Equatable {
    let markerId: Int
    let source: MarkerPoseSource
    let qualityScore: Double
    let reprojectionError: Double
    let topAreaPixels: Double?
    let bottomAreaPixels: Double?
    let normalizedImageX: Double?
    let normalizedImageY: Double?
    let edgeMargin: Double?
    let markerNormal: SIMD3<Double>?
    let motionStabilityScore: Double
    let motionRotationStabilityScore: Double
    let cameraStabilityScore: Double
    let cameraRotationStabilityScore: Double
    let wasNearImageEdge: Bool
    let wasHardRejectedByEdge: Bool
    let wasRejectedByBottomArea: Bool
    let wasRejectedByMotion: Bool
    let wasRejectedByCamera: Bool
    let rejectionReason: String?
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
    let averageNormalizedImageX: Double?
    let averageNormalizedImageY: Double?
    let averageImageEdgeMargin: Double?
    let finalPositionVariationMm: Double?
    let finalRotationVariationDegrees: Double?
    let finalAverageNormal: SIMD3<Double>?
    let finalNormalStdDevDegrees: Double?
    let finalNormalPeakToPeakDegrees: Double?
    let finalWorstNormalDifferenceDegrees: Double?
    let finalDualTagNormalStdDevDegrees: Double?
    let finalFallbackNormalStdDevDegrees: Double?
    let finalDualFallbackNormalDifferenceDegrees: Double?
    let finalAverageMotionStabilityScore: Double?
    let finalConfidence: FinalPoseMarkerConfidence
    let finalConfidenceReason: String?
    let edgeDiscardedObservationCount: Int
    let smallBottomDiscardedObservationCount: Int
    let reprojectionDiscardedObservationCount: Int
    let lowPriorityFallbackDiscardedObservationCount: Int
    let normalOutlierDiscardedObservationCount: Int
    let motionDiscardedObservationCount: Int
    let motionPenalizedObservationCount: Int
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
        let maximumFinalObservationsPerMarker: Int
        let finalTopObservationRatio: Double
        let minimumObservationMarkerAreaPixels: Double
        let minimumBottomTagAreaForHighConfidenceDual: Double
        let minimumPreferredImageEdgeMargin: Double
        let hardRejectImageEdgeMargin: Double
        let idealMinimumDistanceMm: Double
        let idealMaximumDistanceMm: Double
        let maximumDistanceMm: Double
        let maximumFinalPositionOutlierMm: Double
        let maximumFinalRotationOutlierDegrees: Double
        let maximumFinalNormalOutlierDegrees: Double
        let minimumMotionStabilityScoreForFinalUse: Double
        let minimumFinalObservationsAfterOutlierRejection: Int
        let minimumRobustReferenceObservations: Int

        static let scannerDefault = Configuration(
            maximumObservationReprojectionError: 2.0,
            minimumObservationsPerMarker: 2,
            maximumAcceptedReprojectionError: 2.0,
            maximumAcceptedErrorMultiplier: 1.25,
            maximumCameraMatrixDelta: 0.5,
            minimumFinalObservationsPerMarker: 8,
            maximumFinalObservationsPerMarker: 40,
            finalTopObservationRatio: 0.4,
            minimumObservationMarkerAreaPixels: 80.0,
            minimumBottomTagAreaForHighConfidenceDual: 120.0,
            minimumPreferredImageEdgeMargin: 0.15,
            hardRejectImageEdgeMargin: 0.06,
            idealMinimumDistanceMm: 80.0,
            idealMaximumDistanceMm: 180.0,
            maximumDistanceMm: 250.0,
            maximumFinalPositionOutlierMm: 1.0,
            maximumFinalRotationOutlierDegrees: 5.0,
            maximumFinalNormalOutlierDegrees: 3.0,
            minimumMotionStabilityScoreForFinalUse: 0.20,
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
        preferDualTagForFinalExport: Bool = true,
        maximumFinalNormalOutlierDegrees: Double? = nil
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
            preferDualTagForFinalExport: preferDualTagForFinalExport,
            maximumFinalNormalOutlierDegrees: maximumFinalNormalOutlierDegrees
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
        preferDualTagForFinalExport: Bool = true,
        maximumFinalNormalOutlierDegrees: Double? = nil
    ) -> [Int: FinalPoseObservationSelectionDiagnostics] {
        let observationsByMarkerId = Dictionary(grouping: observations, by: \.markerId)

        return observationsByMarkerId.reduce(into: [:]) { partialResult, item in
            partialResult[item.key] = selectedObservationSelection(
                markerId: item.key,
                observations: item.value,
                preferDualTagForFinalExport: preferDualTagForFinalExport,
                maximumFinalNormalOutlierDegrees: maximumFinalNormalOutlierDegrees
            ).diagnostics
        }
    }

    private func refinedCameraPoses(
        observations: [FinalPoseObservation],
        currentPosesByMarkerId: [Int: PoseResult],
        preferDualTagForFinalExport: Bool,
        maximumFinalNormalOutlierDegrees: Double?
    ) -> [Int: PoseResult] {
        let observationsByMarkerId = Dictionary(grouping: observations, by: \.markerId)
        var refinedPosesByMarkerId: [Int: PoseResult] = [:]

        for (markerId, markerObservations) in observationsByMarkerId {
            guard let currentPose = currentPosesByMarkerId[markerId],
                  let refinedPose = refinedCameraPose(
                    markerId: markerId,
                    observations: markerObservations,
                    currentPose: currentPose,
                    preferDualTagForFinalExport: preferDualTagForFinalExport,
                    maximumFinalNormalOutlierDegrees: maximumFinalNormalOutlierDegrees
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
        preferDualTagForFinalExport: Bool,
        maximumFinalNormalOutlierDegrees: Double?
    ) -> PoseResult? {
        let selection = selectedObservationSelection(
            markerId: markerId,
            observations: observations,
            preferDualTagForFinalExport: preferDualTagForFinalExport,
            maximumFinalNormalOutlierDegrees: maximumFinalNormalOutlierDegrees
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
              let rotationMatrix = Self.matrix3x3(from: bridgeResult.rotationMatrix),
              let translationVector = Self.vector3(from: bridgeResult.translationVector)
        else {
            return nil
        }
        let finalRotationMatrix = weightedRotationMatrix(
            from: compatibleObservations,
            fallbackRotationMatrix: rotationMatrix
        )
        guard let finalRotationVector = PoseMath.rotationVector(from: finalRotationMatrix),
              PoseMath.isFinite(finalRotationVector)
        else {
            return nil
        }

        return PoseResult(
            markerId: markerId,
            markerProfile: currentPose.markerProfile,
            poseSource: currentPose.poseSource,
            rotationVector: finalRotationVector,
            rotationMatrix: finalRotationMatrix,
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
        preferDualTagForFinalExport: Bool,
        maximumFinalNormalOutlierDegrees: Double?
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
        let qualitiesByOffset = qualityByOffset(for: indexedObservations)
        var discardReasonCounts: [String: Int] = [:]
        let structurallyValidIndexedObservations = indexedObservations.filter { item in
            if let reason = structuralQualityRejectionReason(
                for: item.element,
                quality: qualitiesByOffset[item.offset]
            ) {
                discardReasonCounts[reason, default: 0] += 1
                return false
            }

            return true
        }
        let validIndexedObservations: [(offset: Int, element: FinalPoseObservation)]
        if preferDualTagForFinalExport {
            let edgeFilteredIndexedObservations = indexedObservationsAfterConditionalRejection(
                from: structurallyValidIndexedObservations,
                qualitiesByOffset: qualitiesByOffset,
                reason: "borda da imagem",
                shouldReject: { $0.wasHardRejectedByEdge },
                discardReasonCounts: &discardReasonCounts
            )
            let bottomFilteredIndexedObservations = indexedObservationsAfterConditionalRejection(
                from: edgeFilteredIndexedObservations,
                qualitiesByOffset: qualitiesByOffset,
                reason: "bottom pequena",
                shouldReject: { $0.wasRejectedByBottomArea },
                discardReasonCounts: &discardReasonCounts
            )
            validIndexedObservations = indexedObservationsAfterConditionalRejection(
                from: bottomFilteredIndexedObservations,
                qualitiesByOffset: qualitiesByOffset,
                reason: "movimento alto",
                shouldReject: { $0.wasRejectedByMotion },
                discardReasonCounts: &discardReasonCounts
            )
        } else {
            validIndexedObservations = structurallyValidIndexedObservations
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
            qualityScore(for: $0.element, qualitiesByOffset: qualitiesByOffset[$0.offset]) >
                qualityScore(for: $1.element, qualitiesByOffset: qualitiesByOffset[$1.offset])
        }
        let selectedCount = selectedObservationCount(from: sortedCandidates.count)
        let selectedIndexedObservations = Array(sortedCandidates.prefix(selectedCount))
        let preOutlierSelectedIndices = Set(selectedIndexedObservations.map(\.offset))
        for item in candidateIndexedObservations where !preOutlierSelectedIndices.contains(item.offset) {
            discardReasonCounts["baixa qualidade", default: 0] += 1
        }

        let outlierResult = selectedIndexedObservationsAfterOutlierRejection(
            from: selectedIndexedObservations,
            maximumFinalNormalOutlierDegrees: maximumFinalNormalOutlierDegrees
        )
        for (reason, count) in outlierResult.discardReasonCounts {
            discardReasonCounts[reason, default: 0] += count
        }

        let selectedObservations = outlierResult.indexedObservations.map(\.element)
        let selectedQualities = qualities(
            for: outlierResult.indexedObservations,
            qualitiesByOffset: qualitiesByOffset
        )
        let discardedObservationCount = max(observations.count - selectedObservations.count, 0)
        let averageReprojectionError = averageReprojectionError(in: selectedObservations)
        let averageQualityScore = averageQualityScore(in: selectedQualities)
        let averageImagePosition = averageImagePosition(in: selectedQualities)
        let averageEdgeMargin = averageImageEdgeMargin(in: selectedQualities)
        let positionVariation = averagePositionVariationMm(in: selectedObservations)
        let rotationVariation = averageRotationVariationDegrees(in: selectedObservations)
        let normalDiagnostics = normalDiagnostics(in: selectedObservations)
        let motionPenalizedObservationCount = qualitiesByOffset.values.filter {
            $0.motionStabilityScore.isFinite && $0.motionStabilityScore < 0.999
        }.count
        let normalOutlierThresholdDegrees = resolvedMaximumFinalNormalOutlierDegrees(
            maximumFinalNormalOutlierDegrees
        )
        let confidence = finalConfidence(
            selectedObservations: selectedObservations,
            observationsBeforeOutlierRejectionCount: selectedIndexedObservations.count,
            outlierRemovedCount: outlierResult.removedCount,
            averageReprojectionError: averageReprojectionError,
            averageImageEdgeMargin: averageEdgeMargin,
            normalStdDevDegrees: normalDiagnostics.stdDevDegrees,
            maximumFinalNormalOutlierDegrees: normalOutlierThresholdDegrees,
            averageMotionStabilityScore: averageMotionStabilityScore(in: selectedQualities),
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
                averageNormalizedImageX: averageImagePosition.x,
                averageNormalizedImageY: averageImagePosition.y,
                averageImageEdgeMargin: averageEdgeMargin,
                finalPositionVariationMm: positionVariation,
                finalRotationVariationDegrees: rotationVariation,
                finalAverageNormal: normalDiagnostics.averageNormal,
                finalNormalStdDevDegrees: normalDiagnostics.stdDevDegrees,
                finalNormalPeakToPeakDegrees: normalDiagnostics.peakToPeakDegrees,
                finalWorstNormalDifferenceDegrees: normalDiagnostics.worstDifferenceDegrees,
                finalDualTagNormalStdDevDegrees: normalDiagnostics.dualStdDevDegrees,
                finalFallbackNormalStdDevDegrees: normalDiagnostics.fallbackStdDevDegrees,
                finalDualFallbackNormalDifferenceDegrees:
                    normalDiagnostics.dualFallbackDifferenceDegrees,
                finalAverageMotionStabilityScore: averageMotionStabilityScore(
                    in: selectedQualities
                ),
                finalConfidence: confidence.value,
                finalConfidenceReason: confidence.reason,
                edgeDiscardedObservationCount: discardReasonCounts["borda da imagem"] ?? 0,
                smallBottomDiscardedObservationCount: discardReasonCounts["bottom pequena"] ?? 0,
                reprojectionDiscardedObservationCount:
                    discardReasonCounts["reprojection error alto"] ?? 0,
                lowPriorityFallbackDiscardedObservationCount:
                    lowPriorityFallbackDiscardCount(in: discardReasonCounts),
                normalOutlierDiscardedObservationCount:
                    discardReasonCounts["outlier normal"] ?? 0,
                motionDiscardedObservationCount: discardReasonCounts["movimento alto"] ?? 0,
                motionPenalizedObservationCount: motionPenalizedObservationCount,
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
        let selectedQualities = selectedObservations.map { observationQuality(for: $0) }
        let averageImagePosition = averageImagePosition(in: selectedQualities)
        let normalDiagnostics = normalDiagnostics(in: selectedObservations)

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
                finalAverageQualityScore: averageQualityScore(in: selectedQualities),
                averageNormalizedImageX: averageImagePosition.x,
                averageNormalizedImageY: averageImagePosition.y,
                averageImageEdgeMargin: averageImageEdgeMargin(in: selectedQualities),
                finalPositionVariationMm: averagePositionVariationMm(in: selectedObservations),
                finalRotationVariationDegrees: averageRotationVariationDegrees(in: selectedObservations),
                finalAverageNormal: normalDiagnostics.averageNormal,
                finalNormalStdDevDegrees: normalDiagnostics.stdDevDegrees,
                finalNormalPeakToPeakDegrees: normalDiagnostics.peakToPeakDegrees,
                finalWorstNormalDifferenceDegrees: normalDiagnostics.worstDifferenceDegrees,
                finalDualTagNormalStdDevDegrees: normalDiagnostics.dualStdDevDegrees,
                finalFallbackNormalStdDevDegrees: normalDiagnostics.fallbackStdDevDegrees,
                finalDualFallbackNormalDifferenceDegrees:
                    normalDiagnostics.dualFallbackDifferenceDegrees,
                finalAverageMotionStabilityScore: averageMotionStabilityScore(
                    in: selectedQualities
                ),
                finalConfidence: selectedObservations.isEmpty ? .low : .medium,
                finalConfidenceReason: selectedObservations.isEmpty ? "sem observacoes finais" : nil,
                edgeDiscardedObservationCount: 0,
                smallBottomDiscardedObservationCount: 0,
                reprojectionDiscardedObservationCount: discardedObservationCount,
                lowPriorityFallbackDiscardedObservationCount: 0,
                normalOutlierDiscardedObservationCount: 0,
                motionDiscardedObservationCount: 0,
                motionPenalizedObservationCount: selectedQualities.filter {
                    $0.motionStabilityScore.isFinite && $0.motionStabilityScore < 0.999
                }.count,
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
        let cappedDesiredCount = min(desiredCount, configuration.maximumFinalObservationsPerMarker)

        return min(candidateCount, cappedDesiredCount)
    }

    private func selectedIndexedObservationsAfterOutlierRejection(
        from indexedObservations: [(offset: Int, element: FinalPoseObservation)],
        maximumFinalNormalOutlierDegrees: Double?
    ) -> OutlierRejectionResult {
        let normalOutlierThresholdDegrees = resolvedMaximumFinalNormalOutlierDegrees(
            maximumFinalNormalOutlierDegrees
        )
        let robustReferenceObservations = robustReferenceIndexedObservations(from: indexedObservations)
        guard indexedObservations.count >= configuration.minimumFinalObservationsAfterOutlierRejection,
              configuration.maximumFinalPositionOutlierMm.isFinite,
              configuration.maximumFinalPositionOutlierMm > 0,
              configuration.maximumFinalRotationOutlierDegrees.isFinite,
              configuration.maximumFinalRotationOutlierDegrees > 0,
              let referenceTranslation = medianTranslation(from: robustReferenceObservations),
              let referenceRotation = referenceRotationMatrix(from: robustReferenceObservations)
        else {
            return OutlierRejectionResult(
                indexedObservations: indexedObservations,
                removedCount: 0,
                discardReasonCounts: [:],
                wasRelaxed: false
            )
        }
        let referenceNormal = averageMarkerNormal(in: robustReferenceObservations.map(\.element))

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
            let normalDistanceDegrees: Double
            if let referenceNormal,
               let observationNormal = markerNormal(for: item.element.rotationMatrix) {
                normalDistanceDegrees = Self.normalAngularDistanceDegrees(
                    observationNormal,
                    referenceNormal
                )
            } else {
                normalDistanceDegrees = .infinity
            }
            let isPositionOutlier = positionDistanceMm.isFinite &&
                positionDistanceMm > configuration.maximumFinalPositionOutlierMm
            let isRotationOutlier = rotationDistanceDegrees.isFinite &&
                rotationDistanceDegrees > configuration.maximumFinalRotationOutlierDegrees
            let isNormalOutlier = normalDistanceDegrees.isFinite &&
                normalDistanceDegrees > normalOutlierThresholdDegrees

            if isNormalOutlier {
                discardReasonCounts["outlier normal", default: 0] += 1
            } else if isPositionOutlier && isRotationOutlier {
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

    private func structuralQualityRejectionReason(
        for observation: FinalPoseObservation,
        quality: PoseObservationQuality?
    ) -> String? {
        let structuralReasons = Set([
            "pose invalida",
            "reprojection error alto",
            "area baixa"
        ])
        if let rejectionReason = quality?.rejectionReason,
           structuralReasons.contains(rejectionReason) {
            return rejectionReason
        }

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

        return nil
    }

    private func indexedObservationsAfterConditionalRejection(
        from indexedObservations: [(offset: Int, element: FinalPoseObservation)],
        qualitiesByOffset: [Int: PoseObservationQuality],
        reason: String,
        shouldReject: (PoseObservationQuality) -> Bool,
        discardReasonCounts: inout [String: Int]
    ) -> [(offset: Int, element: FinalPoseObservation)] {
        guard indexedObservations.count > configuration.minimumFinalObservationsAfterOutlierRejection else {
            return indexedObservations
        }

        let rejectedObservations = indexedObservations.filter {
            guard let quality = qualitiesByOffset[$0.offset] else {
                return false
            }

            return shouldReject(quality)
        }
        guard !rejectedObservations.isEmpty else {
            return indexedObservations
        }

        let betterObservations = indexedObservations.filter {
            guard let quality = qualitiesByOffset[$0.offset] else {
                return true
            }

            return !shouldReject(quality)
        }
        guard betterObservations.count >= configuration.minimumFinalObservationsAfterOutlierRejection else {
            return indexedObservations
        }

        discardReasonCounts[reason, default: 0] += rejectedObservations.count
        return betterObservations
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

    private func qualityByOffset(
        for indexedObservations: [(offset: Int, element: FinalPoseObservation)]
    ) -> [Int: PoseObservationQuality] {
        Dictionary(
            uniqueKeysWithValues: indexedObservations.map {
                ($0.offset, observationQuality(for: $0.element))
            }
        )
    }

    private func qualities(
        for indexedObservations: [(offset: Int, element: FinalPoseObservation)],
        qualitiesByOffset: [Int: PoseObservationQuality]
    ) -> [PoseObservationQuality] {
        indexedObservations.compactMap { qualitiesByOffset[$0.offset] }
    }

    private func averageQualityScore(in qualities: [PoseObservationQuality]) -> Double? {
        let scores = qualities
            .map(\.qualityScore)
            .filter { $0.isFinite }

        guard !scores.isEmpty else {
            return nil
        }

        return scores.reduce(0.0, +) / Double(scores.count)
    }

    private func averageImagePosition(
        in qualities: [PoseObservationQuality]
    ) -> (x: Double?, y: Double?) {
        (
            x: average(qualities.compactMap(\.normalizedImageX)),
            y: average(qualities.compactMap(\.normalizedImageY))
        )
    }

    private func averageImageEdgeMargin(in qualities: [PoseObservationQuality]) -> Double? {
        average(qualities.compactMap(\.edgeMargin))
    }

    private func averagePositionVariationMm(in observations: [FinalPoseObservation]) -> Double? {
        guard observations.count >= 2,
              let referenceTranslation = medianTranslation(
                from: Array(observations.enumerated())
              )
        else {
            return nil
        }

        let distances = observations
            .map { simd_distance($0.translationVector, referenceTranslation) }
            .filter { $0.isFinite }

        return average(distances)
    }

    private func averageRotationVariationDegrees(in observations: [FinalPoseObservation]) -> Double? {
        let indexedObservations = Array(observations.enumerated())
        guard indexedObservations.count >= 2,
              let referenceRotation = referenceRotationMatrix(from: indexedObservations)
        else {
            return nil
        }

        let distances = observations
            .map { Self.rotationAngularDistanceDegrees($0.rotationMatrix, referenceRotation) }
            .filter { $0.isFinite }

        return average(distances)
    }

    private func averageMotionStabilityScore(in qualities: [PoseObservationQuality]) -> Double? {
        average(qualities.map(\.motionStabilityScore))
    }

    private func normalDiagnostics(
        in observations: [FinalPoseObservation]
    ) -> (
        averageNormal: SIMD3<Double>?,
        stdDevDegrees: Double?,
        peakToPeakDegrees: Double?,
        worstDifferenceDegrees: Double?,
        dualStdDevDegrees: Double?,
        fallbackStdDevDegrees: Double?,
        dualFallbackDifferenceDegrees: Double?
    ) {
        let averageNormal = averageMarkerNormal(in: observations)
        let stdDev = normalStdDevDegrees(in: observations, referenceNormal: averageNormal)
        let peakToPeak = normalPeakToPeakDegrees(in: observations)
        let worstDifference = normalWorstDifferenceDegrees(
            in: observations,
            referenceNormal: averageNormal
        )
        let dualObservations = observations.filter { isDualTagObservation($0) }
        let fallbackObservations = observations.filter { !isDualTagObservation($0) }
        let dualAverageNormal = averageMarkerNormal(in: dualObservations)
        let fallbackAverageNormal = averageMarkerNormal(in: fallbackObservations)
        let dualFallbackDifference: Double?
        if let dualAverageNormal,
           let fallbackAverageNormal {
            dualFallbackDifference = Self.normalAngularDistanceDegrees(
                dualAverageNormal,
                fallbackAverageNormal
            )
        } else {
            dualFallbackDifference = nil
        }

        return (
            averageNormal: averageNormal,
            stdDevDegrees: stdDev,
            peakToPeakDegrees: peakToPeak,
            worstDifferenceDegrees: worstDifference,
            dualStdDevDegrees: normalStdDevDegrees(
                in: dualObservations,
                referenceNormal: dualAverageNormal
            ),
            fallbackStdDevDegrees: normalStdDevDegrees(
                in: fallbackObservations,
                referenceNormal: fallbackAverageNormal
            ),
            dualFallbackDifferenceDegrees: dualFallbackDifference
        )
    }

    private func averageMarkerNormal(in observations: [FinalPoseObservation]) -> SIMD3<Double>? {
        let normals = observations.compactMap { markerNormal(for: $0.rotationMatrix) }
        return averageNormal(normals)
    }

    private func averageNormal(_ normals: [SIMD3<Double>]) -> SIMD3<Double>? {
        guard let firstNormal = normals.first else {
            return nil
        }

        var sum = SIMD3<Double>(repeating: 0.0)
        for normal in normals {
            guard PoseMath.isFinite(normal) else {
                continue
            }

            let alignedNormal = simd_dot(normal, firstNormal) < 0 ? -normal : normal
            sum += alignedNormal
        }

        let length = simd_length(sum)
        guard length.isFinite, length > 1e-9 else {
            return nil
        }

        let normal = sum / length
        return PoseMath.isFinite(normal) ? normal : nil
    }

    private func markerNormal(for rotationMatrix: simd_double3x3) -> SIMD3<Double>? {
        guard PoseMath.isFinite(rotationMatrix) else {
            return nil
        }

        // The ArUco object points lie on z = 0, so local +Z is the marker plane normal.
        let normal = rotationMatrix * SIMD3<Double>(0.0, 0.0, 1.0)
        let length = simd_length(normal)
        guard length.isFinite, length > 1e-9 else {
            return nil
        }

        let normalized = normal / length
        return PoseMath.isFinite(normalized) ? normalized : nil
    }

    private func normalStdDevDegrees(
        in observations: [FinalPoseObservation],
        referenceNormal: SIMD3<Double>?
    ) -> Double? {
        guard let referenceNormal else {
            return nil
        }

        let values = observations
            .compactMap { markerNormal(for: $0.rotationMatrix) }
            .map { Self.normalAngularDistanceDegrees($0, referenceNormal) }
            .filter { $0.isFinite }
        guard values.count >= 2,
              let mean = average(values)
        else {
            return nil
        }

        let variance = values.reduce(0.0) {
            let delta = $1 - mean
            return $0 + delta * delta
        } / Double(values.count)

        let stdDev = sqrt(variance)
        return stdDev.isFinite ? stdDev : nil
    }

    private func normalPeakToPeakDegrees(in observations: [FinalPoseObservation]) -> Double? {
        let normals = observations.compactMap { markerNormal(for: $0.rotationMatrix) }
        guard normals.count >= 2 else {
            return nil
        }

        var maximumDistance = 0.0
        for firstIndex in normals.indices.dropLast() {
            for secondIndex in normals.indices where secondIndex > firstIndex {
                let distance = Self.normalAngularDistanceDegrees(
                    normals[firstIndex],
                    normals[secondIndex]
                )
                if distance.isFinite {
                    maximumDistance = max(maximumDistance, distance)
                }
            }
        }

        return maximumDistance.isFinite ? maximumDistance : nil
    }

    private func normalWorstDifferenceDegrees(
        in observations: [FinalPoseObservation],
        referenceNormal: SIMD3<Double>?
    ) -> Double? {
        guard let referenceNormal else {
            return nil
        }

        let distances = observations
            .compactMap { markerNormal(for: $0.rotationMatrix) }
            .map { Self.normalAngularDistanceDegrees($0, referenceNormal) }
            .filter { $0.isFinite }
        return distances.max()
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
        averageImageEdgeMargin: Double?,
        normalStdDevDegrees: Double?,
        maximumFinalNormalOutlierDegrees: Double,
        averageMotionStabilityScore: Double?,
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

        if let averageImageEdgeMargin = averageImageEdgeMargin,
           averageImageEdgeMargin < configuration.hardRejectImageEdgeMargin {
            return (.low, "muitos frames de borda")
        }

        if let normalStdDevDegrees,
           normalStdDevDegrees > maximumFinalNormalOutlierDegrees {
            return (.low, "normal instavel")
        }

        if let averageMotionStabilityScore,
           averageMotionStabilityScore < 0.45 {
            return (.low, "movimento alto")
        }

        let dualTagObservationCount = selectedObservations.filter {
            isDualTagObservation($0)
        }.count
        if selectedObservations.count >= configuration.minimumFinalObservationsPerMarker,
           dualTagObservationCount >= configuration.minimumFinalObservationsPerMarker,
           (averageReprojectionError ?? .infinity) <= 1.2,
           (averageImageEdgeMargin ?? 1.0) >= configuration.minimumPreferredImageEdgeMargin,
           (normalStdDevDegrees ?? 0.0) <= maximumFinalNormalOutlierDegrees * 0.60,
           (averageMotionStabilityScore ?? 1.0) >= 0.75,
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

    private func qualityScore(
        for observation: FinalPoseObservation,
        qualitiesByOffset quality: PoseObservationQuality?
    ) -> Double {
        quality?.qualityScore ?? qualityScore(for: observation)
    }

    private func qualityScore(for observation: FinalPoseObservation) -> Double {
        observationQuality(for: observation).qualityScore
    }

    private func positionWeightMultiplier(for source: MarkerPoseSource) -> Double {
        switch source {
        case .dualTag:
            return 1.0
        case let .singleFallback(_, role):
            return role == .top ? 0.35 : 0.15
        case .singleArucoV1:
            return 1.0
        }
    }

    private func rotationWeightMultiplier(for source: MarkerPoseSource) -> Double {
        switch source {
        case .dualTag:
            return 1.0
        case let .singleFallback(_, role):
            return role == .top ? 0.15 : 0.05
        case .singleArucoV1:
            return 1.0
        }
    }

    private func rotationWeight(for observation: FinalPoseObservation) -> Double {
        let quality = observationQuality(for: observation)
        let positionSourceWeight = max(positionWeightMultiplier(for: observation.poseSource), 0.001)
        let rotationSourceWeight = rotationWeightMultiplier(for: observation.poseSource)
        let bottomRotationConfidence = quality.wasRejectedByBottomArea ? 0.35 : 1.0
        let motionAdjustment = quality.motionStabilityScore > 0
            ? quality.motionRotationStabilityScore / quality.motionStabilityScore
            : quality.motionRotationStabilityScore
        let cameraAdjustment = quality.cameraStabilityScore > 0
            ? quality.cameraRotationStabilityScore / quality.cameraStabilityScore
            : quality.cameraRotationStabilityScore
        let weight = quality.qualityScore /
            positionSourceWeight *
            rotationSourceWeight *
            bottomRotationConfidence *
            min(max(motionAdjustment, 0.05), 1.0) *
            min(max(cameraAdjustment, 0.05), 1.0)

        return weight.isFinite ? max(weight, 0.0) : 0.0
    }

    private func weightedRotationMatrix(
        from observations: [FinalPoseObservation],
        fallbackRotationMatrix: simd_double3x3
    ) -> simd_double3x3 {
        guard observations.count >= 2,
              let referenceObservation = observations.max(by: {
                rotationWeight(for: $0) < rotationWeight(for: $1)
              }),
              let referenceQuaternion = PoseMath.quaternion(
                fromRotationMatrix: referenceObservation.rotationMatrix
              )
        else {
            return fallbackRotationMatrix
        }

        var accumulated = SIMD4<Double>(repeating: 0.0)
        var totalWeight = 0.0
        for observation in observations {
            let weight = rotationWeight(for: observation)
            guard weight > 0,
                  let quaternion = PoseMath.quaternion(fromRotationMatrix: observation.rotationMatrix)
            else {
                continue
            }

            var vector = quaternion.vector
            if simd_dot(vector, referenceQuaternion.vector) < 0 {
                vector = -vector
            }
            accumulated += vector * weight
            totalWeight += weight
        }

        guard totalWeight > 0 else {
            return fallbackRotationMatrix
        }

        let length = simd_length(accumulated)
        guard length.isFinite, length > 1e-9 else {
            return fallbackRotationMatrix
        }

        let normalizedQuaternion = accumulated / length
        let quaternion = simd_quatd(
            ix: normalizedQuaternion.x,
            iy: normalizedQuaternion.y,
            iz: normalizedQuaternion.z,
            r: normalizedQuaternion.w
        )
        guard PoseMath.isFinite(quaternion) else {
            return fallbackRotationMatrix
        }

        let matrix = simd_double3x3(quaternion)
        return PoseMath.isFinite(matrix) ? matrix : fallbackRotationMatrix
    }

    private func observationQuality(for observation: FinalPoseObservation) -> PoseObservationQuality {
        guard isValidObservationPose(observation) else {
            return PoseObservationQuality(
                markerId: observation.markerId,
                source: observation.poseSource,
                qualityScore: 0,
                reprojectionError: observation.reprojectionError,
                topAreaPixels: observation.topTagAreaPixels,
                bottomAreaPixels: observation.bottomTagAreaPixels,
                normalizedImageX: nil,
                normalizedImageY: nil,
                edgeMargin: nil,
                markerNormal: nil,
                motionStabilityScore: observation.motionQuality?.stabilityScore ?? 1.0,
                motionRotationStabilityScore:
                    observation.motionQuality?.rotationStabilityScore ?? 1.0,
                cameraStabilityScore: observation.cameraQuality?.cameraStabilityScore ?? 1.0,
                cameraRotationStabilityScore:
                    observation.cameraQuality?.rotationStabilityScore ?? 1.0,
                wasNearImageEdge: false,
                wasHardRejectedByEdge: false,
                wasRejectedByBottomArea: false,
                wasRejectedByMotion: false,
                wasRejectedByCamera: false,
                rejectionReason: "pose invalida"
            )
        }

        let reprojectionScore = qualityScoreForReprojectionError(observation.reprojectionError)
        let areaScore = qualityScoreForMarkerArea(observation)
        let distanceScore = qualityScoreForDistance(observation.distanceMm)
        let imageCenterScore = qualityScoreForImagePosition(observation)
        let normalizedCenter = normalizedImageCenter(for: observation)
        let edgeMargin = normalizedImageEdgeMargin(for: observation)
        let wasNearImageEdge = edgeMargin < configuration.minimumPreferredImageEdgeMargin
        let wasHardRejectedByEdge = edgeMargin < configuration.hardRejectImageEdgeMargin
        let wasRejectedByBottomArea = isLowConfidenceBottomArea(observation)
        let sourceScore = positionWeightMultiplier(for: observation.poseSource)
        let bottomConfidenceScore = wasRejectedByBottomArea ? 0.25 : 1.0
        let motionStabilityScore = observation.motionQuality?.stabilityScore ?? 1.0
        let motionRotationStabilityScore =
            observation.motionQuality?.rotationStabilityScore ?? motionStabilityScore
        let wasRejectedByMotion = motionStabilityScore <
            configuration.minimumMotionStabilityScoreForFinalUse
        let cameraStabilityScore = observation.cameraQuality?.cameraStabilityScore ?? 1.0
        let cameraRotationStabilityScore =
            observation.cameraQuality?.rotationStabilityScore ?? cameraStabilityScore
        let wasRejectedByCamera = cameraStabilityScore < 0.999
        let rawScore = sourceScore *
            reprojectionScore *
            areaScore *
            distanceScore *
            imageCenterScore *
            bottomConfidenceScore *
            motionStabilityScore *
            cameraStabilityScore
        let rejectionReason: String?
        if reprojectionScore <= 0 {
            rejectionReason = "reprojection error alto"
        } else if areaScore <= 0 {
            rejectionReason = "area baixa"
        } else if wasHardRejectedByEdge {
            rejectionReason = "borda da imagem"
        } else if wasRejectedByBottomArea {
            rejectionReason = "bottom pequena"
        } else if wasRejectedByMotion {
            rejectionReason = "movimento alto"
        } else if wasRejectedByCamera {
            rejectionReason = "camera ajustando"
        } else {
            rejectionReason = nil
        }

        return PoseObservationQuality(
            markerId: observation.markerId,
            source: observation.poseSource,
            qualityScore: rawScore.isFinite ? max(rawScore, 0) : 0,
            reprojectionError: observation.reprojectionError,
            topAreaPixels: observation.topTagAreaPixels,
            bottomAreaPixels: observation.bottomTagAreaPixels,
            normalizedImageX: normalizedCenter.map { Double($0.x) },
            normalizedImageY: normalizedCenter.map { Double($0.y) },
            edgeMargin: edgeMargin.isFinite ? edgeMargin : nil,
            markerNormal: markerNormal(for: observation.rotationMatrix),
            motionStabilityScore: motionStabilityScore.isFinite ? motionStabilityScore : 1.0,
            motionRotationStabilityScore: motionRotationStabilityScore.isFinite
                ? motionRotationStabilityScore
                : 1.0,
            cameraStabilityScore: cameraStabilityScore.isFinite ? cameraStabilityScore : 1.0,
            cameraRotationStabilityScore: cameraRotationStabilityScore.isFinite
                ? cameraRotationStabilityScore
                : 1.0,
            wasNearImageEdge: wasNearImageEdge,
            wasHardRejectedByEdge: wasHardRejectedByEdge,
            wasRejectedByBottomArea: wasRejectedByBottomArea,
            wasRejectedByMotion: wasRejectedByMotion,
            wasRejectedByCamera: wasRejectedByCamera,
            rejectionReason: rejectionReason
        )
    }

    private func isLowConfidenceBottomArea(_ observation: FinalPoseObservation) -> Bool {
        guard case .dualTag = observation.poseSource else {
            return false
        }

        guard let bottomTagAreaPixels = observation.bottomTagAreaPixels,
              bottomTagAreaPixels.isFinite
        else {
            return true
        }

        return bottomTagAreaPixels < configuration.minimumBottomTagAreaForHighConfidenceDual
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
        let edgeMargin = normalizedImageEdgeMargin(for: observation)
        guard edgeMargin.isFinite else {
            return 0
        }

        if edgeMargin >= configuration.minimumPreferredImageEdgeMargin {
            return 1
        }

        if edgeMargin < configuration.hardRejectImageEdgeMargin {
            return 0.08
        }

        let usableRange = max(
            configuration.minimumPreferredImageEdgeMargin - configuration.hardRejectImageEdgeMargin,
            0.001
        )
        let normalized = (edgeMargin - configuration.hardRejectImageEdgeMargin) / usableRange
        return min(max(0.25 + normalized * 0.75, 0.25), 1.0)
    }

    private func normalizedImageEdgeMargin(for observation: FinalPoseObservation) -> Double {
        guard let center = normalizedImageCenter(for: observation) else {
            return 0
        }

        return [
            Double(center.x),
            1.0 - Double(center.x),
            Double(center.y),
            1.0 - Double(center.y)
        ].min() ?? 0
    }

    private func normalizedImageCenter(for observation: FinalPoseObservation) -> CGPoint? {
        guard !observation.imagePoints.isEmpty,
              observation.frameSizePixels.width.isFinite,
              observation.frameSizePixels.height.isFinite,
              observation.frameSizePixels.width > 0,
              observation.frameSizePixels.height > 0
        else {
            return nil
        }

        let sum = observation.imagePoints.reduce(CGPoint.zero) { partialResult, point in
            CGPoint(
                x: partialResult.x + point.x,
                y: partialResult.y + point.y
            )
        }
        let pointCount = CGFloat(observation.imagePoints.count)
        let frameWidth = observation.frameSizePixels.width
        let frameHeight = observation.frameSizePixels.height
        let center = CGPoint(
            x: sum.x / pointCount / frameWidth,
            y: sum.y / pointCount / frameHeight
        )

        guard center.x.isFinite, center.y.isFinite else {
            return nil
        }

        return CGPoint(
            x: min(max(center.x, 0), 1),
            y: min(max(center.y, 0), 1)
        )
    }

    private func dominantReason(in counts: [String: Int]) -> String? {
        counts.max {
            if $0.value == $1.value {
                return $0.key > $1.key
            }

            return $0.value < $1.value
        }?.key
    }

    private func average(_ values: [Double]) -> Double? {
        let finiteValues = values.filter { $0.isFinite }
        guard !finiteValues.isEmpty else {
            return nil
        }

        return finiteValues.reduce(0.0, +) / Double(finiteValues.count)
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

    private func resolvedMaximumFinalNormalOutlierDegrees(_ override: Double?) -> Double {
        guard let override,
              override.isFinite,
              override > 0
        else {
            return configuration.maximumFinalNormalOutlierDegrees
        }

        return override
    }

    private static func normalAngularDistanceDegrees(
        _ lhs: SIMD3<Double>,
        _ rhs: SIMD3<Double>
    ) -> Double {
        guard PoseMath.isFinite(lhs), PoseMath.isFinite(rhs) else {
            return .infinity
        }

        let lhsLength = simd_length(lhs)
        let rhsLength = simd_length(rhs)
        guard lhsLength.isFinite, rhsLength.isFinite, lhsLength > 1e-9, rhsLength > 1e-9 else {
            return .infinity
        }

        let cosineTheta = min(max(simd_dot(lhs / lhsLength, rhs / rhsLength), -1.0), 1.0)
        let radians = acos(cosineTheta)
        guard radians.isFinite else {
            return .infinity
        }

        return radians * 180.0 / Double.pi
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
