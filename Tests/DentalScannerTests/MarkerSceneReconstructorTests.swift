import CoreGraphics
import XCTest
@testable import DentalScannerKit

final class MarkerSceneReconstructorTests: XCTestCase {
    func testReconstructorFusesObservationsByMarkerID() throws {
        let reconstructor = MarkerSceneReconstructor()

        let frames = [
            CaptureFrame(
                index: 1,
                bucket: 0,
                metrics: makeMetrics(),
                markers: [
                    makeMarker(id: 7, x: 10, y: 20, z: 30),
                    makeMarker(id: 9, x: 30, y: 40, z: 50)
                ]
            ),
            CaptureFrame(
                index: 2,
                bucket: 1,
                metrics: makeMetrics(),
                markers: [
                    makeMarker(id: 7, x: 12, y: 22, z: 32),
                    makeMarker(id: 9, x: 28, y: 38, z: 48)
                ]
            )
        ]

        let reconstruction = reconstructor.reconstruct(from: frames)

        XCTAssertEqual(reconstruction.anchorMarkers.count, 2)
        XCTAssertEqual(reconstruction.sparsePoints.count, 2)

        let marker7 = try XCTUnwrap(reconstruction.anchorMarkers.first { $0.id == 7 })
        let pose = try XCTUnwrap(marker7.pose)
        XCTAssertEqual(pose.translation.x, Float(11), accuracy: Float(0.0001))
        XCTAssertEqual(pose.translation.y, Float(21), accuracy: Float(0.0001))
        XCTAssertEqual(pose.translation.z, Float(31), accuracy: Float(0.0001))
    }

    private func makeMetrics() -> FrameQualityMetrics {
        FrameQualityMetrics(
            sharpnessScore: 200,
            lightingMean: 100,
            lightingDeviation: 10,
            motionBlurScore: 0.1,
            overlapEstimate: 0.8,
            detectedTagCount: 4,
            tagsStable: true
        )
    }

    private func makeMarker(id: Int, x: Float, y: Float, z: Float) -> DetectedMarker {
        DetectedMarker(
            id: id,
            dictionary: .fourByFour50,
            physicalSizeMillimeters: 8,
            corners: [
                CGPoint(x: 0, y: 0),
                CGPoint(x: 10, y: 0),
                CGPoint(x: 10, y: 10),
                CGPoint(x: 0, y: 10)
            ],
            pose: PoseTransform(
                rotationEuler: SIMD3<Float>(0, 0, 0),
                translation: SIMD3<Float>(x, y, z)
            ),
            confidence: 0.95
        )
    }
}
