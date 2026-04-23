import XCTest
@testable import DentalScannerKit

final class STLExporterTests: XCTestCase {
    func testExportASCIIProducesValidSolidHeaderAndFacet() {
        let exporter = STLExporter()
        let mesh = Mesh3D(
            vertices: [
                SIMD3<Float>(0, 0, 0),
                SIMD3<Float>(1, 0, 0),
                SIMD3<Float>(0, 1, 0)
            ],
            faces: [SIMD3<Int>(0, 1, 2)]
        )

        let stl = exporter.exportASCII(mesh: mesh, name: "UnitMesh")

        XCTAssertTrue(stl.contains("solid UnitMesh"))
        XCTAssertTrue(stl.contains("facet normal"))
        XCTAssertTrue(stl.contains("endsolid UnitMesh"))
    }
}

