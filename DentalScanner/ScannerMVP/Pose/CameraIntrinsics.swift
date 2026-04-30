import Foundation
import simd

struct CameraIntrinsics: Equatable {
    let matrix: simd_double3x3
    let focalLengthX: Double
    let focalLengthY: Double
    let principalPointX: Double
    let principalPointY: Double

    var openCVCameraMatrixValues: [NSNumber] {
        [
            NSNumber(value: matrix.columns.0.x),
            NSNumber(value: matrix.columns.1.x),
            NSNumber(value: matrix.columns.2.x),
            NSNumber(value: matrix.columns.0.y),
            NSNumber(value: matrix.columns.1.y),
            NSNumber(value: matrix.columns.2.y),
            NSNumber(value: matrix.columns.0.z),
            NSNumber(value: matrix.columns.1.z),
            NSNumber(value: matrix.columns.2.z)
        ]
    }

    init?(
        focalLengthX: Double,
        focalLengthY: Double,
        principalPointX: Double,
        principalPointY: Double
    ) {
        guard focalLengthX.isFinite,
              focalLengthY.isFinite,
              principalPointX.isFinite,
              principalPointY.isFinite,
              focalLengthX > 0,
              focalLengthY > 0
        else {
            return nil
        }

        self.matrix = simd_double3x3(columns: (
            SIMD3(focalLengthX, 0.0, 0.0),
            SIMD3(0.0, focalLengthY, 0.0),
            SIMD3(principalPointX, principalPointY, 1.0)
        ))
        self.focalLengthX = focalLengthX
        self.focalLengthY = focalLengthY
        self.principalPointX = principalPointX
        self.principalPointY = principalPointY
    }

    init?(matrix: simd_double3x3) {
        let focalLengthX = matrix.columns.0.x
        let focalLengthY = matrix.columns.1.y
        let principalPointX = matrix.columns.2.x
        let principalPointY = matrix.columns.2.y

        guard Self.isFinite(matrix),
              focalLengthX > 0,
              focalLengthY > 0
        else {
            return nil
        }

        self.matrix = matrix
        self.focalLengthX = focalLengthX
        self.focalLengthY = focalLengthY
        self.principalPointX = principalPointX
        self.principalPointY = principalPointY
    }

    private static func isFinite(_ matrix: simd_double3x3) -> Bool {
        isFinite(matrix.columns.0) &&
            isFinite(matrix.columns.1) &&
            isFinite(matrix.columns.2)
    }

    private static func isFinite(_ vector: SIMD3<Double>) -> Bool {
        vector.x.isFinite && vector.y.isFinite && vector.z.isFinite
    }

    static func == (lhs: CameraIntrinsics, rhs: CameraIntrinsics) -> Bool {
        matrixEquals(lhs.matrix, rhs.matrix) &&
            lhs.focalLengthX == rhs.focalLengthX &&
            lhs.focalLengthY == rhs.focalLengthY &&
            lhs.principalPointX == rhs.principalPointX &&
            lhs.principalPointY == rhs.principalPointY
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
