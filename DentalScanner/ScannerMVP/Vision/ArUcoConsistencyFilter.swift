import CoreGraphics
import Foundation
import simd

final class ArUcoConsistencyFilter {
    struct Configuration {
        let temporalWindowFrameCount: Int
        let minimumTemporalDetections: Int
        let minimumMarkerSideLengthPixels: Double
        let minimumMarkerAreaPixels: Double
        let maximumSideLengthRatio: Double
        let maximumDiagonalLengthRatio: Double
        let minimumCornerAngleRadians: Double
        let maximumCornerAngleRadians: Double
        let poseHistoryFrameCount: Int
        let maximumPoseTranslationJumpMm: Double
        let maximumPoseRotationJumpRadians: Double
        let pairDistanceHistoryCount: Int
        let minimumPairDistanceSamples: Int
        let maximumPairDistanceAbsoluteDeviationMm: Double
        let maximumPairDistanceRelativeDeviation: Double

        static let scannerDefault = Configuration(
            temporalWindowFrameCount: 6,
            minimumTemporalDetections: 2,
            minimumMarkerSideLengthPixels: 8.0,
            minimumMarkerAreaPixels: 80.0,
            maximumSideLengthRatio: 3.0,
            maximumDiagonalLengthRatio: 2.5,
            minimumCornerAngleRadians: 35.0 * Double.pi / 180.0,
            maximumCornerAngleRadians: 145.0 * Double.pi / 180.0,
            poseHistoryFrameCount: 6,
            maximumPoseTranslationJumpMm: 90.0,
            maximumPoseRotationJumpRadians: Double.pi / 3.0,
            pairDistanceHistoryCount: 45,
            minimumPairDistanceSamples: 4,
            maximumPairDistanceAbsoluteDeviationMm: 10.0,
            maximumPairDistanceRelativeDeviation: 0.25
        )
    }

    private struct PoseSample {
        let frameIndex: Int
        let pose: PoseResult
    }

    private struct MarkerPair: Hashable {
        let firstMarkerId: Int
        let secondMarkerId: Int

        init(_ firstMarkerId: Int, _ secondMarkerId: Int) {
            self.firstMarkerId = min(firstMarkerId, secondMarkerId)
            self.secondMarkerId = max(firstMarkerId, secondMarkerId)
        }
    }

    private let configuration: Configuration
    private let lock = NSLock()
    private var frameIndex = 0
    private var markerObservationFrames: [Int: [Int]] = [:]
    private var poseHistoryByMarkerId: [Int: [PoseSample]] = [:]
    private var pairDistanceHistoryByPair: [MarkerPair: [Double]] = [:]

    init(configuration: Configuration = .scannerDefault) {
        self.configuration = configuration
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }

        frameIndex = 0
        markerObservationFrames.removeAll()
        poseHistoryByMarkerId.removeAll()
        pairDistanceHistoryByPair.removeAll()
    }

    func filterDetections(_ detections: [ArUcoDetectionResult]) -> [ArUcoDetectionResult] {
        lock.lock()
        defer { lock.unlock() }

        frameIndex += 1

        let geometricallyValidDetections = bestGeometricallyValidDetections(from: detections)
        recordTemporalObservations(for: geometricallyValidDetections)
        pruneTemporalObservationHistory()
        prunePoseHistory()

        return geometricallyValidDetections.filter {
            temporalObservationCount(for: $0.markerId) >= configuration.minimumTemporalDetections
        }
    }

    func filterPoses(_ poses: [PoseResult]) -> [PoseResult] {
        lock.lock()
        defer { lock.unlock() }

        let stablePoses = poses
            .filter(isFinitePose)
            .filter(isTemporallyStablePose)
            .sorted { $0.markerId < $1.markerId }
        let tagSetValidatedPoses = posesAfterTagSetValidation(stablePoses)

        recordAcceptedPoseHistory(tagSetValidatedPoses)
        recordPairDistanceHistory(tagSetValidatedPoses)
        prunePoseHistory()

        return tagSetValidatedPoses
    }

    private func bestGeometricallyValidDetections(
        from detections: [ArUcoDetectionResult]
    ) -> [ArUcoDetectionResult] {
        var bestDetectionsByMarkerId: [Int: ArUcoDetectionResult] = [:]
        var bestAreasByMarkerId: [Int: Double] = [:]

        for detection in detections {
            guard let metrics = geometryMetrics(for: detection),
                  isPlausibleGeometry(metrics)
            else {
                continue
            }

            let currentBestArea = bestAreasByMarkerId[detection.markerId] ?? -Double.infinity
            if metrics.area > currentBestArea {
                bestAreasByMarkerId[detection.markerId] = metrics.area
                bestDetectionsByMarkerId[detection.markerId] = detection
            }
        }

        return bestDetectionsByMarkerId.keys.sorted().compactMap {
            bestDetectionsByMarkerId[$0]
        }
    }

    private func recordTemporalObservations(for detections: [ArUcoDetectionResult]) {
        for markerId in Set(detections.map(\.markerId)) {
            markerObservationFrames[markerId, default: []].append(frameIndex)
        }
    }

    private func pruneTemporalObservationHistory() {
        let minimumFrameIndex = frameIndex - configuration.temporalWindowFrameCount + 1
        for markerId in Array(markerObservationFrames.keys) {
            markerObservationFrames[markerId]?.removeAll { $0 < minimumFrameIndex }

            if markerObservationFrames[markerId]?.isEmpty == true {
                markerObservationFrames.removeValue(forKey: markerId)
            }
        }
    }

    private func temporalObservationCount(for markerId: Int) -> Int {
        markerObservationFrames[markerId]?.count ?? 0
    }

    private func isTemporallyStablePose(_ pose: PoseResult) -> Bool {
        guard let previousPose = poseHistoryByMarkerId[pose.markerId]?.last?.pose,
              let previousFrameIndex = poseHistoryByMarkerId[pose.markerId]?.last?.frameIndex,
              frameIndex - previousFrameIndex <= configuration.poseHistoryFrameCount
        else {
            return true
        }

        let translationDelta = simd_distance(pose.translationVector, previousPose.translationVector)
        let rotationDelta = Self.rotationAngle(
            between: pose.rotationVector,
            and: previousPose.rotationVector
        )

        return translationDelta <= configuration.maximumPoseTranslationJumpMm &&
            rotationDelta <= configuration.maximumPoseRotationJumpRadians
    }

    private func posesAfterTagSetValidation(_ poses: [PoseResult]) -> [PoseResult] {
        guard poses.count >= 2 else {
            return poses
        }

        var rejectedMarkerIds: Set<Int> = []

        for firstIndex in poses.indices {
            for secondIndex in poses.indices where secondIndex > firstIndex {
                let firstPose = poses[firstIndex]
                let secondPose = poses[secondIndex]
                let pair = MarkerPair(firstPose.markerId, secondPose.markerId)

                guard let expectedDistance = expectedDistance(for: pair) else {
                    continue
                }

                let currentDistance = simd_distance(
                    firstPose.translationVector,
                    secondPose.translationVector
                )
                let maximumAllowedDeviation = max(
                    configuration.maximumPairDistanceAbsoluteDeviationMm,
                    expectedDistance * configuration.maximumPairDistanceRelativeDeviation
                )

                guard abs(currentDistance - expectedDistance) > maximumAllowedDeviation else {
                    continue
                }

                rejectedMarkerIds.insert(markerIdToReject(firstPose, secondPose))
            }
        }

        guard !rejectedMarkerIds.isEmpty else {
            return poses
        }

        return poses.filter { !rejectedMarkerIds.contains($0.markerId) }
    }

    private func markerIdToReject(_ firstPose: PoseResult, _ secondPose: PoseResult) -> Int {
        let firstHasHistory = hasRecentPoseHistory(for: firstPose.markerId)
        let secondHasHistory = hasRecentPoseHistory(for: secondPose.markerId)

        if firstHasHistory != secondHasHistory {
            return firstHasHistory ? secondPose.markerId : firstPose.markerId
        }

        return firstPose.reprojectionError >= secondPose.reprojectionError
            ? firstPose.markerId
            : secondPose.markerId
    }

    private func expectedDistance(for pair: MarkerPair) -> Double? {
        guard let distances = pairDistanceHistoryByPair[pair],
              distances.count >= configuration.minimumPairDistanceSamples
        else {
            return nil
        }

        return median(distances)
    }

    private func hasRecentPoseHistory(for markerId: Int) -> Bool {
        guard let lastFrameIndex = poseHistoryByMarkerId[markerId]?.last?.frameIndex else {
            return false
        }

        return frameIndex - lastFrameIndex <= configuration.poseHistoryFrameCount
    }

    private func recordAcceptedPoseHistory(_ poses: [PoseResult]) {
        for pose in poses {
            var history = poseHistoryByMarkerId[pose.markerId, default: []]
            history.append(PoseSample(frameIndex: frameIndex, pose: pose))

            if history.count > configuration.poseHistoryFrameCount {
                history.removeFirst(history.count - configuration.poseHistoryFrameCount)
            }

            poseHistoryByMarkerId[pose.markerId] = history
        }
    }

    private func prunePoseHistory() {
        let minimumFrameIndex = frameIndex - configuration.poseHistoryFrameCount + 1
        for markerId in Array(poseHistoryByMarkerId.keys) {
            poseHistoryByMarkerId[markerId]?.removeAll { $0.frameIndex < minimumFrameIndex }

            if poseHistoryByMarkerId[markerId]?.isEmpty == true {
                poseHistoryByMarkerId.removeValue(forKey: markerId)
            }
        }
    }

    private func recordPairDistanceHistory(_ poses: [PoseResult]) {
        guard poses.count >= 2 else {
            return
        }

        for firstIndex in poses.indices {
            for secondIndex in poses.indices where secondIndex > firstIndex {
                let firstPose = poses[firstIndex]
                let secondPose = poses[secondIndex]
                let pair = MarkerPair(firstPose.markerId, secondPose.markerId)
                var distances = pairDistanceHistoryByPair[pair, default: []]
                distances.append(
                    simd_distance(firstPose.translationVector, secondPose.translationVector)
                )

                if distances.count > configuration.pairDistanceHistoryCount {
                    distances.removeFirst(distances.count - configuration.pairDistanceHistoryCount)
                }

                pairDistanceHistoryByPair[pair] = distances
            }
        }
    }

    private func geometryMetrics(for detection: ArUcoDetectionResult) -> GeometryMetrics? {
        guard detection.corners.count == 4,
              detection.corners.allSatisfy({ $0.x.isFinite && $0.y.isFinite })
        else {
            return nil
        }

        let corners = detection.corners.map {
            SIMD2<Double>(Double($0.x), Double($0.y))
        }
        let sideLengths = [
            simd_distance(corners[0], corners[1]),
            simd_distance(corners[1], corners[2]),
            simd_distance(corners[2], corners[3]),
            simd_distance(corners[3], corners[0])
        ]
        let diagonalLengths = [
            simd_distance(corners[0], corners[2]),
            simd_distance(corners[1], corners[3])
        ]
        let area = polygonArea(corners)
        let cornerAngles = corners.indices.map { cornerAngle(at: $0, corners: corners) }

        guard sideLengths.allSatisfy({ $0.isFinite }),
              diagonalLengths.allSatisfy({ $0.isFinite }),
              cornerAngles.allSatisfy({ $0.isFinite }),
              area.isFinite
        else {
            return nil
        }

        return GeometryMetrics(
            sideLengths: sideLengths,
            diagonalLengths: diagonalLengths,
            cornerAngles: cornerAngles,
            area: area,
            isConvex: isConvexQuadrilateral(corners)
        )
    }

    private func isPlausibleGeometry(_ metrics: GeometryMetrics) -> Bool {
        guard metrics.isConvex,
              let minimumSideLength = metrics.sideLengths.min(),
              let maximumSideLength = metrics.sideLengths.max(),
              let minimumDiagonalLength = metrics.diagonalLengths.min(),
              let maximumDiagonalLength = metrics.diagonalLengths.max()
        else {
            return false
        }

        guard minimumSideLength >= configuration.minimumMarkerSideLengthPixels,
              metrics.area >= configuration.minimumMarkerAreaPixels,
              minimumSideLength > 0,
              minimumDiagonalLength > 0
        else {
            return false
        }

        let sideLengthRatio = maximumSideLength / minimumSideLength
        let diagonalLengthRatio = maximumDiagonalLength / minimumDiagonalLength
        let areAnglesPlausible = metrics.cornerAngles.allSatisfy {
            $0 >= configuration.minimumCornerAngleRadians &&
                $0 <= configuration.maximumCornerAngleRadians
        }

        return sideLengthRatio <= configuration.maximumSideLengthRatio &&
            diagonalLengthRatio <= configuration.maximumDiagonalLengthRatio &&
            areAnglesPlausible
    }

    private func isFinitePose(_ pose: PoseResult) -> Bool {
        pose.distanceMm.isFinite &&
            pose.reprojectionError.isFinite &&
            Self.isFinite(pose.rotationVector) &&
            Self.isFinite(pose.translationVector)
    }

    private func polygonArea(_ corners: [SIMD2<Double>]) -> Double {
        var signedArea = 0.0
        for index in corners.indices {
            let nextIndex = (index + 1) % corners.count
            signedArea += corners[index].x * corners[nextIndex].y
            signedArea -= corners[nextIndex].x * corners[index].y
        }

        return abs(signedArea) / 2.0
    }

    private func cornerAngle(at index: Int, corners: [SIMD2<Double>]) -> Double {
        let previousCorner = corners[(index + corners.count - 1) % corners.count]
        let currentCorner = corners[index]
        let nextCorner = corners[(index + 1) % corners.count]
        let previousVector = previousCorner - currentCorner
        let nextVector = nextCorner - currentCorner
        let previousLength = simd_length(previousVector)
        let nextLength = simd_length(nextVector)

        guard previousLength > 0, nextLength > 0 else {
            return .nan
        }

        let cosine = min(
            max(simd_dot(previousVector, nextVector) / (previousLength * nextLength), -1.0),
            1.0
        )
        return acos(cosine)
    }

    private func isConvexQuadrilateral(_ corners: [SIMD2<Double>]) -> Bool {
        guard corners.count == 4 else {
            return false
        }

        var nonZeroSigns: [Double] = []

        for index in corners.indices {
            let current = corners[index]
            let next = corners[(index + 1) % corners.count]
            let following = corners[(index + 2) % corners.count]
            let edgeA = next - current
            let edgeB = following - next
            let crossProduct = edgeA.x * edgeB.y - edgeA.y * edgeB.x

            if abs(crossProduct) > 1e-6 {
                nonZeroSigns.append(crossProduct.sign == .minus ? -1.0 : 1.0)
            }
        }

        guard let firstSign = nonZeroSigns.first else {
            return false
        }

        return nonZeroSigns.allSatisfy { $0 == firstSign }
    }

    private func median(_ values: [Double]) -> Double {
        let sortedValues = values.sorted()
        let middleIndex = sortedValues.count / 2

        if sortedValues.count.isMultiple(of: 2) {
            return (sortedValues[middleIndex - 1] + sortedValues[middleIndex]) / 2.0
        }

        return sortedValues[middleIndex]
    }

    private static func rotationAngle(
        between firstRotationVector: SIMD3<Double>,
        and secondRotationVector: SIMD3<Double>
    ) -> Double {
        let firstRotation = rotationMatrix(fromRodrigues: firstRotationVector)
        let secondRotation = rotationMatrix(fromRodrigues: secondRotationVector)
        let relativeRotation = simd_transpose(firstRotation) * secondRotation
        let trace = matrixElement(relativeRotation, row: 0, column: 0) +
            matrixElement(relativeRotation, row: 1, column: 1) +
            matrixElement(relativeRotation, row: 2, column: 2)
        let cosineTheta = min(max((trace - 1.0) / 2.0, -1.0), 1.0)
        return acos(cosineTheta)
    }

    private static func rotationMatrix(fromRodrigues vector: SIMD3<Double>) -> simd_double3x3 {
        let theta = simd_length(vector)
        guard theta.isFinite, theta > 1e-9 else {
            return matrix_identity_double3x3
        }

        let axis = vector / theta
        let cosine = cos(theta)
        let sine = sin(theta)
        let oneMinusCosine = 1.0 - cosine

        return matrixFromRows(
            SIMD3(
                cosine + axis.x * axis.x * oneMinusCosine,
                axis.x * axis.y * oneMinusCosine - axis.z * sine,
                axis.x * axis.z * oneMinusCosine + axis.y * sine
            ),
            SIMD3(
                axis.y * axis.x * oneMinusCosine + axis.z * sine,
                cosine + axis.y * axis.y * oneMinusCosine,
                axis.y * axis.z * oneMinusCosine - axis.x * sine
            ),
            SIMD3(
                axis.z * axis.x * oneMinusCosine - axis.y * sine,
                axis.z * axis.y * oneMinusCosine + axis.x * sine,
                cosine + axis.z * axis.z * oneMinusCosine
            )
        )
    }

    private static func matrixFromRows(
        _ row0: SIMD3<Double>,
        _ row1: SIMD3<Double>,
        _ row2: SIMD3<Double>
    ) -> simd_double3x3 {
        simd_double3x3(columns: (
            SIMD3(row0.x, row1.x, row2.x),
            SIMD3(row0.y, row1.y, row2.y),
            SIMD3(row0.z, row1.z, row2.z)
        ))
    }

    private static func matrixElement(
        _ matrix: simd_double3x3,
        row: Int,
        column: Int
    ) -> Double {
        switch (row, column) {
        case (0, 0): return matrix.columns.0.x
        case (0, 1): return matrix.columns.1.x
        case (0, 2): return matrix.columns.2.x
        case (1, 0): return matrix.columns.0.y
        case (1, 1): return matrix.columns.1.y
        case (1, 2): return matrix.columns.2.y
        case (2, 0): return matrix.columns.0.z
        case (2, 1): return matrix.columns.1.z
        case (2, 2): return matrix.columns.2.z
        default: return .nan
        }
    }

    private static func isFinite(_ vector: SIMD3<Double>) -> Bool {
        vector.x.isFinite && vector.y.isFinite && vector.z.isFinite
    }

    private struct GeometryMetrics {
        let sideLengths: [Double]
        let diagonalLengths: [Double]
        let cornerAngles: [Double]
        let area: Double
        let isConvex: Bool
    }
}
