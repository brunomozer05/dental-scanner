import Foundation
import simd

final class MultiFramePoseAccumulator {
    struct Configuration {
        let maxReprojectionError: Double
        let maxSamplesPerMarker: Int
        let maxTranslationOutlierDistanceMm: Double
        let minimumSamplesBeforeOutlierRejection: Int
        let minimumWeightedReprojectionError: Double
        let minimumFrameWeight: Double
        let maximumFrameWeight: Double
        let minimumAngularDiversityRadians: Double

        static let scannerDefault = Configuration(
            maxReprojectionError: 2.0,
            maxSamplesPerMarker: 90,
            maxTranslationOutlierDistanceMm: 6.0,
            minimumSamplesBeforeOutlierRejection: 4,
            minimumWeightedReprojectionError: 0.001,
            minimumFrameWeight: 0.1,
            maximumFrameWeight: 10.0,
            minimumAngularDiversityRadians: Double.pi / 60.0
        )
    }

    private let configuration: Configuration
    private let lock = NSLock()
    private var anchorMarkerId: Int?
    private var samplesByMarkerId: [Int: [PoseResult]] = [:]
    private var maximumMarkerAreaPixelsByMarkerId: [Int: Double] = [:]
    private var acceptedViewpointRotations: [Quaternion] = []

    init(configuration: Configuration = .scannerDefault) {
        self.configuration = configuration
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }

        anchorMarkerId = nil
        samplesByMarkerId.removeAll()
        maximumMarkerAreaPixelsByMarkerId.removeAll()
        acceptedViewpointRotations.removeAll()
    }

    func update(with cameraPoseResults: [PoseResult]) -> [PoseResult] {
        lock.lock()
        defer { lock.unlock() }

        let validCameraPoses = cameraPoseResults
            .filter(isValidCameraPose)
            .sorted { $0.markerId < $1.markerId }

        guard !validCameraPoses.isEmpty else {
            return fusedPoseResults()
        }

        if anchorMarkerId == nil {
            anchorMarkerId = validCameraPoses.first?.markerId
        }

        guard let anchorMarkerId,
              let anchorPose = validCameraPoses.first(where: { $0.markerId == anchorMarkerId })
        else {
            return fusedPoseResults()
        }

        let anchorRotation = anchorPose.rotationMatrix
        let inverseAnchorRotation = simd_transpose(anchorRotation)
        guard let viewpointRotation = Quaternion(rotationMatrix: anchorRotation),
              shouldAcceptFrame(
                viewpointRotation: viewpointRotation,
                validCameraPoses: validCameraPoses
              )
        else {
            return fusedPoseResults()
        }

        appendAcceptedViewpointRotation(viewpointRotation)

        for cameraPose in validCameraPoses {
            guard let anchorRelativePose = Self.pose(
                cameraPose,
                relativeTo: anchorPose,
                inverseAnchorRotation: inverseAnchorRotation
            ) else {
                continue
            }

            append(anchorRelativePose)
        }

        return fusedPoseResults()
    }

    private func isValidCameraPose(_ pose: PoseResult) -> Bool {
        pose.reprojectionError.isFinite &&
            pose.reprojectionError <= configuration.maxReprojectionError &&
            pose.distanceMm.isFinite &&
            pose.markerAreaPixels.isFinite &&
            Self.isFinite(pose.rotationVector) &&
            Self.isFinite(pose.translationVector)
    }

    private func append(_ pose: PoseResult) {
        recordMaximumMarkerArea(for: pose)

        var samples = samplesByMarkerId[pose.markerId, default: []]
        samples.append(pose)

        if samples.count > configuration.maxSamplesPerMarker {
            samples.removeFirst(samples.count - configuration.maxSamplesPerMarker)
        }

        samplesByMarkerId[pose.markerId] = samples
    }

    private func recordMaximumMarkerArea(for pose: PoseResult) {
        guard pose.markerAreaPixels.isFinite, pose.markerAreaPixels > 0 else {
            return
        }

        let currentMaximum = maximumMarkerAreaPixelsByMarkerId[pose.markerId] ?? 0.0
        maximumMarkerAreaPixelsByMarkerId[pose.markerId] = max(currentMaximum, pose.markerAreaPixels)
    }

    private func shouldAcceptFrame(
        viewpointRotation: Quaternion,
        validCameraPoses: [PoseResult]
    ) -> Bool {
        guard !acceptedViewpointRotations.isEmpty else {
            return true
        }

        let hasMarkerWithoutSamples = validCameraPoses.contains { pose in
            samplesByMarkerId[pose.markerId]?.isEmpty ?? true
        }
        if hasMarkerWithoutSamples {
            return true
        }

        let closestAcceptedAngle = acceptedViewpointRotations
            .map { viewpointRotation.angularDistance(to: $0) }
            .min() ?? .infinity

        return closestAcceptedAngle >= configuration.minimumAngularDiversityRadians
    }

    private func appendAcceptedViewpointRotation(_ viewpointRotation: Quaternion) {
        acceptedViewpointRotations.append(viewpointRotation)

        if acceptedViewpointRotations.count > configuration.maxSamplesPerMarker {
            acceptedViewpointRotations.removeFirst(
                acceptedViewpointRotations.count - configuration.maxSamplesPerMarker
            )
        }
    }

    private func fusedPoseResults() -> [PoseResult] {
        samplesByMarkerId.keys.sorted().compactMap { markerId in
            guard let samples = samplesByMarkerId[markerId] else {
                return nil
            }

            return fusedPoseResult(for: markerId, samples: samples)
        }
    }

    private func fusedPoseResult(for markerId: Int, samples: [PoseResult]) -> PoseResult? {
        guard !samples.isEmpty else {
            return nil
        }

        let filteredSamples = samplesAfterOutlierRejection(samples)
        let weightedSamples = filteredSamples.compactMap { weightedPoseSample(from: $0) }
        guard !weightedSamples.isEmpty else {
            return nil
        }

        let totalWeight = weightedSamples.reduce(0.0) { $0 + $1.weight }
        guard totalWeight.isFinite, totalWeight > 0 else {
            return nil
        }

        let translationVector = weightedSamples.reduce(SIMD3<Double>.zero) {
            $0 + $1.pose.translationVector * $1.weight
        } / totalWeight
        let reprojectionError = weightedSamples.reduce(0.0) {
            $0 + $1.pose.reprojectionError * $1.weight
        } / totalWeight
        let markerAreaPixels = weightedSamples.reduce(0.0) {
            $0 + $1.pose.markerAreaPixels * $1.weight
        } / totalWeight
        guard let rotationQuaternion = weightedAverageQuaternion(from: weightedSamples)
        else {
            return nil
        }
        let rotationMatrix = simd_double3x3(rotationQuaternion)
        guard let rotationVector = Self.rotationVector(from: rotationMatrix) else {
            return nil
        }

        guard Self.isFinite(rotationVector),
              Self.isFinite(translationVector),
              reprojectionError.isFinite
        else {
            return nil
        }
        let metadataPose = metadataPose(from: filteredSamples.isEmpty ? samples : filteredSamples)

        return PoseResult(
            markerId: markerId,
            markerProfile: metadataPose.markerProfile,
            poseSource: metadataPose.poseSource,
            rotationVector: rotationVector,
            rotationMatrix: rotationMatrix,
            translationVector: translationVector,
            distanceMm: simd_length(translationVector),
            reprojectionError: reprojectionError,
            markerAreaPixels: markerAreaPixels,
            usedPointCount: metadataPose.usedPointCount,
            detectedTopTagId: metadataPose.detectedTopTagId,
            detectedBottomTagId: metadataPose.detectedBottomTagId
        )
    }

    private func weightedPoseSample(from pose: PoseResult) -> WeightedPoseSample? {
        let reprojectionWeight = 1.0 / max(
            pose.reprojectionError,
            configuration.minimumWeightedReprojectionError
        )
        let rawWeight = reprojectionWeight *
            normalizedMarkerArea(for: pose) *
            pose.poseSource.qualityWeight
        let weight = min(
            max(rawWeight, configuration.minimumFrameWeight),
            configuration.maximumFrameWeight
        )
        guard weight.isFinite, weight > 0 else {
            return nil
        }

        guard let quaternion = PoseMath.quaternion(fromRotationMatrix: pose.rotationMatrix) else {
            return nil
        }

        return WeightedPoseSample(
            pose: pose,
            weight: weight,
            quaternion: quaternion
        )
    }

    private func normalizedMarkerArea(for pose: PoseResult) -> Double {
        guard pose.markerAreaPixels.isFinite, pose.markerAreaPixels > 0 else {
            return 1.0
        }

        guard let maximumMarkerAreaPixels = maximumMarkerAreaPixelsByMarkerId[pose.markerId],
              maximumMarkerAreaPixels.isFinite,
              maximumMarkerAreaPixels > 0
        else {
            return 1.0
        }

        return min(max(pose.markerAreaPixels / maximumMarkerAreaPixels, 0.0), 1.0)
    }

    private func weightedAverageQuaternion(from weightedSamples: [WeightedPoseSample]) -> simd_quatd? {
        var accumulatedRotation: simd_quatd?
        var totalWeight = 0.0

        for sample in weightedSamples {
            let nextTotalWeight = totalWeight + sample.weight
            guard nextTotalWeight.isFinite, nextTotalWeight > 0 else {
                return nil
            }

            if let currentRotation = accumulatedRotation {
                let alpha = sample.weight / nextTotalWeight
                accumulatedRotation = simd_slerp(currentRotation, sample.quaternion, alpha)
            } else {
                accumulatedRotation = sample.quaternion
            }

            totalWeight = nextTotalWeight
        }

        guard let accumulatedRotation, PoseMath.isFinite(accumulatedRotation) else {
            return nil
        }

        return accumulatedRotation
    }

    private func samplesAfterOutlierRejection(_ samples: [PoseResult]) -> [PoseResult] {
        guard samples.count >= configuration.minimumSamplesBeforeOutlierRejection else {
            return samples
        }

        let medianTranslation = SIMD3<Double>(
            median(samples.map { $0.translationVector.x }),
            median(samples.map { $0.translationVector.y }),
            median(samples.map { $0.translationVector.z })
        )
        let filteredSamples = samples.filter {
            simd_distance($0.translationVector, medianTranslation) <= configuration.maxTranslationOutlierDistanceMm
        }

        return filteredSamples
    }

    private func metadataPose(from samples: [PoseResult]) -> PoseResult {
        samples.last(where: { pose in
            if case .dualTag = pose.poseSource {
                return true
            }

            return false
        }) ?? samples.last!
    }

    private func median(_ values: [Double]) -> Double {
        let sortedValues = values.sorted()
        let middleIndex = sortedValues.count / 2

        if sortedValues.count.isMultiple(of: 2) {
            return (sortedValues[middleIndex - 1] + sortedValues[middleIndex]) / 2.0
        }

        return sortedValues[middleIndex]
    }

    private static func pose(
        _ pose: PoseResult,
        relativeTo anchorPose: PoseResult,
        inverseAnchorRotation: simd_double3x3
    ) -> PoseResult? {
        let poseRotation = pose.rotationMatrix
        let relativeRotationMatrix = inverseAnchorRotation * poseRotation
        let relativeTranslation = inverseAnchorRotation * (pose.translationVector - anchorPose.translationVector)

        guard let relativeRotationVector = rotationVector(from: relativeRotationMatrix),
              isFinite(relativeRotationVector),
              isFinite(relativeTranslation)
        else {
            return nil
        }

        return PoseResult(
            markerId: pose.markerId,
            markerProfile: pose.markerProfile,
            poseSource: pose.poseSource,
            rotationVector: relativeRotationVector,
            rotationMatrix: relativeRotationMatrix,
            translationVector: relativeTranslation,
            distanceMm: simd_length(relativeTranslation),
            reprojectionError: pose.reprojectionError,
            markerAreaPixels: pose.markerAreaPixels,
            usedPointCount: pose.usedPointCount,
            detectedTopTagId: pose.detectedTopTagId,
            detectedBottomTagId: pose.detectedBottomTagId
        )
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

    private static func rotationVector(from matrix: simd_double3x3) -> SIMD3<Double>? {
        let trace = matrixElement(matrix, row: 0, column: 0) +
            matrixElement(matrix, row: 1, column: 1) +
            matrixElement(matrix, row: 2, column: 2)
        let cosineTheta = min(max((trace - 1.0) / 2.0, -1.0), 1.0)
        let theta = acos(cosineTheta)

        guard theta.isFinite else {
            return nil
        }

        guard theta > 1e-9 else {
            return .zero
        }

        let sineTheta = sin(theta)
        guard abs(sineTheta) > 1e-9 else {
            return rotationVectorForHalfTurn(from: matrix, theta: theta)
        }

        let axis = SIMD3<Double>(
            matrixElement(matrix, row: 2, column: 1) - matrixElement(matrix, row: 1, column: 2),
            matrixElement(matrix, row: 0, column: 2) - matrixElement(matrix, row: 2, column: 0),
            matrixElement(matrix, row: 1, column: 0) - matrixElement(matrix, row: 0, column: 1)
        ) / (2.0 * sineTheta)
        let vector = axis * theta

        return isFinite(vector) ? vector : nil
    }

    private static func rotationVectorForHalfTurn(
        from matrix: simd_double3x3,
        theta: Double
    ) -> SIMD3<Double>? {
        guard abs(theta - Double.pi) < 1e-5 else {
            return nil
        }

        let xx = max((matrixElement(matrix, row: 0, column: 0) + 1.0) / 2.0, 0.0)
        let yy = max((matrixElement(matrix, row: 1, column: 1) + 1.0) / 2.0, 0.0)
        let zz = max((matrixElement(matrix, row: 2, column: 2) + 1.0) / 2.0, 0.0)
        let xy = (matrixElement(matrix, row: 0, column: 1) + matrixElement(matrix, row: 1, column: 0)) / 4.0
        let xz = (matrixElement(matrix, row: 0, column: 2) + matrixElement(matrix, row: 2, column: 0)) / 4.0
        let yz = (matrixElement(matrix, row: 1, column: 2) + matrixElement(matrix, row: 2, column: 1)) / 4.0

        var axis: SIMD3<Double>
        if xx >= yy && xx >= zz {
            let x = sqrt(xx)
            guard x > 1e-9 else { return nil }
            axis = SIMD3(x, xy / x, xz / x)
        } else if yy >= zz {
            let y = sqrt(yy)
            guard y > 1e-9 else { return nil }
            axis = SIMD3(xy / y, y, yz / y)
        } else {
            let z = sqrt(zz)
            guard z > 1e-9 else { return nil }
            axis = SIMD3(xz / z, yz / z, z)
        }

        let axisLength = simd_length(axis)
        guard axisLength.isFinite, axisLength > 1e-9 else {
            return nil
        }

        axis = axis / axisLength
        let vector = axis * theta

        return isFinite(vector) ? vector : nil
    }

    private struct WeightedPoseSample {
        let pose: PoseResult
        let weight: Double
        let quaternion: simd_quatd
    }

    private struct Quaternion {
        let x: Double
        let y: Double
        let z: Double
        let w: Double

        static let zero = Quaternion(x: 0.0, y: 0.0, z: 0.0, w: 0.0)

        init(x: Double, y: Double, z: Double, w: Double) {
            self.x = x
            self.y = y
            self.z = z
            self.w = w
        }

        init?(rotationMatrix matrix: simd_double3x3) {
            let m00 = MultiFramePoseAccumulator.matrixElement(matrix, row: 0, column: 0)
            let m01 = MultiFramePoseAccumulator.matrixElement(matrix, row: 0, column: 1)
            let m02 = MultiFramePoseAccumulator.matrixElement(matrix, row: 0, column: 2)
            let m10 = MultiFramePoseAccumulator.matrixElement(matrix, row: 1, column: 0)
            let m11 = MultiFramePoseAccumulator.matrixElement(matrix, row: 1, column: 1)
            let m12 = MultiFramePoseAccumulator.matrixElement(matrix, row: 1, column: 2)
            let m20 = MultiFramePoseAccumulator.matrixElement(matrix, row: 2, column: 0)
            let m21 = MultiFramePoseAccumulator.matrixElement(matrix, row: 2, column: 1)
            let m22 = MultiFramePoseAccumulator.matrixElement(matrix, row: 2, column: 2)
            let trace = m00 + m11 + m22
            let quaternion: Quaternion

            if trace > 0.0 {
                let scale = sqrt(max(trace + 1.0, 0.0)) * 2.0
                guard scale.isFinite, scale > 1e-12 else { return nil }
                quaternion = Quaternion(
                    x: (m21 - m12) / scale,
                    y: (m02 - m20) / scale,
                    z: (m10 - m01) / scale,
                    w: 0.25 * scale
                )
            } else if m00 > m11 && m00 > m22 {
                let scale = sqrt(max(1.0 + m00 - m11 - m22, 0.0)) * 2.0
                guard scale.isFinite, scale > 1e-12 else { return nil }
                quaternion = Quaternion(
                    x: 0.25 * scale,
                    y: (m01 + m10) / scale,
                    z: (m02 + m20) / scale,
                    w: (m21 - m12) / scale
                )
            } else if m11 > m22 {
                let scale = sqrt(max(1.0 + m11 - m00 - m22, 0.0)) * 2.0
                guard scale.isFinite, scale > 1e-12 else { return nil }
                quaternion = Quaternion(
                    x: (m01 + m10) / scale,
                    y: 0.25 * scale,
                    z: (m12 + m21) / scale,
                    w: (m02 - m20) / scale
                )
            } else {
                let scale = sqrt(max(1.0 + m22 - m00 - m11, 0.0)) * 2.0
                guard scale.isFinite, scale > 1e-12 else { return nil }
                quaternion = Quaternion(
                    x: (m02 + m20) / scale,
                    y: (m12 + m21) / scale,
                    z: 0.25 * scale,
                    w: (m10 - m01) / scale
                )
            }

            guard let normalizedQuaternion = quaternion.normalized() else {
                return nil
            }

            self = normalizedQuaternion
        }

        var rotationMatrix: simd_double3x3 {
            guard let quaternion = normalized() else {
                return matrix_identity_double3x3
            }

            let xx = quaternion.x * quaternion.x
            let yy = quaternion.y * quaternion.y
            let zz = quaternion.z * quaternion.z
            let xy = quaternion.x * quaternion.y
            let xz = quaternion.x * quaternion.z
            let yz = quaternion.y * quaternion.z
            let wx = quaternion.w * quaternion.x
            let wy = quaternion.w * quaternion.y
            let wz = quaternion.w * quaternion.z

            return MultiFramePoseAccumulator.matrixFromRows(
                SIMD3(1.0 - 2.0 * (yy + zz), 2.0 * (xy - wz), 2.0 * (xz + wy)),
                SIMD3(2.0 * (xy + wz), 1.0 - 2.0 * (xx + zz), 2.0 * (yz - wx)),
                SIMD3(2.0 * (xz - wy), 2.0 * (yz + wx), 1.0 - 2.0 * (xx + yy))
            )
        }

        func normalized() -> Quaternion? {
            let length = sqrt(x * x + y * y + z * z + w * w)
            guard length.isFinite, length > 1e-12 else {
                return nil
            }

            return Quaternion(
                x: x / length,
                y: y / length,
                z: z / length,
                w: w / length
            )
        }

        func dot(_ other: Quaternion) -> Double {
            x * other.x + y * other.y + z * other.z + w * other.w
        }

        func aligned(to reference: Quaternion) -> Quaternion {
            dot(reference) < 0.0 ? scaled(by: -1.0) : self
        }

        func scaled(by scalar: Double) -> Quaternion {
            Quaternion(
                x: x * scalar,
                y: y * scalar,
                z: z * scalar,
                w: w * scalar
            )
        }

        func angularDistance(to other: Quaternion) -> Double {
            guard let lhs = normalized(),
                  let rhs = other.normalized()
            else {
                return .infinity
            }

            let cosineHalfAngle = min(max(abs(lhs.dot(rhs)), 0.0), 1.0)
            return 2.0 * acos(cosineHalfAngle)
        }

        static func + (lhs: Quaternion, rhs: Quaternion) -> Quaternion {
            Quaternion(
                x: lhs.x + rhs.x,
                y: lhs.y + rhs.y,
                z: lhs.z + rhs.z,
                w: lhs.w + rhs.w
            )
        }
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
}
