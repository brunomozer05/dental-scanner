import Foundation

enum PreAccumulationObservationRejectReason: String, Codable, CaseIterable, Sendable {
    case unexpectedMarker
    case missingIntrinsics
    case invalidIntrinsics
    case notFinitePose
    case invalidPose
    case frameMask
    case tooClose
    case tooFar
    case focusRisk
    case highReprojection
    case highMotion
    case unknown
}

struct PreAccumulationObservationIdentity: Hashable, Codable, Sendable {
    let frameIndex: Int
    let markerId: Int
}

struct PreAccumulationObservationGateInput: Equatable, Sendable {
    let identity: PreAccumulationObservationIdentity
    let timestampSeconds: Double?
    let expectedMarker: Bool

    let intrinsicsAvailable: Bool
    let intrinsicsFinite: Bool

    let rotationVector: ObservationPoint3D
    let translationVector: ObservationPoint3D
    let poseFinite: Bool
    let poseValid: Bool

    let distanceMm: Double?
    let insideFrameMask: Bool?
    let frameMaskViolation: String?

    let focusQualityState: String?
    let tooCloseFocusRiskDistanceMm: Double?
    let minimumDistanceMm: Double?
    let maximumDistanceMm: Double?

    let reprojectionError: Double?
    let maximumReprojectionError: Double?

    let motionEvaluationAvailable: Bool
    let motionQualityState: String?
    let motionMagnitude: Double?
}

struct PreAccumulationObservationGateDecision: Codable, Equatable, Sendable {
    let identity: PreAccumulationObservationIdentity
    let timestampSeconds: Double?
    let wouldAccept: Bool
    let primaryRejectReason: PreAccumulationObservationRejectReason?
    let reprojectionEvaluationUnavailable: Bool
    let motionEvaluationAvailable: Bool
}

struct PreAccumulationExperimentalGateEvaluation: Equatable, Sendable {
    let identity: PreAccumulationObservationIdentity
    let wouldAccept: Bool
}

struct PreAccumulationMarkerGateDiagnostics: Equatable, Sendable {
    let markerId: Int
    let rawCount: Int
    let wouldAcceptCount: Int
    let wouldRejectCount: Int
    let accumulatorInsertedCount: Int
    let wouldRejectByFrameMaskCount: Int
    let wouldRejectByTooCloseCount: Int
    let wouldRejectByTooFarCount: Int
    let wouldRejectByFocusRiskCount: Int
    let wouldRejectByHighReprojectionCount: Int
    let wouldRejectByHighMotionCount: Int
}

struct PreAccumulationMarkerGateReportSummary: Codable, Equatable, Sendable {
    let markerId: Int
    let markerPreAccumulationRawCount: Int
    let markerPreAccumulationWouldAcceptCount: Int
    let markerPreAccumulationWouldRejectCount: Int
    let markerPreAccumulationAccumulatorInsertedCount: Int
    let markerPreAccumulationWouldRejectByFrameMaskCount: Int
    let markerPreAccumulationWouldRejectByTooCloseCount: Int
    let markerPreAccumulationWouldRejectByTooFarCount: Int
    let markerPreAccumulationWouldRejectByFocusRiskCount: Int
    let markerPreAccumulationWouldRejectByHighReprojectionCount: Int
    let markerPreAccumulationWouldRejectByHighMotionCount: Int

    init(_ diagnostics: PreAccumulationMarkerGateDiagnostics) {
        markerId = diagnostics.markerId
        markerPreAccumulationRawCount = diagnostics.rawCount
        markerPreAccumulationWouldAcceptCount = diagnostics.wouldAcceptCount
        markerPreAccumulationWouldRejectCount = diagnostics.wouldRejectCount
        markerPreAccumulationAccumulatorInsertedCount = diagnostics.accumulatorInsertedCount
        markerPreAccumulationWouldRejectByFrameMaskCount =
            diagnostics.wouldRejectByFrameMaskCount
        markerPreAccumulationWouldRejectByTooCloseCount = diagnostics.wouldRejectByTooCloseCount
        markerPreAccumulationWouldRejectByTooFarCount = diagnostics.wouldRejectByTooFarCount
        markerPreAccumulationWouldRejectByFocusRiskCount = diagnostics.wouldRejectByFocusRiskCount
        markerPreAccumulationWouldRejectByHighReprojectionCount =
            diagnostics.wouldRejectByHighReprojectionCount
        markerPreAccumulationWouldRejectByHighMotionCount = diagnostics.wouldRejectByHighMotionCount
    }
}

struct PreAccumulationObservationGateDiagnosticsSnapshot: Equatable, Sendable {
    let diagnosticsEnabled: Bool
    let blockingEnabled: Bool
    let rawObservationCount: Int
    let wouldAcceptCount: Int
    let wouldRejectCount: Int
    let accumulatorInsertedCount: Int
    let wouldRejectByUnexpectedMarkerCount: Int
    let wouldRejectByMissingIntrinsicsCount: Int
    let wouldRejectByInvalidIntrinsicsCount: Int
    let wouldRejectByNotFinitePoseCount: Int
    let wouldRejectByInvalidPoseCount: Int
    let wouldRejectByFrameMaskCount: Int
    let wouldRejectByTooCloseCount: Int
    let wouldRejectByTooFarCount: Int
    let wouldRejectByFocusRiskCount: Int
    let wouldRejectByHighReprojectionCount: Int
    let wouldRejectByHighMotionCount: Int
    let wouldRejectByUnknownCount: Int
    let wouldAcceptRatio: Double?
    let wouldRejectRatio: Double?
    let topRejectReason: String?
    let reprojectionEvaluationUnavailableCount: Int
    let motionEvaluationUnavailableCount: Int
    let experimentalComparisonAvailable: Bool
    let experimentalAgreementCount: Int
    let experimentalDisagreementCount: Int
    let preGateAcceptedExperimentalAcceptedCount: Int
    let preGateAcceptedExperimentalRejectedCount: Int
    let preGateRejectedExperimentalAcceptedCount: Int
    let preGateRejectedExperimentalRejectedCount: Int
    let markerDiagnosticsByMarkerId: [Int: PreAccumulationMarkerGateDiagnostics]
}

struct PreAccumulationObservationGate {
    func evaluate(_ input: PreAccumulationObservationGateInput) -> PreAccumulationObservationGateDecision {
        let reason: PreAccumulationObservationRejectReason?

        if !input.expectedMarker {
            reason = .unexpectedMarker
        } else if !input.intrinsicsAvailable {
            reason = .missingIntrinsics
        } else if !input.intrinsicsFinite {
            reason = .invalidIntrinsics
        } else if !input.poseFinite {
            reason = .notFinitePose
        } else if !input.poseValid {
            reason = .invalidPose
        } else if input.insideFrameMask == nil {
            reason = .unknown
        } else if input.insideFrameMask != true || input.frameMaskViolation != nil {
            reason = .frameMask
        } else if Self.isFocusRisk(input.focusQualityState) {
            reason = .focusRisk
        } else if let threshold = input.tooCloseFocusRiskDistanceMm,
                  let distance = input.distanceMm,
                  distance < threshold {
            reason = .focusRisk
        } else if let minimumDistance = input.minimumDistanceMm,
                  let distance = input.distanceMm,
                  distance < minimumDistance {
            reason = .tooClose
        } else if let maximumDistance = input.maximumDistanceMm,
                  let distance = input.distanceMm,
                  distance > maximumDistance {
            reason = .tooFar
        } else if let maximumReprojectionError = input.maximumReprojectionError,
                  let reprojectionError = input.reprojectionError,
                  reprojectionError > maximumReprojectionError {
            reason = .highReprojection
        } else if input.motionEvaluationAvailable,
                  input.motionQualityState == "unstable" {
            reason = .highMotion
        } else {
            reason = nil
        }

        return PreAccumulationObservationGateDecision(
            identity: input.identity,
            timestampSeconds: input.timestampSeconds,
            wouldAccept: reason == nil,
            primaryRejectReason: reason,
            reprojectionEvaluationUnavailable:
                input.maximumReprojectionError == nil || input.reprojectionError == nil,
            motionEvaluationAvailable: input.motionEvaluationAvailable
        )
    }

    private static func isFocusRisk(_ state: String?) -> Bool {
        state == "adjusting" || state == "settling" || state == "sharpness_risk" || state == "unstable"
    }
}

final class PreAccumulationObservationGateRecorder {
    private struct MutableMarkerDiagnostics {
        var rawCount = 0
        var wouldAcceptCount = 0
        var wouldRejectCount = 0
        var accumulatorInsertedCount = 0
        var wouldRejectByFrameMaskCount = 0
        var wouldRejectByTooCloseCount = 0
        var wouldRejectByTooFarCount = 0
        var wouldRejectByFocusRiskCount = 0
        var wouldRejectByHighReprojectionCount = 0
        var wouldRejectByHighMotionCount = 0
    }

    private let lock = NSLock()
    private let diagnosticsEnabled: Bool
    private let blockingEnabled: Bool
    private var rawObservationCount = 0
    private var wouldAcceptCount = 0
    private var wouldRejectCount = 0
    private var accumulatorInsertedCount = 0
    private var rejectionCounts: [PreAccumulationObservationRejectReason: Int] = [:]
    private var reprojectionEvaluationUnavailableCount = 0
    private var motionEvaluationUnavailableCount = 0
    private var markerDiagnosticsByMarkerId: [Int: MutableMarkerDiagnostics] = [:]
    private var experimentalAgreementCount = 0
    private var experimentalDisagreementCount = 0
    private var preGateAcceptedExperimentalAcceptedCount = 0
    private var preGateAcceptedExperimentalRejectedCount = 0
    private var preGateRejectedExperimentalAcceptedCount = 0
    private var preGateRejectedExperimentalRejectedCount = 0

    init(diagnosticsEnabled: Bool, blockingEnabled: Bool) {
        self.diagnosticsEnabled = diagnosticsEnabled
        self.blockingEnabled = blockingEnabled
    }

    func record(decisions: [PreAccumulationObservationGateDecision]) {
        guard diagnosticsEnabled else { return }
        lock.lock()
        defer { lock.unlock() }

        for decision in decisions {
            rawObservationCount += 1
            var marker = markerDiagnosticsByMarkerId[decision.identity.markerId] ?? MutableMarkerDiagnostics()
            marker.rawCount += 1

            if decision.wouldAccept {
                wouldAcceptCount += 1
                marker.wouldAcceptCount += 1
            } else {
                wouldRejectCount += 1
                marker.wouldRejectCount += 1
                if let reason = decision.primaryRejectReason {
                    rejectionCounts[reason, default: 0] += 1
                    incrementMarkerReason(reason, marker: &marker)
                } else {
                    rejectionCounts[.unknown, default: 0] += 1
                }
            }

            if decision.reprojectionEvaluationUnavailable {
                reprojectionEvaluationUnavailableCount += 1
            }
            if !decision.motionEvaluationAvailable {
                motionEvaluationUnavailableCount += 1
            }
            markerDiagnosticsByMarkerId[decision.identity.markerId] = marker
        }
    }

    func recordAccumulatorInputs(markerIds: [Int]) {
        guard diagnosticsEnabled else { return }
        lock.lock()
        defer { lock.unlock() }

        accumulatorInsertedCount += markerIds.count
        for markerId in markerIds {
            var marker = markerDiagnosticsByMarkerId[markerId] ?? MutableMarkerDiagnostics()
            marker.accumulatorInsertedCount += 1
            markerDiagnosticsByMarkerId[markerId] = marker
        }
    }

    func recordExperimentalComparison(
        preGateDecisions: [PreAccumulationObservationGateDecision],
        experimentalEvaluations: [PreAccumulationExperimentalGateEvaluation]
    ) {
        guard diagnosticsEnabled else { return }

        let preGateByIdentity = Dictionary(grouping: preGateDecisions, by: \.identity)
        let experimentalByIdentity = Dictionary(grouping: experimentalEvaluations, by: \.identity)
        let comparableIdentities = Set(preGateByIdentity.keys)
            .intersection(Set(experimentalByIdentity.keys))

        lock.lock()
        defer { lock.unlock() }

        for identity in comparableIdentities {
            guard let preGateMatches = preGateByIdentity[identity],
                  preGateMatches.count == 1,
                  let experimentalMatches = experimentalByIdentity[identity],
                  experimentalMatches.count == 1,
                  let preGate = preGateMatches.first,
                  let experimental = experimentalMatches.first
            else {
                continue
            }

            if preGate.wouldAccept == experimental.wouldAccept {
                experimentalAgreementCount += 1
            } else {
                experimentalDisagreementCount += 1
            }

            switch (preGate.wouldAccept, experimental.wouldAccept) {
            case (true, true):
                preGateAcceptedExperimentalAcceptedCount += 1
            case (true, false):
                preGateAcceptedExperimentalRejectedCount += 1
            case (false, true):
                preGateRejectedExperimentalAcceptedCount += 1
            case (false, false):
                preGateRejectedExperimentalRejectedCount += 1
            }
        }
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        rawObservationCount = 0
        wouldAcceptCount = 0
        wouldRejectCount = 0
        accumulatorInsertedCount = 0
        rejectionCounts.removeAll(keepingCapacity: true)
        reprojectionEvaluationUnavailableCount = 0
        motionEvaluationUnavailableCount = 0
        markerDiagnosticsByMarkerId.removeAll(keepingCapacity: true)
        experimentalAgreementCount = 0
        experimentalDisagreementCount = 0
        preGateAcceptedExperimentalAcceptedCount = 0
        preGateAcceptedExperimentalRejectedCount = 0
        preGateRejectedExperimentalAcceptedCount = 0
        preGateRejectedExperimentalRejectedCount = 0
    }

    func diagnosticsSnapshot() -> PreAccumulationObservationGateDiagnosticsSnapshot {
        lock.lock()
        defer { lock.unlock() }

        let comparedCount = experimentalAgreementCount + experimentalDisagreementCount
        var markerSnapshots = Dictionary(uniqueKeysWithValues: markerDiagnosticsByMarkerId.map { markerId, marker in
            (markerId, PreAccumulationMarkerGateDiagnostics(
                markerId: markerId,
                rawCount: marker.rawCount,
                wouldAcceptCount: marker.wouldAcceptCount,
                wouldRejectCount: marker.wouldRejectCount,
                accumulatorInsertedCount: marker.accumulatorInsertedCount,
                wouldRejectByFrameMaskCount: marker.wouldRejectByFrameMaskCount,
                wouldRejectByTooCloseCount: marker.wouldRejectByTooCloseCount,
                wouldRejectByTooFarCount: marker.wouldRejectByTooFarCount,
                wouldRejectByFocusRiskCount: marker.wouldRejectByFocusRiskCount,
                wouldRejectByHighReprojectionCount: marker.wouldRejectByHighReprojectionCount,
                wouldRejectByHighMotionCount: marker.wouldRejectByHighMotionCount
            ))
        })
        for markerId in 0...3 where markerSnapshots[markerId] == nil {
            markerSnapshots[markerId] = PreAccumulationMarkerGateDiagnostics(
                markerId: markerId,
                rawCount: 0,
                wouldAcceptCount: 0,
                wouldRejectCount: 0,
                accumulatorInsertedCount: 0,
                wouldRejectByFrameMaskCount: 0,
                wouldRejectByTooCloseCount: 0,
                wouldRejectByTooFarCount: 0,
                wouldRejectByFocusRiskCount: 0,
                wouldRejectByHighReprojectionCount: 0,
                wouldRejectByHighMotionCount: 0
            )
        }

        return PreAccumulationObservationGateDiagnosticsSnapshot(
            diagnosticsEnabled: diagnosticsEnabled,
            blockingEnabled: blockingEnabled,
            rawObservationCount: rawObservationCount,
            wouldAcceptCount: wouldAcceptCount,
            wouldRejectCount: wouldRejectCount,
            accumulatorInsertedCount: accumulatorInsertedCount,
            wouldRejectByUnexpectedMarkerCount: rejectionCounts[.unexpectedMarker, default: 0],
            wouldRejectByMissingIntrinsicsCount: rejectionCounts[.missingIntrinsics, default: 0],
            wouldRejectByInvalidIntrinsicsCount: rejectionCounts[.invalidIntrinsics, default: 0],
            wouldRejectByNotFinitePoseCount: rejectionCounts[.notFinitePose, default: 0],
            wouldRejectByInvalidPoseCount: rejectionCounts[.invalidPose, default: 0],
            wouldRejectByFrameMaskCount: rejectionCounts[.frameMask, default: 0],
            wouldRejectByTooCloseCount: rejectionCounts[.tooClose, default: 0],
            wouldRejectByTooFarCount: rejectionCounts[.tooFar, default: 0],
            wouldRejectByFocusRiskCount: rejectionCounts[.focusRisk, default: 0],
            wouldRejectByHighReprojectionCount: rejectionCounts[.highReprojection, default: 0],
            wouldRejectByHighMotionCount: rejectionCounts[.highMotion, default: 0],
            wouldRejectByUnknownCount: rejectionCounts[.unknown, default: 0],
            wouldAcceptRatio: Self.ratio(wouldAcceptCount, total: rawObservationCount),
            wouldRejectRatio: Self.ratio(wouldRejectCount, total: rawObservationCount),
            topRejectReason: topRejectReason(),
            reprojectionEvaluationUnavailableCount: reprojectionEvaluationUnavailableCount,
            motionEvaluationUnavailableCount: motionEvaluationUnavailableCount,
            experimentalComparisonAvailable: comparedCount > 0,
            experimentalAgreementCount: experimentalAgreementCount,
            experimentalDisagreementCount: experimentalDisagreementCount,
            preGateAcceptedExperimentalAcceptedCount: preGateAcceptedExperimentalAcceptedCount,
            preGateAcceptedExperimentalRejectedCount: preGateAcceptedExperimentalRejectedCount,
            preGateRejectedExperimentalAcceptedCount: preGateRejectedExperimentalAcceptedCount,
            preGateRejectedExperimentalRejectedCount: preGateRejectedExperimentalRejectedCount,
            markerDiagnosticsByMarkerId: markerSnapshots
        )
    }

    private func incrementMarkerReason(
        _ reason: PreAccumulationObservationRejectReason,
        marker: inout MutableMarkerDiagnostics
    ) {
        switch reason {
        case .frameMask:
            marker.wouldRejectByFrameMaskCount += 1
        case .tooClose:
            marker.wouldRejectByTooCloseCount += 1
        case .tooFar:
            marker.wouldRejectByTooFarCount += 1
        case .focusRisk:
            marker.wouldRejectByFocusRiskCount += 1
        case .highReprojection:
            marker.wouldRejectByHighReprojectionCount += 1
        case .highMotion:
            marker.wouldRejectByHighMotionCount += 1
        case .unexpectedMarker, .missingIntrinsics, .invalidIntrinsics, .notFinitePose,
             .invalidPose, .unknown:
            break
        }
    }

    private func topRejectReason() -> String? {
        rejectionCounts
            .filter { $0.value > 0 }
            .sorted { lhs, rhs in
                lhs.value == rhs.value
                    ? lhs.key.rawValue < rhs.key.rawValue
                    : lhs.value > rhs.value
            }
            .first?
            .key
            .rawValue
    }

    private static func ratio(_ value: Int, total: Int) -> Double? {
        guard total > 0 else { return nil }
        return Double(value) / Double(total)
    }
}
