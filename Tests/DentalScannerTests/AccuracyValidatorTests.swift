import XCTest
@testable import DentalScannerKit

final class AccuracyValidatorTests: XCTestCase {
    func testValidatorReturnsZeroErrorForIdenticalMeshes() {
        let validator = AccuracyValidator()
        let mesh = Mesh3D(
            vertices: [
                SIMD3<Float>(0, 0, 0),
                SIMD3<Float>(1, 0, 0),
                SIMD3<Float>(0, 1, 0)
            ],
            faces: [SIMD3<Int>(0, 1, 2)]
        )

        let report = validator.validate(scan: mesh, reference: mesh)

        XCTAssertEqual(report.rmsErrorMicrometers, 0, accuracy: 0.0001)
        XCTAssertEqual(report.pointsWithinTolerancePercent, 100, accuracy: 0.0001)
    }
}
