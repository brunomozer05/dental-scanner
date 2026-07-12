import Foundation

struct ObservationPoint2D: Codable, Equatable, Sendable {
    let x: Double
    let y: Double
}

struct ObservationPoint3D: Codable, Equatable, Sendable {
    let x: Double
    let y: Double
    let z: Double
}

struct MarkerFrameObservation: Codable, Equatable, Sendable {
    let markerId: Int
    let markerSource: String
    let markerProfileId: String

    let imageCorners: [ObservationPoint2D]
    let objectPoints: [ObservationPoint3D]

    let rotationVector: ObservationPoint3D
    let translationVector: ObservationPoint3D
    let reprojectionError: Double?
    let distanceMm: Double?

    let frameMaskState: String?
    let insideFrameMask: Bool?
    let frameMaskViolation: String?

    let focusQualityState: String?
    let focusVariance: Double?

    let motionQualityState: String?
    let motionMagnitude: Double?

    let poseFinite: Bool
    let intrinsicsFinite: Bool
    let observationValid: Bool

    let preAccumulationGateEvaluated: Bool?
    let preAccumulationGateWouldAccept: Bool?
    let preAccumulationGateRejectReason: String?
}

struct FrameObservation: Codable, Equatable, Sendable {
    var frameIndex: Int
    let timestampSeconds: Double?

    let frameWidth: Int
    let frameHeight: Int

    let intrinsicsAvailable: Bool
    let intrinsicFx: Double?
    let intrinsicFy: Double?
    let intrinsicCx: Double?
    let intrinsicCy: Double?

    let cameraProfileId: String
    let cameraProfileName: String

    let markerObservations: [MarkerFrameObservation]
}

struct FrameObservationDiagnosticsSnapshot: Equatable, Sendable {
    let frameObservationModelEnabled: Bool
    let frameObservationCount: Int
    let frameObservationDroppedCount: Int
    let frameObservationBufferLimit: Int
    let frameObservationOldestTimestamp: Double?
    let frameObservationNewestTimestamp: Double?
    let framesWithAnyMarkerObservationCount: Int
    let framesWithExpectedMarkersObservationCount: Int
    let perMarkerFrameObservationCount: [Int: Int]
    let frameObservationIncompleteExpectedPoseSetCount: Int
    let frameObservationPoseMappingMismatchCount: Int
    let frameObservationPointCountMismatchCount: Int
    let frameObservationMissingIntrinsicsCount: Int
    let frameObservationNonFinitePoseCount: Int
}

final class FrameObservationRecorder {
    static let defaultBufferLimit = 600

    private let lock = NSLock()
    private let bufferLimit: Int

    private var observations: [FrameObservation] = []
    private var firstSourceFrameIndex: Int?
    private var lastFrameIndex: Int?
    private var droppedCount = 0
    private var framesWithAnyMarkerCount = 0
    private var framesWithExpectedMarkersCount = 0
    private var perMarkerCount: [Int: Int] = [:]
    private var incompleteExpectedPoseSetCount = 0
    private var poseMappingMismatchCount = 0
    private var pointCountMismatchCount = 0
    private var missingIntrinsicsCount = 0
    private var nonFinitePoseCount = 0

    init(bufferLimit: Int = FrameObservationRecorder.defaultBufferLimit) {
        self.bufferLimit = max(bufferLimit, 1)
    }

    func append(
        _ sourceObservation: FrameObservation,
        sourceFrameIndex: Int,
        expectedMarkerIds: [Int],
        poseInputMarkerIds: [Int]
    ) {
        lock.lock()
        defer { lock.unlock() }

        if firstSourceFrameIndex == nil {
            firstSourceFrameIndex = sourceFrameIndex
        }

        let sourceBase = firstSourceFrameIndex ?? sourceFrameIndex
        let sourceRelativeIndex = max(sourceFrameIndex - sourceBase, 0)
        let frameIndex = max(sourceRelativeIndex, (lastFrameIndex ?? -1) + 1)
        lastFrameIndex = frameIndex

        var observation = sourceObservation
        observation.frameIndex = frameIndex

        if observations.count == bufferLimit {
            observations.removeFirst()
            droppedCount += 1
        }
        observations.append(observation)

        let observedMarkerIds = Set(observation.markerObservations.map(\.markerId))
        let expectedMarkerIdSet = Set(expectedMarkerIds)

        if !observation.markerObservations.isEmpty {
            framesWithAnyMarkerCount += 1
        }
        if !expectedMarkerIdSet.isEmpty,
           expectedMarkerIdSet.isSubset(of: observedMarkerIds) {
            framesWithExpectedMarkersCount += 1
        }
        // Completeness: this frame's retained pose IDs versus the full configured expected set.
        if observedMarkerIds != expectedMarkerIdSet {
            incompleteExpectedPoseSetCount += 1
        }
        // Structural mapping: exact identity, multiplicity, and order of accumulator pose inputs.
        if poseInputMarkerIds != observation.markerObservations.map(\.markerId) {
            poseMappingMismatchCount += 1
        }
        if !observation.intrinsicsAvailable {
            missingIntrinsicsCount += 1
        }

        for markerObservation in observation.markerObservations {
            perMarkerCount[markerObservation.markerId, default: 0] += 1
            if markerObservation.imageCorners.count != markerObservation.objectPoints.count {
                pointCountMismatchCount += 1
            }
            if !markerObservation.poseFinite {
                nonFinitePoseCount += 1
            }
        }
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }

        observations.removeAll(keepingCapacity: true)
        firstSourceFrameIndex = nil
        lastFrameIndex = nil
        droppedCount = 0
        framesWithAnyMarkerCount = 0
        framesWithExpectedMarkersCount = 0
        perMarkerCount.removeAll(keepingCapacity: true)
        incompleteExpectedPoseSetCount = 0
        poseMappingMismatchCount = 0
        pointCountMismatchCount = 0
        missingIntrinsicsCount = 0
        nonFinitePoseCount = 0
    }

    func observationsSnapshot() -> [FrameObservation] {
        lock.lock()
        defer { lock.unlock() }
        return observations
    }

    func diagnosticsSnapshot() -> FrameObservationDiagnosticsSnapshot {
        lock.lock()
        defer { lock.unlock() }

        return FrameObservationDiagnosticsSnapshot(
            frameObservationModelEnabled: true,
            frameObservationCount: observations.count,
            frameObservationDroppedCount: droppedCount,
            frameObservationBufferLimit: bufferLimit,
            frameObservationOldestTimestamp: observations.first?.timestampSeconds,
            frameObservationNewestTimestamp: observations.last?.timestampSeconds,
            framesWithAnyMarkerObservationCount: framesWithAnyMarkerCount,
            framesWithExpectedMarkersObservationCount: framesWithExpectedMarkersCount,
            perMarkerFrameObservationCount: perMarkerCount,
            frameObservationIncompleteExpectedPoseSetCount: incompleteExpectedPoseSetCount,
            frameObservationPoseMappingMismatchCount: poseMappingMismatchCount,
            frameObservationPointCountMismatchCount: pointCountMismatchCount,
            frameObservationMissingIntrinsicsCount: missingIntrinsicsCount,
            frameObservationNonFinitePoseCount: nonFinitePoseCount
        )
    }
}
