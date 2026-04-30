import Foundation
import simd

struct PoseResult: Equatable {
    let markerId: Int
    let rotationVector: SIMD3<Double>
    let rotationMatrix: simd_double3x3
    let translationVector: SIMD3<Double>
    let distanceMm: Double
    let reprojectionError: Double

    init(
        markerId: Int,
        rotationVector: SIMD3<Double>,
        rotationMatrix: simd_double3x3? = nil,
        translationVector: SIMD3<Double>,
        distanceMm: Double,
        reprojectionError: Double
    ) {
        self.markerId = markerId
        self.rotationVector = rotationVector
        self.rotationMatrix = rotationMatrix ?? PoseMath.rotationMatrix(fromRodrigues: rotationVector)
        self.translationVector = translationVector
        self.distanceMm = distanceMm
        self.reprojectionError = reprojectionError
    }

    static func == (lhs: PoseResult, rhs: PoseResult) -> Bool {
        lhs.markerId == rhs.markerId &&
            lhs.rotationVector == rhs.rotationVector &&
            matrixEquals(lhs.rotationMatrix, rhs.rotationMatrix) &&
            lhs.translationVector == rhs.translationVector &&
            lhs.distanceMm == rhs.distanceMm &&
            lhs.reprojectionError == rhs.reprojectionError
    }

    private static func matrixEquals(
        _ lhs: simd_double3x3,
        _ rhs: simd_double3x3
    ) -> Bool {
        lhs.columns.0 == rhs.columns.0 &&
            lhs.columns.1 == rhs.columns.1 &&
            lhs.columns.2 == rhs.columns.2
    }
}
