import Foundation
import simd
import XCTest
@testable import DentalScanner

final class ScanSessionCaptureMaturityReplayTests: XCTestCase {
    // 1. camera-from-marker convention
    func testCameraFromMarkerConventionPlacesCameraCenterAtMarkerOriginInCameraSpace() throws {
        let cameraCenter = SIMD3<Double>(23, -11, 87)
        let pose = makePose(markerId: 2, cameraCenterInMarker: cameraCenter)
        let cameraOrigin = pose.rotationMatrix * cameraCenter + pose.translationVector

        assertVector(cameraOrigin, equals: .zero, accuracy: 1e-10)
        _ = try viewpoint(for: pose)
    }

    // 2. camera center in marker coordinates
    func testViewpointRecoversCameraCenterInMarkerCoordinates() throws {
        let expected = SIMD3<Double>(17, 29, -83)
        let result = try viewpoint(
            for: makePose(markerId: 1, cameraCenterInMarker: expected)
        )

        assertVector(result.cameraCenterInMarker, equals: expected, accuracy: 1e-10)
    }

    // 3. marker-to-camera direction
    func testViewpointProducesMarkerToCameraDirection() throws {
        let center = SIMD3<Double>(3, -4, 12)
        let result = try viewpoint(
            for: makePose(markerId: 3, cameraCenterInMarker: center)
        )

        assertVector(
            result.viewDirection,
            equals: center / simd_length(center),
            accuracy: 1e-12
        )
    }

    // 4. vector normalization
    func testViewDirectionNormalizationProducesUnitVector() throws {
        let normalized = try XCTUnwrap(
            CaptureMaturityViewpointMath.normalized(SIMD3(3, 4, 12))
        )

        XCTAssertEqual(simd_length(normalized), 1, accuracy: 1e-12)
        assertVector(
            normalized,
            equals: SIMD3(3.0 / 13.0, 4.0 / 13.0, 12.0 / 13.0),
            accuracy: 1e-12
        )
    }

    // 5. non-finite pose
    func testNonFinitePoseIsRejected() {
        let pose = PoseResult(
            markerId: 0,
            rotationVector: SIMD3(0.13, -0.07, 0.11),
            rotationMatrix: PoseMath.rotationMatrix(
                fromRodrigues: SIMD3(0.13, -0.07, 0.11)
            ),
            translationVector: SIMD3(.nan, 1, 2),
            distanceMm: 10,
            reprojectionError: 0.2,
            markerAreaPixels: 500,
            usedPointCount: 4
        )

        assertViewpointFailure(pose, reason: .nonFiniteTranslation)
    }

    // 6. non-orthonormal rotation
    func testNonOrthonormalRotationIsRejected() {
        let matrix = PoseMath.matrixFromRows(
            SIMD3(2, 0, 0),
            SIMD3(0, 1, 0),
            SIMD3(0, 0, 1)
        )
        let pose = makePose(
            markerId: 0,
            cameraCenterInMarker: SIMD3(1, 2, 30),
            rotationMatrix: matrix
        )

        assertViewpointFailure(pose, reason: .nonOrthonormalRotation)
    }

    // 7. invalid determinant
    func testInvalidRotationDeterminantIsRejected() {
        let reflection = PoseMath.matrixFromRows(
            SIMD3(-1, 0, 0),
            SIMD3(0, 1, 0),
            SIMD3(0, 0, 1)
        )
        let pose = makePose(
            markerId: 0,
            cameraCenterInMarker: SIMD3(1, 2, 30),
            rotationMatrix: reflection
        )

        assertViewpointFailure(pose, reason: .invalidRotationDeterminant)
    }

    // 8. zero-norm translation/camera center
    func testZeroTranslationProducesZeroCameraCenterRejection() {
        let pose = PoseResult(
            markerId: 0,
            rotationVector: SIMD3(0.13, -0.07, 0.11),
            rotationMatrix: PoseMath.rotationMatrix(
                fromRodrigues: SIMD3(0.13, -0.07, 0.11)
            ),
            translationVector: .zero,
            distanceMm: 0,
            reprojectionError: 0.2,
            markerAreaPixels: 500,
            usedPointCount: 4
        )

        assertViewpointFailure(pose, reason: .zeroCameraCenterNorm)
    }

    // 9. known vector angle
    func testAngularDistanceMatchesKnownRightAngle() {
        XCTAssertEqual(
            CaptureMaturityViewpointMath.angularDistanceDegrees(
                SIMD3(1, 0, 0),
                SIMD3(0, 1, 0)
            ),
            90,
            accuracy: 1e-12
        )
    }

    // 10. dot-product clamping
    func testAngularDistanceClampsDotProductNumerically() {
        XCTAssertEqual(
            CaptureMaturityViewpointMath.angleRadians(
                fromDotProduct: 1.0 + 1e-9
            ),
            0,
            accuracy: 0
        )
        XCTAssertEqual(
            CaptureMaturityViewpointMath.angleRadians(
                fromDotProduct: -1.0 - 1e-9
            ),
            Double.pi,
            accuracy: 0
        )
    }

    // 11. first view always selected
    func testFirstViewIsAlwaysSelected() {
        let summary = analyze(
            frames: [makeFrameInput(index: 0, poses: [poseAtAngle(0, markerId: 0)])],
            expectedMarkerIds: [0],
            configuration: makeConfiguration(
                minimumDistinctViewAngleDegrees: 179,
                targetSelectedFrameCount: 1
            )
        )

        XCTAssertEqual(marker(summary, 0).selectedDistinctViewCount, 1)
        XCTAssertEqual(summary.selection.selectedObservationCount, 1)
    }

    // 12. below-threshold view is redundant
    func testViewBelowThresholdIsClassifiedAsRedundant() {
        let summary = analyze(
            frames: [
                makeFrameInput(index: 0, poses: [poseAtAngle(0, markerId: 0)]),
                makeFrameInput(index: 1, poses: [poseAtAngle(1, markerId: 0)])
            ],
            expectedMarkerIds: [0],
            configuration: makeConfiguration(
                minimumDistinctViewAngleDegrees: 2,
                targetSelectedFrameCount: 1
            )
        )
        let marker = marker(summary, 0)

        XCTAssertEqual(marker.selectedDistinctViewCount, 1)
        XCTAssertEqual(marker.redundantViewCount, 1)
        XCTAssertEqual(marker.selectedObservationCount, 1)
    }

    // 13. above-threshold view is selected
    func testViewAboveThresholdIsSelected() {
        let summary = analyze(
            frames: [
                makeFrameInput(index: 0, poses: [poseAtAngle(0, markerId: 0)]),
                makeFrameInput(index: 1, poses: [poseAtAngle(3, markerId: 0)])
            ],
            expectedMarkerIds: [0],
            configuration: makeConfiguration(
                minimumDistinctViewAngleDegrees: 2,
                targetSelectedFrameCount: 2
            )
        )

        XCTAssertEqual(marker(summary, 0).selectedDistinctViewCount, 2)
        XCTAssertEqual(summary.selection.selectedFrameCount, 2)
    }

    // 14. independent marker histories
    func testViewpointHistoryIsIndependentPerMarker() {
        let summary = analyze(
            frames: [
                makeFrameInput(
                    index: 0,
                    poses: [
                        poseAtAngle(0, markerId: 0),
                        poseAtAngle(0, markerId: 1)
                    ]
                ),
                makeFrameInput(
                    index: 1,
                    poses: [
                        poseAtAngle(0.5, markerId: 0),
                        poseAtAngle(3, markerId: 1)
                    ]
                )
            ],
            expectedMarkerIds: [0, 1],
            configuration: makeConfiguration(
                minimumDistinctViewAngleDegrees: 2,
                targetSelectedFrameCount: 2
            )
        )

        XCTAssertEqual(marker(summary, 0).selectedDistinctViewCount, 1)
        XCTAssertEqual(marker(summary, 0).redundantViewCount, 1)
        XCTAssertEqual(marker(summary, 1).selectedDistinctViewCount, 2)
        XCTAssertEqual(marker(summary, 1).redundantViewCount, 0)
    }

    // 15. no M0 special handling
    func testM0ReceivesNoSpecialMaturityHandling() {
        let summary = analyze(
            frames: [
                makeFrameInput(
                    index: 0,
                    poses: [
                        poseAtAngle(0, markerId: 0),
                        poseAtAngle(0, markerId: 1)
                    ]
                ),
                makeFrameInput(
                    index: 1,
                    poses: [
                        poseAtAngle(4, markerId: 0),
                        poseAtAngle(4, markerId: 1)
                    ]
                )
            ],
            expectedMarkerIds: [0, 1],
            configuration: makeConfiguration(
                minimumDistinctViewAngleDegrees: 2,
                minimumValidObservationsPerMarker: 2,
                minimumDistinctViewsPerMarker: 2,
                targetSelectedFrameCount: 2
            )
        )
        let m0 = marker(summary, 0)
        let m1 = marker(summary, 1)

        XCTAssertEqual(m0.validObservationCount, m1.validObservationCount)
        XCTAssertEqual(m0.selectedDistinctViewCount, m1.selectedDistinctViewCount)
        XCTAssertEqual(m0.maturityState, m1.maturityState)
        XCTAssertEqual(m0.progress, m1.progress)
    }

    // 16. frame-level selection
    func testWholeFrameSelectionRetainsValidRedundantMarkerObservation() {
        let configuration = makeConfiguration(
            minimumDistinctViewAngleDegrees: 2,
            targetSelectedFrameCount: 2,
            strictSelectionStrategy: .wholeFrameWhenAnyMarkerHasDistinctView
        )
        let summary = analyze(
            frames: [
                makeFrameInput(
                    index: 0,
                    poses: [
                        poseAtAngle(0, markerId: 0),
                        poseAtAngle(0, markerId: 1)
                    ]
                ),
                makeFrameInput(
                    index: 1,
                    poses: [
                        poseAtAngle(4, markerId: 0),
                        poseAtAngle(0.5, markerId: 1)
                    ]
                )
            ],
            expectedMarkerIds: [0, 1],
            configuration: configuration
        )

        XCTAssertEqual(summary.selection.selectedObservationCount, 4)
        XCTAssertEqual(summary.selection.framesWithAllExpectedMarkersSelected, 2)
        XCTAssertEqual(marker(summary, 1).selectedObservationCount, 2)
        XCTAssertEqual(marker(summary, 1).selectedDistinctViewCount, 1)
        XCTAssertEqual(marker(summary, 1).redundantViewCount, 1)
    }

    // 17. per-observation selection
    func testPerObservationSelectionExcludesRedundantMarkerObservation() {
        let summary = analyze(
            frames: [
                makeFrameInput(
                    index: 0,
                    poses: [
                        poseAtAngle(0, markerId: 0),
                        poseAtAngle(0, markerId: 1)
                    ]
                ),
                makeFrameInput(
                    index: 1,
                    poses: [
                        poseAtAngle(4, markerId: 0),
                        poseAtAngle(0.5, markerId: 1)
                    ]
                )
            ],
            expectedMarkerIds: [0, 1],
            configuration: makeConfiguration(
                minimumDistinctViewAngleDegrees: 2,
                targetSelectedFrameCount: 2,
                strictSelectionStrategy: .perMarkerObservation
            )
        )

        XCTAssertEqual(summary.selection.selectedObservationCount, 3)
        XCTAssertEqual(summary.selection.framesWithAllExpectedMarkersSelected, 1)
        XCTAssertEqual(marker(summary, 1).selectedObservationCount, 1)
        XCTAssertEqual(marker(summary, 1).redundantViewCount, 1)
    }

    // 18. frame and observation counts remain distinct
    func testFrameCountIsDistinctFromObservationCount() {
        let summary = analyze(
            frames: [
                makeFrameInput(
                    index: 0,
                    poses: [
                        poseAtAngle(0, markerId: 0),
                        poseAtAngle(20, markerId: 1),
                        poseAtAngle(40, markerId: 2)
                    ]
                )
            ],
            expectedMarkerIds: [0, 1, 2],
            configuration: makeConfiguration(targetSelectedFrameCount: 1)
        )

        XCTAssertEqual(summary.selection.selectedFrameCount, 1)
        XCTAssertEqual(summary.selection.selectedObservationCount, 3)
    }

    func testInsufficientFrameSupportIsNotMisclassifiedAsAngularRedundancy() {
        let summary = analyze(
            frames: [
                makeFrameInput(
                    index: 0,
                    poses: [poseAtAngle(0, markerId: 0)]
                )
            ],
            expectedMarkerIds: [0],
            configuration: makeConfiguration(
                minimumObservationsPerFrame: 2
            )
        )
        let marker = marker(summary, 0)

        XCTAssertEqual(marker.validObservationCount, 1)
        XCTAssertEqual(marker.redundantViewCount, 0)
        XCTAssertEqual(marker.frameSupportExcludedObservationCount, 1)
        XCTAssertEqual(
            summary.selection.frameSupportExcludedObservationCount,
            1
        )
    }

    // 19. exact minimum view count
    func testExactMinimumDistinctViewCountMaturesMarker() {
        let summary = analyze(
            frames: [
                makeFrameInput(index: 0, poses: [poseAtAngle(0, markerId: 0)]),
                makeFrameInput(index: 1, poses: [poseAtAngle(4, markerId: 0)])
            ],
            expectedMarkerIds: [0],
            configuration: makeConfiguration(
                minimumDistinctViewAngleDegrees: 2,
                minimumValidObservationsPerMarker: 2,
                minimumDistinctViewsPerMarker: 2,
                targetSelectedFrameCount: 2
            )
        )

        XCTAssertEqual(marker(summary, 0).maturityState, .mature)
        XCTAssertEqual(summary.globalMaturity.globalMaturityState, .mature)
    }

    // 20. one view below minimum
    func testOneViewBelowMinimumRemainsInsufficient() {
        let summary = analyze(
            frames: [makeFrameInput(index: 0, poses: [poseAtAngle(0, markerId: 0)])],
            expectedMarkerIds: [0],
            configuration: makeConfiguration(
                minimumValidObservationsPerMarker: 1,
                minimumDistinctViewsPerMarker: 2,
                targetSelectedFrameCount: 1
            )
        )

        XCTAssertEqual(
            marker(summary, 0).maturityState,
            .insufficientDistinctViews
        )
    }

    // 21. spherical spread ground truth
    func testSphericalSpreadMatchesSymmetricGroundTruth() throws {
        let spread = try XCTUnwrap(
            CaptureMaturityViewpointMath.angularSpreadDegrees(
                [direction(atDegrees: -10), direction(atDegrees: 10)]
            )
        )
        let result = CaptureMaturityViewpointMath.angularSpread(
            [direction(atDegrees: -10), direction(atDegrees: 10)]
        )

        XCTAssertEqual(spread, 10, accuracy: 1e-9)
        XCTAssertTrue(result.meanDirectionDefined)
        XCTAssertEqual(try XCTUnwrap(result.degrees), spread)
    }

    // 22. directional concentration
    func testSphericalSpreadDetectsDirectionalConcentration() throws {
        let spread = try XCTUnwrap(
            CaptureMaturityViewpointMath.angularSpreadDegrees(
                [
                    direction(atDegrees: 0),
                    direction(atDegrees: 0.2),
                    direction(atDegrees: 0.4)
                ]
            )
        )
        let antipodal = CaptureMaturityViewpointMath.angularSpread(
            [SIMD3(1, 0, 0), SIMD3(-1, 0, 0)]
        )

        XCTAssertLessThan(spread, 0.2)
        XCTAssertGreaterThan(spread, 0)
        XCTAssertFalse(antipodal.meanDirectionDefined)
        XCTAssertNil(antipodal.degrees)
    }

    func testUndefinedSphericalMeanCannotProduceFalseMaturity() {
        let summary = analyze(
            frames: [
                makeFrameInput(
                    index: 0,
                    poses: [poseAtAngle(0, markerId: 0)]
                ),
                makeFrameInput(
                    index: 1,
                    poses: [poseAtAngle(180, markerId: 0)]
                )
            ],
            expectedMarkerIds: [0],
            configuration: makeConfiguration(
                minimumDistinctViewAngleDegrees: 0,
                minimumValidObservationsPerMarker: 2,
                minimumDistinctViewsPerMarker: 2,
                targetSelectedFrameCount: 2,
                minimumAngularSpreadDegrees: 0
            )
        )
        let marker = marker(summary, 0)

        XCTAssertFalse(marker.angularMeanDirectionDefined)
        XCTAssertNil(marker.angularSpreadDegrees)
        XCTAssertEqual(
            marker.maturityState,
            .insufficientAngularSpread
        )
        XCTAssertLessThan(
            summary.globalMaturity.globalProgressPercent,
            100
        )
    }

    // 23. known angular coverage bins
    func testCoverageMapsKnownDirectionsToExpectedBins() {
        let coverage = CaptureMaturityCoverage.summary(
            directions: [
                SIMD3(1, 0, 0),
                SIMD3(0, 1, 0),
                SIMD3(0, -1, 0),
                SIMD3(0, 0, -1)
            ],
            azimuthBinCount: 4,
            elevationBinCount: 2,
            epsilon: 1e-9
        )

        XCTAssertEqual(coverage.coveredBinCount, 4)
        XCTAssertEqual(
            coverage.coveredBins.map {
                [$0.elevationIndex, $0.azimuthIndex]
            },
            [[0, 2], [1, 1], [1, 2], [1, 3]]
        )
    }

    // 24. missing bins
    func testCoverageReportsMissingBins() {
        let coverage = CaptureMaturityCoverage.summary(
            directions: [
                SIMD3(1, 0, 0),
                SIMD3(0, 0, -1)
            ],
            azimuthBinCount: 4,
            elevationBinCount: 2,
            epsilon: 1e-9
        )

        XCTAssertEqual(coverage.totalBinCount, 8)
        XCTAssertEqual(coverage.coveredBinCount, 2)
        XCTAssertEqual(coverage.missingBins.count, 6)
        XCTAssertEqual(coverage.coveragePercent, 25, accuracy: 1e-12)
    }

    func testCoverageNormalizesPositivePiToNegativePiBoundaryBin() {
        let coverage = CaptureMaturityCoverage.summary(
            directions: [
                SIMD3(-1.0, 0.0, 0.0),
                SIMD3(-1.0, -0.0, 0.0)
            ],
            azimuthBinCount: 4,
            elevationBinCount: 2,
            epsilon: 1e-9
        )

        XCTAssertEqual(coverage.coveredBinCount, 1)
        XCTAssertEqual(coverage.coveredBins.first?.azimuthIndex, 0)
        XCTAssertEqual(coverage.coveredBins.first?.elevationIndex, 1)
        XCTAssertEqual(
            coverage.coveredBins.first?.azimuthMinimumDegrees,
            -180
        )
    }

    // 25. immature marker blocks session
    func testImmatureMarkerBlocksGlobalMaturity() {
        let summary = partiallyMatureTwoMarkerSummary()

        XCTAssertEqual(marker(summary, 0).maturityState, .mature)
        XCTAssertNotEqual(marker(summary, 1).maturityState, .mature)
        XCTAssertEqual(
            summary.globalMaturity.globalMaturityState,
            .insufficientMarkerMaturity
        )
    }

    // 26. slowest marker
    func testSlowestMarkerIsReportedDeterministically() {
        let summary = partiallyMatureTwoMarkerSummary()

        XCTAssertEqual(summary.globalMaturity.slowestMarkerId, 1)
        XCTAssertEqual(
            summary.globalMaturity.slowestMarkerBlockingReason,
            MarkerCaptureMaturityState.insufficientDistinctViews.rawValue
        )
    }

    // 27. disconnected component
    func testDisconnectedSelectedGraphBlocksMaturity() {
        let summary = analyze(
            frames: [
                makeFrameInput(index: 0, poses: [poseAtAngle(0, markerId: 0)]),
                makeFrameInput(index: 1, poses: [poseAtAngle(20, markerId: 1)])
            ],
            expectedMarkerIds: [0, 1],
            configuration: makeConfiguration(
                targetSelectedFrameCount: 2,
                requireExpectedMarkersConnected: true
            )
        )

        XCTAssertEqual(marker(summary, 0).maturityState, .mature)
        XCTAssertEqual(marker(summary, 1).maturityState, .mature)
        XCTAssertFalse(summary.selectedConnectivity.expectedMarkersConnected)
        XCTAssertEqual(
            summary.globalMaturity.globalMaturityState,
            .insufficientConnectivity
        )
    }

    // 28. ALL population
    func testAllPolicyPreservesPersistedObservationPopulation() throws {
        let result = try ScanSessionCaptureMaturityReplayRunner(
            configuration: makeConfiguration(targetSelectedFrameCount: 1)
        ).run(sessionFileURL: fixtureURL("pregate_ab_valid"))

        XCTAssertEqual(result.summary.all.strict.selection.sourceObservationCount, 4)
        XCTAssertEqual(result.summary.all.strict.selection.policyInputObservationCount, 4)
        XCTAssertEqual(
            result.summary.all.readerSelectionDiagnostics.rawMarkerObservationCount,
            4
        )
    }

    // 29. FILTERED persisted decisions
    func testFilteredPolicyUsesPersistedAcceptedDecisions() throws {
        let result = try ScanSessionCaptureMaturityReplayRunner(
            configuration: makeConfiguration(targetSelectedFrameCount: 1)
        ).run(sessionFileURL: fixtureURL("pregate_ab_valid"))

        XCTAssertEqual(
            result.summary.filtered.strict.selection.sourceObservationCount,
            4
        )
        XCTAssertEqual(
            result.summary.filtered.strict.selection.policyInputObservationCount,
            2
        )
        XCTAssertEqual(
            result.summary.filtered.readerSelectionDiagnostics
                .acceptedMarkerObservationCount,
            2
        )
    }

    // 30. missing gate annotation diagnostics
    func testMissingGateAnnotationsAreDiagnosedWithoutInference() throws {
        let result = try ScanSessionCaptureMaturityReplayRunner(
            configuration: makeConfiguration(targetSelectedFrameCount: 1)
        ).run(sessionFileURL: fixtureURL("valid_completed"))

        XCTAssertEqual(result.summary.filtered.missingGateEvaluationCount, 6)
        XCTAssertEqual(result.summary.filtered.missingGateDecisionCount, 0)
        XCTAssertEqual(
            result.summary.filtered.strict.selection.policyInputObservationCount,
            0
        )
        XCTAssertEqual(
            result.summary.integrityResult,
            "validWithMissingGateAnnotations"
        )
    }

    // 31. STRICT never relaxes
    func testStrictModeNeverRelaxesThresholds() {
        let configuration = relaxationTestConfiguration()
        let summary = analyze(
            frames: relaxationFrames(),
            expectedMarkerIds: [0, 1],
            mode: .strict,
            configuration: configuration
        )

        XCTAssertEqual(summary.relaxationCount, 0)
        XCTAssertTrue(summary.relaxationHistory.isEmpty)
        XCTAssertEqual(
            summary.currentMinimumDistinctViewAngleDegrees,
            configuration.minimumDistinctViewAngleDegrees
        )
        XCTAssertEqual(
            summary.currentMinimumAngularSpreadDegrees,
            configuration.minimumAngularSpreadDegrees
        )
    }

    // 32. REFERENCE_LIKE relaxation history
    func testReferenceLikeModePersistsEveryRelaxation() {
        let summary = analyze(
            frames: relaxationFrames(),
            expectedMarkerIds: [0, 1],
            mode: .referenceLike,
            configuration: relaxationTestConfiguration()
        )

        XCTAssertEqual(summary.relaxationCount, 3)
        XCTAssertEqual(summary.relaxationHistory.map(\.relaxationCount), [1, 2, 3])
        XCTAssertEqual(summary.relaxationHistory.map(\.frameIndex), [1, 2, 3])
        XCTAssertTrue(
            zip(
                summary.relaxationHistory,
                summary.relaxationHistory.dropFirst()
            ).allSatisfy { pair in
                pair.0.currentMinimumDistinctViewAngleDegrees >
                    pair.1.currentMinimumDistinctViewAngleDegrees
            }
        )
    }

    // 33. relaxed mode does not replace STRICT
    func testReferenceLikeModeDoesNotReplaceStrictResult() {
        let configuration = relaxationTestConfiguration()
        let strict = analyze(
            frames: relaxationFrames(),
            expectedMarkerIds: [0, 1],
            mode: .strict,
            configuration: configuration
        )
        let referenceLike = analyze(
            frames: relaxationFrames(),
            expectedMarkerIds: [0, 1],
            mode: .referenceLike,
            configuration: configuration
        )

        XCTAssertEqual(strict.mode, "STRICT")
        XCTAssertEqual(strict.relaxationCount, 0)
        XCTAssertEqual(referenceLike.mode, "REFERENCE_LIKE")
        XCTAssertGreaterThan(referenceLike.relaxationCount, 0)
        XCTAssertEqual(
            strict.currentMinimumDistinctViewAngleDegrees,
            configuration.minimumDistinctViewAngleDegrees
        )
        XCTAssertNotEqual(
            strict.currentMinimumDistinctViewAngleDegrees,
            referenceLike.currentMinimumDistinctViewAngleDegrees
        )
    }

    // 34. no premature 100 percent
    func testDiagnosticProgressCannotReachOneHundredBeforeMaturity() {
        let summary = analyze(
            frames: [
                makeFrameInput(
                    index: 0,
                    timestamp: 100,
                    poses: [
                        poseAtAngle(0, markerId: 0),
                        poseAtAngle(20, markerId: 1)
                    ]
                )
            ],
            expectedMarkerIds: [0, 1],
            configuration: makeConfiguration(
                minimumValidObservationsPerMarker: 1,
                minimumDistinctViewsPerMarker: 1,
                targetSelectedFrameCount: 2
            )
        )

        XCTAssertEqual(
            summary.globalMaturity.globalMaturityState,
            .insufficientSelectedFrameSupport
        )
        XCTAssertLessThan(summary.globalMaturity.globalProgressPercent, 100)
        XCTAssertLessThanOrEqual(summary.globalMaturity.globalProgressPercent, 99)
        XCTAssertEqual(
            summary.globalMaturity.firstTimestampAllMarkersMature,
            100
        )
        XCTAssertEqual(summary.globalMaturity.frameIndexAllMarkersMature, 0)
        XCTAssertNil(summary.globalMaturity.firstTimestampGlobalMature)
        XCTAssertNil(summary.globalMaturity.frameIndexGlobalMature)
    }

    // 35. exactly 100 percent at maturity
    func testDiagnosticProgressReachesOneHundredExactlyAtGlobalMaturity() {
        let summary = analyze(
            frames: [
                makeFrameInput(
                    index: 0,
                    timestamp: 100,
                    poses: [poseAtAngle(0, markerId: 0)]
                ),
                makeFrameInput(
                    index: 1,
                    timestamp: 100.5,
                    poses: [poseAtAngle(4, markerId: 0)]
                )
            ],
            expectedMarkerIds: [0],
            configuration: makeConfiguration(
                minimumDistinctViewAngleDegrees: 2,
                minimumValidObservationsPerMarker: 2,
                minimumDistinctViewsPerMarker: 2,
                targetSelectedFrameCount: 2
            )
        )

        XCTAssertEqual(summary.globalMaturity.globalMaturityState, .mature)
        XCTAssertEqual(summary.globalMaturity.globalProgressPercent, 100)
        XCTAssertTrue(marker(summary, 0).angularMeanDirectionDefined)
        XCTAssertNotNil(marker(summary, 0).angularSpreadDegrees)
        XCTAssertEqual(
            summary.globalMaturity.firstTimestampAllMarkersMature,
            100.5
        )
        XCTAssertEqual(summary.globalMaturity.frameIndexAllMarkersMature, 1)
        XCTAssertEqual(
            summary.globalMaturity.firstTimestampGlobalMature,
            100.5
        )
        XCTAssertEqual(summary.globalMaturity.frameIndexGlobalMature, 1)
    }

    // 36. deterministic timeline intervals
    func testTimelineUsesDeterministicConfiguredIntervals() {
        let timestamps = [100.0, 100.2, 100.5, 100.9, 101.0]
        let frames = timestamps.enumerated().map { index, timestamp in
            makeFrameInput(
                index: index,
                timestamp: timestamp,
                poses: [poseAtAngle(Double(index) * 3, markerId: 0)]
            )
        }
        let summary = analyze(
            frames: frames,
            expectedMarkerIds: [0],
            configuration: makeConfiguration(
                minimumDistinctViewAngleDegrees: 0,
                minimumValidObservationsPerMarker: 10,
                minimumDistinctViewsPerMarker: 10,
                targetSelectedFrameCount: 10,
                timelineIntervalSeconds: 0.5
            )
        )

        XCTAssertEqual(
            summary.timeline.compactMap(\.elapsedSeconds),
            [0, 0.5, 1.0]
        )
        XCTAssertEqual(summary.timeline.map(\.frameIndex), [0, 2, 4])
        XCTAssertTrue(
            summary.timeline.allSatisfy { snapshot in
                snapshot.perMarker.allSatisfy(
                    \.angularMeanDirectionDefined
                )
            }
        )
    }

    // 37. deterministic frame ordering
    func testRepeatedAnalysisProducesDeterministicFrameOrdering() {
        let frames = (0..<3).map {
            makeFrameInput(
                index: $0,
                timestamp: 100 + Double($0) * 0.5,
                poses: [poseAtAngle(Double($0) * 4, markerId: 0)]
            )
        }
        let configuration = makeConfiguration(
            minimumDistinctViewAngleDegrees: 0,
            targetSelectedFrameCount: 3
        )
        let first = analyze(
            frames: frames,
            expectedMarkerIds: [0],
            configuration: configuration
        )
        let second = analyze(
            frames: frames,
            expectedMarkerIds: [0],
            configuration: configuration
        )

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.selectionFrameIndices, [0, 1, 2])
    }

    // 38. deterministic marker ordering
    func testMarkerSnapshotsAreDeterministicallySorted() {
        let summary = analyze(
            frames: [
                makeFrameInput(
                    index: 0,
                    poses: [
                        poseAtAngle(30, markerId: 3),
                        poseAtAngle(10, markerId: 1),
                        poseAtAngle(20, markerId: 2)
                    ]
                )
            ],
            expectedMarkerIds: [3, 1, 2],
            configuration: makeConfiguration(targetSelectedFrameCount: 1)
        )

        XCTAssertEqual(summary.markerMaturity.map(\.markerId), [1, 2, 3])
        XCTAssertEqual(
            summary.timeline.first?.perMarker.map(\.markerId) ?? [],
            [1, 2, 3]
        )
    }

    // 39. deterministic bin ordering
    func testCoverageBinsAreDeterministicallySorted() {
        let coverage = CaptureMaturityCoverage.summary(
            directions: [
                SIMD3(0, 1, 0),
                SIMD3(0, 0, -1),
                SIMD3(1, 0, 0)
            ],
            azimuthBinCount: 4,
            elevationBinCount: 2,
            epsilon: 1e-9
        )

        assertBinsSorted(coverage.coveredBins)
        assertBinsSorted(coverage.missingBins)
    }

    // 40. pretty-printed JSON
    func testCaptureMaturityJSONIsPrettyPrinted() throws {
        let summary = try replaySummary()
        let data = try ScanSessionCaptureMaturityReplayExporter.encode(summary)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(json.contains("\n  \""))
        XCTAssertTrue(json.hasSuffix("\n") || json.hasSuffix("}"))
    }

    // 41. sorted JSON keys
    func testCaptureMaturityJSONUsesSortedKeys() throws {
        let summary = try replaySummary()
        let data = try ScanSessionCaptureMaturityReplayExporter.encode(summary)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        let actual = try XCTUnwrap(json.range(of: "\"actualProgressComparison\""))
        let algorithm = try XCTUnwrap(json.range(of: "\"algorithmIdentifier\""))
        let artifact = try XCTUnwrap(json.range(of: "\"artifactSchemaVersion\""))

        XCTAssertLessThan(actual.lowerBound, algorithm.lowerBound)
        XCTAssertLessThan(algorithm.lowerBound, artifact.lowerBound)
    }

    // 42. atomic write
    func testCaptureMaturityExporterAtomicallyReplacesCompleteArtifact() throws {
        let summary = try replaySummary()
        try withTemporaryDirectory { directory in
            let scanURL = directory.appendingPathComponent("SavedScan.stl")
            try Data("production-stl".utf8).write(to: scanURL)
            let outputURL = ScanSessionCaptureMaturityReplayExporter.outputURL(
                forScanFileURL: scanURL
            )
            try Data("stale-incomplete-json".utf8).write(to: outputURL)

            let writtenURL = try ScanSessionCaptureMaturityReplayExporter.write(
                summary,
                forScanFileURL: scanURL
            )
            let decoded = try JSONDecoder().decode(
                CaptureMaturityReplaySummary.self,
                from: Data(contentsOf: writtenURL)
            )

            XCTAssertEqual(writtenURL, outputURL)
            XCTAssertEqual(decoded, summary)
        }
    }

    // 43. byte-deterministic repeated run
    func testRepeatedReplayProducesByteDeterministicJSON() throws {
        let runner = ScanSessionCaptureMaturityReplayRunner(
            configuration: makeConfiguration(targetSelectedFrameCount: 1)
        )
        let sessionURL = fixtureURL("pregate_ab_valid")
        let first = try runner.run(sessionFileURL: sessionURL)
        let second = try runner.run(sessionFileURL: sessionURL)

        XCTAssertEqual(
            try ScanSessionCaptureMaturityReplayExporter.encode(first.summary),
            try ScanSessionCaptureMaturityReplayExporter.encode(second.summary)
        )
    }

    // 44. real progress timestamp comparison when diagnostics are available
    func testAssociatedDiagnosticsProduceTimestampComparison() throws {
        try withTemporaryDirectory { directory in
            let diagnosticsURL = directory.appendingPathComponent(
                "SavedScan_diagnostics.json"
            )
            let diagnostics = """
            {
              "timeToAllMarkersSeenSeconds": 0.05,
              "timeToAllMarkersExportableSeconds": 0.15,
              "normalFinalizationStartedAtSeconds": 0.25,
              "events": [
                {
                  "name": "normal_finalization_started",
                  "timestampSeconds": 0.30
                },
                {
                  "name": "normal_finalization_export_triggered",
                  "timestampSeconds": 0.70
                }
              ]
            }
            """
            try Data(diagnostics.utf8).write(to: diagnosticsURL)
            let result = try ScanSessionCaptureMaturityReplayRunner(
                configuration: makeConfiguration(
                    minimumDistinctViewAngleDegrees: 0,
                    targetSelectedFrameCount: 2
                ),
                includeReferenceLikeMode: false
            ).run(
                sessionFileURL: fixtureURL("pregate_ab_valid"),
                diagnosticsFileURL: diagnosticsURL
            )
            let comparison = result.summary.actualProgressComparison

            XCTAssertEqual(comparison.comparisonStatus, "availableWithCaveats")
            XCTAssertEqual(
                comparison.sourceProgressArtifactFilename,
                "SavedScan_diagnostics.json"
            )
            XCTAssertEqual(comparison.actualAllMarkersSeenTimestamp, 0.05)
            XCTAssertEqual(comparison.actualAllMarkersExportableTimestamp, 0.15)
            XCTAssertEqual(comparison.actualUI100PercentTimestamp, 0.30)
            XCTAssertEqual(comparison.actualExportTriggeredTimestamp, 0.70)
            XCTAssertEqual(
                try XCTUnwrap(comparison.offlineStrictMaturityTimestamp),
                0.20,
                accuracy: 1e-9
            )
            XCTAssertEqual(
                try XCTUnwrap(comparison.ui100ToStrictMaturityDeltaSeconds),
                -0.10,
                accuracy: 1e-9
            )
            XCTAssertEqual(
                try XCTUnwrap(
                    comparison.exportableToStrictMaturityDeltaSeconds
                ),
                0.05,
                accuracy: 1e-9
            )
            XCTAssertEqual(comparison.strictMaturityReachedBeforeExport, true)
        }
    }

    // 45. unavailable comparison without diagnostics
    func testProgressComparisonIsUnavailableWithoutDiagnostics() throws {
        let result = try ScanSessionCaptureMaturityReplayRunner(
            configuration: makeConfiguration(targetSelectedFrameCount: 1)
        ).run(
            sessionFileURL: fixtureURL("pregate_ab_valid"),
            diagnosticsFileURL: nil
        )

        XCTAssertEqual(
            result.summary.actualProgressComparison.comparisonStatus,
            "unavailable"
        )
        XCTAssertNil(
            result.summary.actualProgressComparison
                .sourceProgressArtifactFilename
        )
    }

    func testReportFallbackProvidesPartialProgressComparisonWhenDiagnosticsAreMissing() throws {
        try withTemporaryDirectory { directory in
            let reportURL = directory.appendingPathComponent(
                "SavedScan_report.json"
            )
            let report = """
            {
              "normalFinalizationStartedAtSeconds": 0.24
            }
            """
            try Data(report.utf8).write(to: reportURL)

            let result = try ScanSessionCaptureMaturityReplayRunner(
                configuration: makeConfiguration(
                    minimumDistinctViewAngleDegrees: 0,
                    targetSelectedFrameCount: 2
                ),
                includeReferenceLikeMode: false
            ).run(
                sessionFileURL: fixtureURL("pregate_ab_valid"),
                diagnosticsFileURL: nil,
                reportFileURL: reportURL
            )
            let comparison = result.summary.actualProgressComparison

            XCTAssertEqual(comparison.comparisonStatus, "availableWithCaveats")
            XCTAssertEqual(
                comparison.sourceProgressArtifactFilename,
                "SavedScan_report.json"
            )
            XCTAssertNil(comparison.actualAllMarkersSeenTimestamp)
            XCTAssertNil(comparison.actualAllMarkersExportableTimestamp)
            XCTAssertEqual(comparison.actualUI100PercentTimestamp, 0.24)
            XCTAssertNil(comparison.actualExportTriggeredTimestamp)
            XCTAssertTrue(
                comparison.caveats.contains {
                    $0.contains("technical report is a partial fallback")
                }
            )
        }
    }

    // 46. marker multiplicity
    func testMarkerMultiplicityIsPreserved() {
        let summary = analyze(
            frames: [
                makeFrameInput(
                    index: 0,
                    poses: [
                        poseAtAngle(0, markerId: 0),
                        poseAtAngle(10, markerId: 0)
                    ]
                )
            ],
            expectedMarkerIds: [0],
            configuration: makeConfiguration(
                minimumDistinctViewAngleDegrees: 0,
                minimumValidObservationsPerMarker: 2,
                minimumDistinctViewsPerMarker: 2,
                targetSelectedFrameCount: 1
            )
        )
        let marker = marker(summary, 0)

        XCTAssertEqual(marker.rawObservationCount, 2)
        XCTAssertEqual(marker.validObservationCount, 2)
        XCTAssertEqual(marker.selectedObservationCount, 2)
        XCTAssertEqual(summary.validConnectivity.largestComponentObservationCount, 2)
    }

    // 47. physical frame/marker order
    func testReaderPreservesPhysicalFrameAndMarkerOrderForMaturityConsumer() throws {
        var frameIndices: [Int] = []
        var markerIds: [[Int]] = []

        _ = try ScanSessionSchemaV1Reader().readObservationFrames(
            from: fixtureURL("valid_completed")
        ) { frame in
            frameIndices.append(frame.frame.frameIndex)
            markerIds.append(
                frame.selectedMarkerObservations.map {
                    $0.observation.markerId
                }
            )
        }

        XCTAssertEqual(frameIndices, [0, 1, 2])
        XCTAssertEqual(markerIds, [[1, 0], [0, 1], [1, 0]])
    }

    // 48. invalid integrity
    func testInvalidSessionIntegrityPreventsMaturityReplay() {
        XCTAssertThrowsError(
            try ScanSessionCaptureMaturityReplayRunner().run(
                sessionFileURL: fixtureURL("duplicate_frame_index")
            )
        ) { error in
            guard let replayError = error as? ScanSessionReplayError,
                  case .nonIncreasingFrameIndex = replayError
            else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    // 49. physical/runtime artifacts remain untouched
    func testCaptureMaturityExportDoesNotOverwritePhysicalArtifacts() throws {
        let summary = try replaySummary()
        try withTemporaryDirectory { directory in
            let scanURL = directory.appendingPathComponent("SavedScan.stl")
            let protectedURLs = [
                scanURL,
                directory.appendingPathComponent("SavedScan_session.ndjson"),
                directory.appendingPathComponent("SavedScan_report.json"),
                directory.appendingPathComponent("SavedScan_diagnostics.json"),
                directory.appendingPathComponent("SavedScan_replay_summary.json"),
                directory.appendingPathComponent(
                    "SavedScan_pregate_ab_replay_summary.json"
                )
            ]
            let sentinel = Data("protected-runtime-artifact".utf8)
            for url in protectedURLs {
                try sentinel.write(to: url)
            }

            _ = try ScanSessionCaptureMaturityReplayExporter.write(
                summary,
                forScanFileURL: scanURL,
                protectedSourceURLs: Array(protectedURLs.dropFirst())
            )

            for url in protectedURLs {
                XCTAssertEqual(try Data(contentsOf: url), sentinel)
            }
        }
    }

    // 50. live progress artifacts remain unchanged
    func testOfflineReplayDoesNotAlterPersistedLiveProgressDiagnostics() throws {
        try withTemporaryDirectory { directory in
            let diagnosticsURL = directory.appendingPathComponent(
                "SavedScan_diagnostics.json"
            )
            let reportURL = directory.appendingPathComponent(
                "SavedScan_report.json"
            )
            let scanURL = directory.appendingPathComponent("SavedScan.stl")
            let diagnostics = Data(
                """
                {
                  "captureProgressPercent": 100.0,
                  "timeToAllMarkersSeenSeconds": 0.1,
                  "timeToAllMarkersExportableSeconds": 0.2,
                  "normalFinalizationStartedAtSeconds": 0.3
                }
                """.utf8
            )
            let report = Data(
                "{\"captureProgressPercent\":100.0}".utf8
            )
            try diagnostics.write(to: diagnosticsURL)
            try report.write(to: reportURL)
            try Data("production-stl".utf8).write(to: scanURL)

            let result = try ScanSessionCaptureMaturityReplayRunner(
                configuration: makeConfiguration(targetSelectedFrameCount: 1)
            ).run(
                sessionFileURL: fixtureURL("pregate_ab_valid"),
                diagnosticsFileURL: diagnosticsURL
            )
            _ = try ScanSessionCaptureMaturityReplayExporter.write(
                result.summary,
                forScanFileURL: scanURL,
                protectedSourceURLs: [diagnosticsURL, reportURL]
            )

            XCTAssertEqual(try Data(contentsOf: diagnosticsURL), diagnostics)
            XCTAssertEqual(try Data(contentsOf: reportURL), report)
        }
    }

    func testExternalPhysicalCaptureMaturityReplayWhenPathIsProvided() throws {
        guard let path = ProcessInfo.processInfo.environment[
            "DENTALSCANNER_CAPTURE_MATURITY_REPLAY_FILE"
        ], !path.isEmpty else {
            throw XCTSkip(
                "Set DENTALSCANNER_CAPTURE_MATURITY_REPLAY_FILE to run an external read-only maturity replay."
            )
        }

        let result = try ScanSessionCaptureMaturityReplayRunner().run(
            sessionFileURL: URL(fileURLWithPath: path)
        )
        XCTAssertGreaterThan(
            result.summary.all.strict.selection.framesProcessed,
            0
        )
        let data = try ScanSessionCaptureMaturityReplayExporter.encode(
            result.summary
        )
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        print("CAPTURE_MATURITY_REPLAY_SUMMARY\n\(json)")
    }

    private func makeConfiguration(
        minimumDistinctViewAngleDegrees: Double = 1.5,
        minimumValidObservationsPerMarker: Int = 1,
        minimumDistinctViewsPerMarker: Int = 1,
        targetSelectedFrameCount: Int = 1,
        minimumAngularSpreadDegrees: Double = 0,
        requiredCoveragePercent: Double = 0,
        azimuthBinCount: Int = 12,
        elevationBinCount: Int = 6,
        minimumObservationsPerFrame: Int = 1,
        requireExpectedMarkersConnected: Bool = true,
        requireSelectedFrameTargetForGlobalMaturity: Bool = true,
        timelineIntervalSeconds: Double = 0.5,
        strictSelectionStrategy: CaptureMaturitySelectionStrategy =
            .perMarkerObservation,
        referenceLikeSelectionStrategy: CaptureMaturitySelectionStrategy =
            .wholeFrameWhenAnyMarkerHasDistinctView,
        relaxationPolicy: CaptureMaturityRelaxationPolicy =
            CaptureMaturityRelaxationPolicy()
    ) -> CaptureMaturityReplayConfiguration {
        CaptureMaturityReplayConfiguration(
            minimumDistinctViewAngleDegrees:
                minimumDistinctViewAngleDegrees,
            minimumValidObservationsPerMarker:
                minimumValidObservationsPerMarker,
            minimumDistinctViewsPerMarker:
                minimumDistinctViewsPerMarker,
            targetSelectedFrameCount: targetSelectedFrameCount,
            minimumAngularSpreadDegrees: minimumAngularSpreadDegrees,
            requiredCoveragePercent: requiredCoveragePercent,
            azimuthBinCount: azimuthBinCount,
            elevationBinCount: elevationBinCount,
            minimumObservationsPerFrame: minimumObservationsPerFrame,
            requireExpectedMarkersConnected:
                requireExpectedMarkersConnected,
            requireSelectedFrameTargetForGlobalMaturity:
                requireSelectedFrameTargetForGlobalMaturity,
            timelineIntervalSeconds: timelineIntervalSeconds,
            strictSelectionStrategy: strictSelectionStrategy,
            referenceLikeSelectionStrategy:
                referenceLikeSelectionStrategy,
            relaxationPolicy: relaxationPolicy
        )
    }

    private func relaxationTestConfiguration()
        -> CaptureMaturityReplayConfiguration {
        makeConfiguration(
            minimumDistinctViewAngleDegrees: 2,
            minimumValidObservationsPerMarker: 10,
            minimumDistinctViewsPerMarker: 10,
            targetSelectedFrameCount: 4,
            minimumAngularSpreadDegrees: 20,
            relaxationPolicy: CaptureMaturityRelaxationPolicy(
                enabled: true,
                halfProgressFraction: 0.5,
                progressStepFraction: 0.25,
                minimumAngularSeparationFloorDegrees: 0.1,
                angularSeparationFactor: 0.8,
                angularSpreadRelaxationStepDegrees: 0.25,
                minimumAngularSpreadDegrees: 0.25
            )
        )
    }

    private func relaxationFrames()
        -> [ScanSessionReplayObservationFrameInput] {
        [0.0, 5.0, 10.0, 15.0].enumerated().map { index, angle in
            makeFrameInput(
                index: index,
                timestamp: 100 + Double(index) * 0.5,
                poses: [
                    poseAtAngle(angle, markerId: 0),
                    poseAtAngle(angle + 20, markerId: 1)
                ]
            )
        }
    }

    private func partiallyMatureTwoMarkerSummary()
        -> CaptureMaturityModeReplaySummary {
        analyze(
            frames: [
                makeFrameInput(
                    index: 0,
                    poses: [
                        poseAtAngle(0, markerId: 0),
                        poseAtAngle(0, markerId: 1)
                    ]
                ),
                makeFrameInput(
                    index: 1,
                    poses: [poseAtAngle(4, markerId: 0)]
                )
            ],
            expectedMarkerIds: [0, 1],
            configuration: makeConfiguration(
                minimumDistinctViewAngleDegrees: 2,
                minimumValidObservationsPerMarker: 1,
                minimumDistinctViewsPerMarker: 2,
                targetSelectedFrameCount: 2
            )
        )
    }

    private func analyze(
        frames: [ScanSessionReplayObservationFrameInput],
        expectedMarkerIds: [Int],
        policy: CaptureMaturityObservationPolicy = .all,
        mode: CaptureMaturityReplayMode = .strict,
        configuration: CaptureMaturityReplayConfiguration
    ) -> CaptureMaturityModeReplaySummary {
        let analyzer = CaptureMaturitySessionAnalyzer(
            metadata: makeMetadata(expectedMarkerIds: expectedMarkerIds),
            policy: policy,
            mode: mode,
            configuration: configuration
        )
        for frame in frames {
            analyzer.process(frame)
        }
        return analyzer.makeSummary()
    }

    private func makeMetadata(
        expectedMarkerIds: [Int]
    ) -> ScanSessionReplayCaptureMetadata {
        ScanSessionReplayCaptureMetadata(
            sessionIdentifier: "SYNTHETIC-MATURITY",
            schemaVersion: 1,
            captureStartedTimestamp: 100,
            deviceModelIdentifier: "synthetic-device",
            osVersion: "test",
            cameraProfileId: "synthetic-wide",
            cameraProfileName: "Synthetic Wide",
            markerProfile: MarkerProfile.singleArucoV1.rawValue,
            expectedPhysicalMarkerIds: expectedMarkerIds,
            featureFlags: [
                "preAccumulationGateBlocking": false,
                "scanSessionObservationCapture": true
            ],
            appVersion: "test",
            appBuildIdentifier: "1",
            appGitCommitHash: "synthetic-commit"
        )
    }

    private func makeFrameInput(
        index: Int,
        timestamp: Double? = nil,
        poses: [PoseResult],
        selectedPositions: [Int]? = nil,
        gateEvaluated: [Bool?]? = nil,
        gateWouldAccept: [Bool?]? = nil
    ) -> ScanSessionReplayObservationFrameInput {
        let observations = poses.enumerated().map { position, pose in
            makeObservation(
                pose,
                gateEvaluated: value(
                    gateEvaluated,
                    at: position,
                    fallback: true
                ),
                gateWouldAccept: value(
                    gateWouldAccept,
                    at: position,
                    fallback: true
                )
            )
        }
        let frame = FrameObservation(
            frameIndex: index,
            timestampSeconds: timestamp ?? (100 + Double(index) * 0.1),
            frameWidth: 1920,
            frameHeight: 1080,
            intrinsicsAvailable: true,
            intrinsicFx: 1_000,
            intrinsicFy: 1_000,
            intrinsicCx: 960,
            intrinsicCy: 540,
            cameraProfileId: "synthetic-wide",
            cameraProfileName: "Synthetic Wide",
            markerObservations: observations
        )
        let positions = selectedPositions ?? Array(poses.indices)
        let selected = positions.map { position in
            ScanSessionReplayMarkerObservationInput(
                markerPosition: position,
                observation: observations[position],
                poseResult: poses[position]
            )
        }
        return ScanSessionReplayObservationFrameInput(
            frame: frame,
            selectedMarkerObservations: selected
        )
    }

    private func makeObservation(
        _ pose: PoseResult,
        gateEvaluated: Bool?,
        gateWouldAccept: Bool?
    ) -> MarkerFrameObservation {
        MarkerFrameObservation(
            markerId: pose.markerId,
            markerSource: "singleArucoV1",
            markerSourceTagId: nil,
            markerProfileId: pose.markerProfile.rawValue,
            imageCorners: [
                ObservationPoint2D(x: 10, y: 10),
                ObservationPoint2D(x: 20, y: 10),
                ObservationPoint2D(x: 20, y: 20),
                ObservationPoint2D(x: 10, y: 20)
            ],
            objectPoints: [
                ObservationPoint3D(x: -5, y: 5, z: 0),
                ObservationPoint3D(x: 5, y: 5, z: 0),
                ObservationPoint3D(x: 5, y: -5, z: 0),
                ObservationPoint3D(x: -5, y: -5, z: 0)
            ],
            rotationVector: point(pose.rotationVector),
            rotationMatrixRows: matrixRows(pose.rotationMatrix),
            translationVector: point(pose.translationVector),
            reprojectionError: pose.reprojectionError,
            distanceMm: pose.distanceMm,
            markerAreaPixels: pose.markerAreaPixels,
            usedPointCount: pose.usedPointCount,
            detectedTopTagId: pose.detectedTopTagId,
            detectedBottomTagId: pose.detectedBottomTagId,
            frameMaskState: "inside",
            insideFrameMask: true,
            frameMaskViolation: nil,
            focusQualityState: "stable",
            focusVariance: nil,
            motionQualityState: "stable",
            motionMagnitude: 0.01,
            poseFinite: true,
            intrinsicsFinite: true,
            observationValid: true,
            preAccumulationGateEvaluated: gateEvaluated,
            preAccumulationGateWouldAccept: gateWouldAccept,
            preAccumulationGateRejectReason:
                gateWouldAccept == false ? "frameMask" : nil
        )
    }

    private func makePose(
        markerId: Int,
        cameraCenterInMarker: SIMD3<Double>,
        rotationVector: SIMD3<Double> = SIMD3(0.13, -0.07, 0.11),
        rotationMatrix: simd_double3x3? = nil
    ) -> PoseResult {
        let matrix = rotationMatrix ??
            PoseMath.rotationMatrix(fromRodrigues: rotationVector)
        let translation = -(matrix * cameraCenterInMarker)
        return PoseResult(
            markerId: markerId,
            rotationVector: rotationVector,
            rotationMatrix: matrix,
            translationVector: translation,
            distanceMm: simd_length(translation),
            reprojectionError: 0.2,
            markerAreaPixels: 500,
            usedPointCount: 4
        )
    }

    private func poseAtAngle(
        _ degrees: Double,
        markerId: Int
    ) -> PoseResult {
        makePose(
            markerId: markerId,
            cameraCenterInMarker: direction(atDegrees: degrees) * 100
        )
    }

    private func direction(atDegrees degrees: Double) -> SIMD3<Double> {
        let radians = degrees * Double.pi / 180
        return SIMD3(cos(radians), sin(radians), 0)
    }

    private func viewpoint(
        for pose: PoseResult
    ) throws -> MarkerViewpointObservation {
        try CaptureMaturityViewpointMath.viewpoint(
            frameIndex: 7,
            timestampSeconds: 123.4,
            pose: pose,
            configuration: makeConfiguration()
        ).get()
    }

    private func assertViewpointFailure(
        _ pose: PoseResult,
        reason expectedReason: CaptureMaturityObservationRejectReason,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        switch CaptureMaturityViewpointMath.viewpoint(
            frameIndex: 0,
            timestampSeconds: 100,
            pose: pose,
            configuration: makeConfiguration()
        ) {
        case .success:
            XCTFail("Expected viewpoint rejection", file: file, line: line)
        case let .failure(reason):
            XCTAssertEqual(
                reason.rawValue,
                expectedReason.rawValue,
                file: file,
                line: line
            )
        }
    }

    private func marker(
        _ summary: CaptureMaturityModeReplaySummary,
        _ markerId: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> MarkerCaptureMaturitySnapshot {
        guard let marker = summary.markerMaturity.first(where: {
            $0.markerId == markerId
        }) else {
            XCTFail("Missing marker \(markerId)", file: file, line: line)
            return summary.markerMaturity[0]
        }
        return marker
    }

    private func replaySummary() throws -> CaptureMaturityReplaySummary {
        try ScanSessionCaptureMaturityReplayRunner(
            configuration: makeConfiguration(targetSelectedFrameCount: 1)
        ).run(sessionFileURL: fixtureURL("pregate_ab_valid")).summary
    }

    private func fixtureURL(
        _ name: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> URL {
        let bundle = Bundle(for: Self.self)
        let url = bundle.url(forResource: name, withExtension: "ndjson") ??
            bundle.url(
                forResource: name,
                withExtension: "ndjson",
                subdirectory: "Fixtures"
            )
        guard let url else {
            XCTFail("Missing fixture \(name).ndjson", file: file, line: line)
            return URL(
                fileURLWithPath: "/missing-fixture/\(name).ndjson"
            )
        }
        return url
    }

    private func withTemporaryDirectory(
        _ body: (URL) throws -> Void
    ) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }

    private func point(_ vector: SIMD3<Double>) -> ObservationPoint3D {
        ObservationPoint3D(x: vector.x, y: vector.y, z: vector.z)
    }

    private func matrixRows(
        _ matrix: simd_double3x3
    ) -> [ObservationPoint3D] {
        [
            ObservationPoint3D(
                x: matrix.columns.0.x,
                y: matrix.columns.1.x,
                z: matrix.columns.2.x
            ),
            ObservationPoint3D(
                x: matrix.columns.0.y,
                y: matrix.columns.1.y,
                z: matrix.columns.2.y
            ),
            ObservationPoint3D(
                x: matrix.columns.0.z,
                y: matrix.columns.1.z,
                z: matrix.columns.2.z
            )
        ]
    }

    private func assertVector(
        _ actual: SIMD3<Double>,
        equals expected: SIMD3<Double>,
        accuracy: Double,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.x, expected.x, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.y, expected.y, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.z, expected.z, accuracy: accuracy, file: file, line: line)
    }

    private func assertBinsSorted(
        _ bins: [CaptureMaturityCoverageBin],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let indices = bins.map { ($0.elevationIndex, $0.azimuthIndex) }
        let sorted = indices.sorted {
            $0.0 == $1.0 ? $0.1 < $1.1 : $0.0 < $1.0
        }
        XCTAssertEqual(
            indices.map { [$0.0, $0.1] },
            sorted.map { [$0.0, $0.1] },
            file: file,
            line: line
        )
    }

    private func value<T>(
        _ values: [T?]?,
        at index: Int,
        fallback: T?
    ) -> T? {
        guard let values, values.indices.contains(index) else {
            return fallback
        }
        return values[index]
    }
}
