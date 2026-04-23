import XCTest
@testable import DentalScannerKit

final class SessionManagerTests: XCTestCase {
    func testSessionAdvancesToProcessingAfterCoverageAndFrameThreshold() {
        let manager = SessionManager(
            configuration: SessionConfiguration(
                coverageBucketCount: 6,
                minimumValidFrames: 6,
                minimumSharpnessScore: 150,
                maximumLightingDeviationRatio: 0.2,
                minimumOverlap: 0.7,
                requiredVisibleTags: 4,
                maximumMotionBlurScore: 0.3
            )
        )

        manager.setCalibration(
            CameraIntrinsics(
                fx: 1,
                fy: 1,
                cx: 0,
                cy: 0,
                distortionCoefficients: [],
                reprojectionErrorPixels: 0.2
            )
        )
        manager.beginCaptureSession()

        for index in 0..<6 {
            let accepted = manager.acceptFrame(
                CaptureFrame(
                    index: index,
                    bucket: index,
                    metrics: FrameQualityMetrics(
                        sharpnessScore: 240,
                        lightingMean: 100,
                        lightingDeviation: 8,
                        motionBlurScore: 0.1,
                        overlapEstimate: 0.8,
                        detectedTagCount: 4,
                        tagsStable: true
                    ),
                    markers: makeMarkers()
                )
            )

            XCTAssertTrue(accepted)
        }

        XCTAssertEqual(manager.state.stage, .processing)
        XCTAssertEqual(manager.state.guidance.validFrameCount, 6)
        XCTAssertEqual(manager.state.guidance.coverageMap.filter { $0 }.count, 6)
    }

    func testRejectedFrameDoesNotIncreaseValidFrameCount() {
        let manager = SessionManager()
        manager.setCalibration(
            CameraIntrinsics(
                fx: 1,
                fy: 1,
                cx: 0,
                cy: 0,
                distortionCoefficients: [],
                reprojectionErrorPixels: 0.2
            )
        )
        manager.beginCaptureSession()

        let accepted = manager.acceptFrame(
            CaptureFrame(
                index: 1,
                bucket: 0,
                metrics: FrameQualityMetrics(
                    sharpnessScore: 40,
                    lightingMean: 100,
                    lightingDeviation: 30,
                    motionBlurScore: 0.8,
                    overlapEstimate: 0.2,
                    detectedTagCount: 1,
                    tagsStable: false
                ),
                markers: []
            )
        )

        XCTAssertFalse(accepted)
        XCTAssertEqual(manager.state.guidance.validFrameCount, 0)
    }

    private func makeMarkers() -> [DetectedMarker] {
        (0..<4).map { index in
            DetectedMarker(
                id: index,
                dictionary: .fourByFour50,
                physicalSizeMillimeters: 8,
                corners: [
                    CGPoint(x: 0, y: 0),
                    CGPoint(x: 10, y: 0),
                    CGPoint(x: 10, y: 10),
                    CGPoint(x: 0, y: 10)
                ],
                pose: PoseTransform(translation: SIMD3<Float>(Float(index), 0, 30)),
                confidence: 0.95
            )
        }
    }
}

