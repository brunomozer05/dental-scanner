import XCTest
@testable import DentalScannerKit

final class MeshReconstructorTests: XCTestCase {
    func testReconstructBuildsSolidMeshForMarkers() {
        let reconstructor = MeshReconstructor()
        let state = ReconstructionState(
            anchorMarkers: [
                DetectedMarker(
                    id: 1,
                    dictionary: .fourByFour50,
                    physicalSizeMillimeters: 8,
                    corners: [],
                    pose: PoseTransform(
                        rotationEuler: SIMD3<Float>(0, 0, 0),
                        translation: SIMD3<Float>(10, 20, 30)
                    ),
                    confidence: 0.95
                )
            ],
            scaleAnchored: true
        )

        let mesh = reconstructor.reconstruct(from: state)

        XCTAssertEqual(mesh.vertices.count, 8)
        XCTAssertEqual(mesh.faces.count, 12)
    }
}
