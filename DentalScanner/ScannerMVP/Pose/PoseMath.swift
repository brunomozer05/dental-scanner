import Foundation
import simd

enum PoseMath {
    static func rotationMatrix(fromRodrigues vector: SIMD3<Double>) -> simd_double3x3 {
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

    static func quaternion(fromRotationMatrix matrix: simd_double3x3) -> simd_quatd? {
        let quaternion = simd_quatd(matrix)
        return isFinite(quaternion) ? quaternion : nil
    }

    static func rotationVector(from matrix: simd_double3x3) -> SIMD3<Double>? {
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

    static func matrixFromRows(
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

    static func matrixElement(
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

    static func isFinite(_ vector: SIMD3<Double>) -> Bool {
        vector.x.isFinite && vector.y.isFinite && vector.z.isFinite
    }

    static func isFinite(_ matrix: simd_double3x3) -> Bool {
        isFinite(matrix.columns.0) &&
            isFinite(matrix.columns.1) &&
            isFinite(matrix.columns.2)
    }

    static func isFinite(_ quaternion: simd_quatd) -> Bool {
        let vector = quaternion.vector
        return vector.x.isFinite &&
            vector.y.isFinite &&
            vector.z.isFinite &&
            vector.w.isFinite
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
}
