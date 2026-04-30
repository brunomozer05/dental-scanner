import Foundation
import simd

struct MarkerToImplantTransform {
    let translationMm: SIMD3<Double>
    let rotationVector: SIMD3<Double>

    static let identity = MarkerToImplantTransform()

    init(
        translationMm: SIMD3<Double> = .zero,
        rotationVector: SIMD3<Double> = .zero
    ) {
        self.translationMm = translationMm
        self.rotationVector = rotationVector
    }

    static func applyOffset(
        tagPose: PoseResult,
        offset: MarkerToImplantTransform
    ) -> ImplantPose {
        offset.applyOffset(to: tagPose)
    }

    func applyOffset(to tagPose: PoseResult) -> ImplantPose {
        let tagRotation = tagPose.rotationMatrix
        let implantOffsetRotation = Self.rotationMatrix(fromRodrigues: rotationVector)
        let implantTranslation = tagPose.translationVector + tagRotation * translationMm
        let implantRotation = tagRotation * implantOffsetRotation

        return ImplantPose(
            markerId: tagPose.markerId,
            rotationMatrix: implantRotation,
            translationVector: implantTranslation,
            distanceMm: simd_length(implantTranslation),
            sourceTagPose: tagPose
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
}
