import Foundation
import simd

struct ScanSessionReplayMarkerPairGeometryComparison: Codable, Equatable, Sendable {
    let markerAId: Int
    let markerBId: Int
    let allDistanceMm: Double
    let filteredDistanceMm: Double
    let signedDistanceDeltaMm: Double
    let absoluteDistanceDeltaMm: Double
    let relativeRotationDeltaDegrees: Double
}

struct ScanSessionReplayMarkerPairIdentity: Codable, Equatable, Hashable, Sendable {
    let markerAId: Int
    let markerBId: Int
}

struct ScanSessionReplayPairwiseGeometryComparison: Codable, Equatable, Sendable {
    let allMarkerIds: [Int]
    let filteredMarkerIds: [Int]
    let missingFromAll: [Int]
    let missingFromFiltered: [Int]
    let missingFromAllPairs: [ScanSessionReplayMarkerPairIdentity]
    let missingFromFilteredPairs: [ScanSessionReplayMarkerPairIdentity]
    let pairs: [ScanSessionReplayMarkerPairGeometryComparison]
    let comparedPairCount: Int
    let meanAbsoluteDistanceDeltaMm: Double
    let maxAbsoluteDistanceDeltaMm: Double
    let meanRelativeRotationDeltaDegrees: Double
    let maxRelativeRotationDeltaDegrees: Double
}

struct ScanSessionPreAccumulationGateABReplaySummary: Codable, Equatable, Sendable {
    let sessionIdentifier: String
    let schemaVersion: Int
    let appGitCommitHash: String?
    let appVersion: String?
    let appBuildIdentifier: String?
    let baselineReplayPolicy: String
    let filteredReplayPolicy: String
    let replayAlgorithmIdentifier: String
    let replayUsesRandomness: Bool
    let framesReplayed: Int
    let selectionDiagnostics: ScanSessionReplaySelectionDiagnostics
    let allDeterminism: ScanSessionReplayDeterminismComparison
    let filteredDeterminism: ScanSessionReplayDeterminismComparison
    let allFinalMarkerIds: [Int]
    let filteredFinalMarkerIds: [Int]
    let allFinalPoses: [ScanSessionReplayFinalPoseSummary]
    let filteredFinalPoses: [ScanSessionReplayFinalPoseSummary]
    let pairwiseRelativeGeometry: ScanSessionReplayPairwiseGeometryComparison
    let integrityResult: String
    let provenanceCaveats: [String]
    let livePreAccumulationBlockingEnabledAtCapture: Bool?
    let offlineFilteredReplayUsesPersistedDecisions: Bool
}

struct ScanSessionPreAccumulationGateABReplayResult {
    let summary: ScanSessionPreAccumulationGateABReplaySummary
    let allReplay: ScanSessionDeterministicReplayResult
    let filteredReplay: ScanSessionDeterministicReplayResult
}

enum ScanSessionReplayPairwiseGeometryComparator {
    static func compare(
        allPoses: [PoseResult],
        filteredPoses: [PoseResult]
    ) -> ScanSessionReplayPairwiseGeometryComparison {
        let allByMarker = posesByMarkerId(allPoses)
        let filteredByMarker = posesByMarkerId(filteredPoses)
        let allIds = allByMarker.keys.sorted()
        let filteredIds = filteredByMarker.keys.sorted()
        let allSet = Set(allIds)
        let filteredSet = Set(filteredIds)
        let commonIds = allSet.intersection(filteredSet).sorted()
        let allPairs = Set(pairIdentities(for: allIds))
        let filteredPairs = Set(pairIdentities(for: filteredIds))
        var pairs: [ScanSessionReplayMarkerPairGeometryComparison] = []

        for firstIndex in commonIds.indices {
            for secondIndex in commonIds.index(after: firstIndex)..<commonIds.endIndex {
                let markerAId = commonIds[firstIndex]
                let markerBId = commonIds[secondIndex]
                guard let allA = allByMarker[markerAId],
                      let allB = allByMarker[markerBId],
                      let filteredA = filteredByMarker[markerAId],
                      let filteredB = filteredByMarker[markerBId]
                else {
                    continue
                }

                let allRelative = relativePose(from: allA, to: allB)
                let filteredRelative = relativePose(from: filteredA, to: filteredB)
                let allDistance = simd_length(allRelative.translation)
                let filteredDistance = simd_length(filteredRelative.translation)
                let signedDistanceDelta = filteredDistance - allDistance
                pairs.append(
                    ScanSessionReplayMarkerPairGeometryComparison(
                        markerAId: markerAId,
                        markerBId: markerBId,
                        allDistanceMm: allDistance,
                        filteredDistanceMm: filteredDistance,
                        signedDistanceDeltaMm: signedDistanceDelta,
                        absoluteDistanceDeltaMm: abs(signedDistanceDelta),
                        relativeRotationDeltaDegrees: rotationAngularDistanceDegrees(
                            allRelative.rotation,
                            filteredRelative.rotation
                        )
                    )
                )
            }
        }

        let distanceDeltas = pairs.map(\.absoluteDistanceDeltaMm)
        let rotationDeltas = pairs.map(\.relativeRotationDeltaDegrees)
        return ScanSessionReplayPairwiseGeometryComparison(
            allMarkerIds: allIds,
            filteredMarkerIds: filteredIds,
            missingFromAll: filteredSet.subtracting(allSet).sorted(),
            missingFromFiltered: allSet.subtracting(filteredSet).sorted(),
            missingFromAllPairs: filteredPairs.subtracting(allPairs).sorted(by: pairSort),
            missingFromFilteredPairs: allPairs.subtracting(filteredPairs).sorted(by: pairSort),
            pairs: pairs,
            comparedPairCount: pairs.count,
            meanAbsoluteDistanceDeltaMm: mean(distanceDeltas),
            maxAbsoluteDistanceDeltaMm: distanceDeltas.max() ?? 0,
            meanRelativeRotationDeltaDegrees: mean(rotationDeltas),
            maxRelativeRotationDeltaDegrees: rotationDeltas.max() ?? 0
        )
    }

    private static func posesByMarkerId(_ poses: [PoseResult]) -> [Int: PoseResult] {
        var result: [Int: PoseResult] = [:]
        for pose in poses {
            result[pose.markerId] = pose
        }
        return result
    }

    private static func pairIdentities(for markerIds: [Int]) -> [ScanSessionReplayMarkerPairIdentity] {
        var result: [ScanSessionReplayMarkerPairIdentity] = []
        for firstIndex in markerIds.indices {
            for secondIndex in markerIds.index(after: firstIndex)..<markerIds.endIndex {
                result.append(
                    ScanSessionReplayMarkerPairIdentity(
                        markerAId: markerIds[firstIndex],
                        markerBId: markerIds[secondIndex]
                    )
                )
            }
        }
        return result
    }

    private static func pairSort(
        _ lhs: ScanSessionReplayMarkerPairIdentity,
        _ rhs: ScanSessionReplayMarkerPairIdentity
    ) -> Bool {
        lhs.markerAId == rhs.markerAId
            ? lhs.markerBId < rhs.markerBId
            : lhs.markerAId < rhs.markerAId
    }

    private static func relativePose(
        from markerA: PoseResult,
        to markerB: PoseResult
    ) -> (rotation: simd_double3x3, translation: SIMD3<Double>) {
        let inverseARotation = simd_transpose(markerA.rotationMatrix)
        return (
            inverseARotation * markerB.rotationMatrix,
            inverseARotation * (markerB.translationVector - markerA.translationVector)
        )
    }

    private static func rotationAngularDistanceDegrees(
        _ lhs: simd_double3x3,
        _ rhs: simd_double3x3
    ) -> Double {
        guard PoseMath.isFinite(lhs), PoseMath.isFinite(rhs) else { return .infinity }
        if lhs.columns.0 == rhs.columns.0,
           lhs.columns.1 == rhs.columns.1,
           lhs.columns.2 == rhs.columns.2 {
            return 0
        }
        let delta = simd_transpose(lhs) * rhs
        let trace = PoseMath.matrixElement(delta, row: 0, column: 0) +
            PoseMath.matrixElement(delta, row: 1, column: 1) +
            PoseMath.matrixElement(delta, row: 2, column: 2)
        let cosine = min(max((trace - 1.0) / 2.0, -1.0), 1.0)
        return acos(cosine) * 180.0 / Double.pi
    }

    private static func mean(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }
}

final class ScanSessionPreAccumulationGateABReplayRunner {
    private let deterministicRunner: ScanSessionDeterministicReplayRunner

    init(
        readerFactory: @escaping () -> ScanSessionSchemaV1Reader = {
            ScanSessionSchemaV1Reader()
        },
        accumulatorFactory: @escaping () -> MultiFramePoseAccumulator = {
            MultiFramePoseAccumulator()
        }
    ) {
        deterministicRunner = ScanSessionDeterministicReplayRunner(
            readerFactory: readerFactory,
            accumulatorFactory: accumulatorFactory
        )
    }

    func run(
        sessionFileURL: URL,
        options: ScanSessionReplayOptions = .deterministic
    ) throws -> ScanSessionPreAccumulationGateABReplayResult {
        let allReplay = try deterministicRunner.verifyDeterminism(
            sessionFileURL: sessionFileURL,
            options: options,
            observationPolicy: .allPersisted
        )
        let filteredReplay = try deterministicRunner.verifyDeterminism(
            sessionFileURL: sessionFileURL,
            options: options,
            observationPolicy: .preAccumulationGateAcceptedOnly
        )
        guard allReplay.readSummary.metadata == filteredReplay.readSummary.metadata,
              allReplay.readSummary.framesRead == filteredReplay.readSummary.framesRead
        else {
            throw ScanSessionReplayError.replayPassMetadataMismatch
        }

        let metadata = allReplay.readSummary.metadata
        let selection = filteredReplay.readSummary.selectionDiagnostics
        let geometry = ScanSessionReplayPairwiseGeometryComparator.compare(
            allPoses: allReplay.replayAFinalPoses,
            filteredPoses: filteredReplay.replayAFinalPoses
        )
        var caveats = allReplay.summary.provenanceCaveats
        caveats.append(
            "filtered replay is an offline simulation using persisted Pre-Accumulation Gate decisions"
        )
        caveats.append(
            "pairwise relative geometry is authoritative because accumulator outputs may use different anchors"
        )
        let blockingFlag = metadata.featureFlags["preAccumulationGateBlocking"]
        if blockingFlag == nil {
            caveats.append("capture live Pre-Accumulation Gate blocking flag is unavailable")
        }
        let annotationInconsistencyCount = selection.rejectedWithoutReasonCount +
            selection.unrecognizedRejectReasonCount
        let summary = ScanSessionPreAccumulationGateABReplaySummary(
            sessionIdentifier: metadata.sessionIdentifier,
            schemaVersion: metadata.schemaVersion,
            appGitCommitHash: metadata.appGitCommitHash,
            appVersion: metadata.appVersion,
            appBuildIdentifier: metadata.appBuildIdentifier,
            baselineReplayPolicy: ScanSessionReplayObservationPolicy.allPersisted.rawValue,
            filteredReplayPolicy:
                ScanSessionReplayObservationPolicy.preAccumulationGateAcceptedOnly.rawValue,
            replayAlgorithmIdentifier: ScanSessionDeterministicReplayRunner.algorithmIdentifier,
            replayUsesRandomness: false,
            framesReplayed: allReplay.summary.framesReplayed,
            selectionDiagnostics: selection,
            allDeterminism: allReplay.summary.determinism,
            filteredDeterminism: filteredReplay.summary.determinism,
            allFinalMarkerIds: allReplay.summary.finalMarkerIds,
            filteredFinalMarkerIds: filteredReplay.summary.finalMarkerIds,
            allFinalPoses: allReplay.summary.finalPoses,
            filteredFinalPoses: filteredReplay.summary.finalPoses,
            pairwiseRelativeGeometry: geometry,
            integrityResult: annotationInconsistencyCount == 0
                ? "valid"
                : "validWithGateAnnotationInconsistencies",
            provenanceCaveats: caveats,
            livePreAccumulationBlockingEnabledAtCapture: blockingFlag,
            offlineFilteredReplayUsesPersistedDecisions: true
        )
        return ScanSessionPreAccumulationGateABReplayResult(
            summary: summary,
            allReplay: allReplay,
            filteredReplay: filteredReplay
        )
    }
}
