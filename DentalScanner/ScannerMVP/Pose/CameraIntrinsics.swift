import Foundation
import simd

struct CameraIntrinsics: Equatable {
    let focalLengthX: Double
    let focalLengthY: Double
    let principalPointX: Double
    let principalPointY: Double

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

        self.focalLengthX = focalLengthX
        self.focalLengthY = focalLengthY
        self.principalPointX = principalPointX
        self.principalPointY = principalPointY
    }

    init?(matrix: simd_float3x3) {
        self.init(
            focalLengthX: Double(matrix.columns.0.x),
            focalLengthY: Double(matrix.columns.1.y),
            principalPointX: Double(matrix.columns.2.x),
            principalPointY: Double(matrix.columns.2.y)
        )
    }
}
