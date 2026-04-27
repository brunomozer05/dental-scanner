import Foundation
import simd

final class MultiFramePoseAccumulator {
    struct Configuration {
        let maxReprojectionError: Double
        let maxSamplesPerMarker: Int
        let maxTranslationOutlierDistanceMm: Double
        let minimumSamplesBeforeOutlierRejection: Int

        static let scannerDefault = Configuration(
            maxReprojectionError: 2.0,
            maxSamplesPerMarker: 90,
            maxTranslationOutlierDistanceMm: 6.0,
            minimumSamplesBeforeOutlierRejection: 4
        )
    }

    private let configuration: Configuration
    private let lock = NSLock()
    private var anchorMarkerId: Int?
    private var samplesByMarkerId: [Int: [PoseResult]] = [:]

    init(configuration: Configuration = .scannerDefault) {
        self.configuration = configuration
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }

        anchorMarkerId = nil
        samplesByMarkerId.removeAll()
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

        let anchorRotation = Self.rotationMatrix(fromRodrigues: anchorPose.rotationVector)
        let inverseAnchorRotation = simd_transpose(anchorRotation)

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
            Self.isFinite(pose.rotationVector) &&
            Self.isFinite(pose.translationVector)
    }

    private func append(_ pose: PoseResult) {
        var samples = samplesByMarkerId[pose.markerId, default: []]
        samples.append(pose)

        if samples.count > configuration.maxSamplesPerMarker {
            samples.removeFirst(samples.count - configuration.maxSamplesPerMarker)
        }

        samplesByMarkerId[pose.markerId] = samples
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
        guard !filteredSamples.isEmpty else {
            return nil
        }

        let sampleCount = Double(filteredSamples.count)
        let rotationVector = filteredSamples.reduce(SIMD3<Double>.zero) {
            $0 + $1.rotationVector
        } / sampleCount
        let translationVector = filteredSamples.reduce(SIMD3<Double>.zero) {
            $0 + $1.translationVector
        } / sampleCount
        let reprojectionError = filteredSamples.reduce(0.0) {
            $0 + $1.reprojectionError
        } / sampleCount

        guard Self.isFinite(rotationVector),
              Self.isFinite(translationVector),
              reprojectionError.isFinite
        else {
            return nil
        }

        return PoseResult(
            markerId: markerId,
            rotationVector: rotationVector,
            translationVector: translationVector,
            distanceMm: simd_length(translationVector),
            reprojectionError: reprojectionError
        )
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

        return filteredSamples.isEmpty ? samples : filteredSamples
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
        let poseRotation = rotationMatrix(fromRodrigues: pose.rotationVector)
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
            rotationVector: relativeRotationVector,
            translationVector: relativeTranslation,
            distanceMm: simd_length(relativeTranslation),
            reprojectionError: pose.reprojectionError
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
