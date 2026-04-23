import Foundation
import simd

public final class AccuracyValidator {
    public init() {}

    public func validate(
        scan: Mesh3D,
        reference: Mesh3D,
        toleranceMicrometers: Double = 100
    ) -> AccuracyReport {
        let centeredScan = centered(scan.vertices)
        let centeredReference = centered(reference.vertices)
        let pairCount = min(centeredScan.count, centeredReference.count)

        guard pairCount > 0 else {
            return AccuracyReport(
                rmsErrorMicrometers: 0,
                maxErrorMicrometers: 0,
                meanErrorMicrometers: 0,
                pointsWithinTolerancePercent: 0
            )
        }

        let errors = zip(centeredScan.prefix(pairCount), centeredReference.prefix(pairCount)).map { lhs, rhs in
            Double(simd_length(lhs - rhs)) * 1_000
        }

        let meanError = errors.reduce(0, +) / Double(errors.count)
        let rmsError = sqrt(errors.reduce(0) { $0 + ($1 * $1) } / Double(errors.count))
        let maxError = errors.max() ?? 0
        let pointsWithinTolerance = Double(errors.filter { $0 <= toleranceMicrometers }.count) / Double(errors.count) * 100

        return AccuracyReport(
            rmsErrorMicrometers: rmsError,
            maxErrorMicrometers: maxError,
            meanErrorMicrometers: meanError,
            pointsWithinTolerancePercent: pointsWithinTolerance
        )
    }

    private func centered(_ vertices: [SIMD3<Float>]) -> [SIMD3<Float>] {
        guard !vertices.isEmpty else {
            return []
        }

        let centroid = vertices.reduce(SIMD3<Float>.zero, +) / Float(vertices.count)
        return vertices.map { $0 - centroid }
    }
}

