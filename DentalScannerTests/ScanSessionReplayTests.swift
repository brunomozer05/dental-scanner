import Foundation
import simd
import XCTest
@testable import DentalScanner

final class ScanSessionReplayTests: XCTestCase {
    func testValidReaderPreservesPhysicalFrameAndMarkerOrder() throws {
        var frameIndices: [Int] = []
        var markerIdsByFrame: [[Int]] = []
        var firstPersistedMatrix: simd_double3x3?

        let summary = try ScanSessionSchemaV1Reader().read(
            from: fixtureURL("valid_completed")
        ) { frame in
            frameIndices.append(frame.frameIndex)
            markerIdsByFrame.append(frame.poseResults.map(\.markerId))
            if firstPersistedMatrix == nil {
                firstPersistedMatrix = frame.poseResults.first?.rotationMatrix
            }
        }

        XCTAssertEqual(frameIndices, [0, 1, 2])
        XCTAssertEqual(markerIdsByFrame, [[1, 0], [0, 1], [1, 0]])
        XCTAssertEqual(summary.framesRead, 3)
        XCTAssertEqual(summary.markerObservationsReconstructed, 6)
        XCTAssertEqual(summary.firstFrameIndex, 0)
        XCTAssertEqual(summary.lastFrameIndex, 2)

        let matrix = try XCTUnwrap(firstPersistedMatrix)
        XCTAssertEqual(PoseMath.matrixElement(matrix, row: 0, column: 0), 0.9887710779360422)
        XCTAssertEqual(PoseMath.matrixElement(matrix, row: 0, column: 1), -0.14943813247359922)
        XCTAssertEqual(PoseMath.matrixElement(matrix, row: 1, column: 0), 0.14943813247359922)
        XCTAssertEqual(PoseMath.matrixElement(matrix, row: 1, column: 1), 0.9887710779360422)
    }

    func testReplayTwiceUsesFreshAccumulatorsAndIsDeterministic() throws {
        var accumulators: [MultiFramePoseAccumulator] = []
        let runner = ScanSessionDeterministicReplayRunner(
            accumulatorFactory: {
                let accumulator = MultiFramePoseAccumulator()
                accumulators.append(accumulator)
                return accumulator
            }
        )

        let result = try runner.verifyDeterminism(
            sessionFileURL: fixtureURL("valid_completed")
        )

        XCTAssertEqual(accumulators.count, 2)
        XCTAssertFalse(accumulators[0] === accumulators[1])
        XCTAssertEqual(result.summary.framesReplayed, 3)
        XCTAssertEqual(result.summary.markerObservationsReconstructed, 6)
        XCTAssertEqual(result.summary.finalMarkerIds, [0, 1])
        XCTAssertEqual(result.summary.determinism.comparedMarkerCount, 2)
        XCTAssertEqual(result.summary.determinism.meanTranslationDeltaMm, 0)
        XCTAssertEqual(result.summary.determinism.maxTranslationDeltaMm, 0)
        XCTAssertEqual(result.summary.determinism.meanRotationDeltaDegrees, 0)
        XCTAssertEqual(result.summary.determinism.maxRotationDeltaDegrees, 0)
        XCTAssertTrue(result.summary.determinism.replayDeterministic)
        XCTAssertFalse(result.summary.replayUsesRandomness)
        XCTAssertEqual(result.summary.liveVsReplayDirectComparison, "unavailable")
        XCTAssertTrue(
            result.summary.provenanceCaveats.contains(
                "capture appGitCommitHash is unavailable"
            )
        )
    }

    func testReplaySummaryExporterEncodesRunnerSummaryWithoutModifyingSession() throws {
        let sessionURL = fixtureURL("valid_completed")
        let sessionDataBeforeReplay = try Data(contentsOf: sessionURL)
        let result = try ScanSessionDeterministicReplayRunner().verifyDeterminism(
            sessionFileURL: sessionURL
        )
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let scanURL = temporaryDirectory.appendingPathComponent("Scan_2026-07-12_20-49.stl")
        let summaryURL = try ScanSessionReplaySummaryExporter.write(
            result.summary,
            forScanFileURL: scanURL
        )

        XCTAssertEqual(
            summaryURL.lastPathComponent,
            "Scan_2026-07-12_20-49_replay_summary.json"
        )
        let encodedSummary = try Data(contentsOf: summaryURL)
        let decodedSummary = try JSONDecoder().decode(
            ScanSessionDeterministicReplaySummary.self,
            from: encodedSummary
        )
        XCTAssertEqual(decodedSummary, result.summary)
        XCTAssertEqual(try Data(contentsOf: sessionURL), sessionDataBeforeReplay)
    }

    func testReplayPoliciesPreserveFramesAndSelectPersistedAcceptedObservations() throws {
        let sessionURL = fixtureURL("pregate_ab_valid")
        var allMarkerIds: [[Int]] = []
        let allSummary = try ScanSessionSchemaV1Reader().read(
            from: sessionURL,
            observationPolicy: .allPersisted
        ) { frame in
            allMarkerIds.append(frame.poseResults.map(\.markerId))
        }
        var filteredFrameIndices: [Int] = []
        var filteredMarkerIds: [[Int]] = []
        let filteredSummary = try ScanSessionSchemaV1Reader().read(
            from: sessionURL,
            observationPolicy: .preAccumulationGateAcceptedOnly
        ) { frame in
            filteredFrameIndices.append(frame.frameIndex)
            filteredMarkerIds.append(frame.poseResults.map(\.markerId))
        }

        XCTAssertEqual(allMarkerIds, [[0, 1], [1, 0]])
        XCTAssertEqual(allSummary.markerObservationsReconstructed, 4)
        XCTAssertEqual(filteredFrameIndices, [0, 1])
        XCTAssertEqual(filteredMarkerIds, [[], [1, 0]])
        XCTAssertEqual(filteredSummary.markerObservationsReconstructed, 2)
        let selection = filteredSummary.selectionDiagnostics
        XCTAssertEqual(selection.rawMarkerObservationCount, 4)
        XCTAssertEqual(selection.acceptedMarkerObservationCount, 2)
        XCTAssertEqual(selection.rejectedMarkerObservationCount, 2)
        XCTAssertEqual(selection.framesWithAnyRawObservation, 2)
        XCTAssertEqual(selection.framesWithAnyAcceptedObservation, 1)
        XCTAssertEqual(selection.framesWithZeroAcceptedObservations, 1)
        XCTAssertEqual(selection.perMarker.map(\.markerId), [0, 1])
        XCTAssertEqual(selection.perMarker.map(\.rawCount), [2, 2])
        XCTAssertEqual(selection.perMarker.map(\.acceptedCount), [1, 1])
        XCTAssertEqual(selection.perMarker.map(\.rejectedCount), [1, 1])
        XCTAssertEqual(selection.rejectReasonCounts["frameMask"], 1)
        XCTAssertEqual(selection.rejectReasonCounts["highMotion"], 1)
    }

    func testFilteredReplayRequiresPersistedGateEvaluation() {
        XCTAssertThrowsError(
            try ScanSessionSchemaV1Reader().read(
                from: fixtureURL("valid_completed"),
                observationPolicy: .preAccumulationGateAcceptedOnly,
                onFrame: { _ in }
            )
        ) { error in
            guard let replayError = error as? ScanSessionReplayError,
                  case let .missingGateAnnotation(_, frameIndex, markerId, reason) = replayError
            else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(frameIndex, 0)
            XCTAssertEqual(markerId, 1)
            XCTAssertTrue(reason.contains("Evaluated"))
        }
    }

    func testFilteredReplayRequiresPersistedGateDecision() {
        XCTAssertThrowsError(
            try ScanSessionSchemaV1Reader().read(
                from: fixtureURL("pregate_missing_decision"),
                observationPolicy: .preAccumulationGateAcceptedOnly,
                onFrame: { _ in }
            )
        ) { error in
            guard let replayError = error as? ScanSessionReplayError,
                  case let .missingGateAnnotation(_, frameIndex, markerId, reason) = replayError
            else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(frameIndex, 0)
            XCTAssertEqual(markerId, 0)
            XCTAssertTrue(reason.contains("WouldAccept"))
        }
    }

    func testABReplayUsesFourFreshAccumulatorsAndReportsSelection() throws {
        var accumulators: [MultiFramePoseAccumulator] = []
        let runner = ScanSessionPreAccumulationGateABReplayRunner(
            accumulatorFactory: {
                let accumulator = MultiFramePoseAccumulator()
                accumulators.append(accumulator)
                return accumulator
            }
        )
        let result = try runner.run(sessionFileURL: fixtureURL("pregate_ab_valid"))

        XCTAssertEqual(accumulators.count, 4)
        XCTAssertEqual(Set(accumulators.map { ObjectIdentifier($0) }).count, 4)
        XCTAssertTrue(result.summary.allDeterminism.replayDeterministic)
        XCTAssertTrue(result.summary.filteredDeterminism.replayDeterministic)
        XCTAssertEqual(result.summary.baselineReplayPolicy, "allPersisted")
        XCTAssertEqual(
            result.summary.filteredReplayPolicy,
            "preAccumulationGateAcceptedOnly"
        )
        XCTAssertEqual(result.summary.framesReplayed, 2)
        XCTAssertEqual(result.summary.selectionDiagnostics.rawMarkerObservationCount, 4)
        XCTAssertEqual(result.summary.selectionDiagnostics.acceptedMarkerObservationCount, 2)
        XCTAssertEqual(result.summary.selectionDiagnostics.rejectedMarkerObservationCount, 2)
        XCTAssertEqual(result.summary.livePreAccumulationBlockingEnabledAtCapture, false)
        XCTAssertTrue(result.summary.offlineFilteredReplayUsesPersistedDecisions)
    }

    func testRejectedObservationWithoutReasonIsReported() throws {
        let result = try ScanSessionPreAccumulationGateABReplayRunner().run(
            sessionFileURL: fixtureURL("pregate_rejected_missing_reason")
        )
        XCTAssertEqual(result.summary.selectionDiagnostics.rejectedWithoutReasonCount, 1)
        XCTAssertEqual(result.summary.integrityResult, "validWithGateAnnotationInconsistencies")
    }

    func testPairwiseGeometryComparisonIsGlobalFrameInvariant() {
        let marker0 = makePose(
            markerId: 0,
            rotationVector: SIMD3(0.1, 0.2, 0.05),
            translation: SIMD3(1, 2, 3)
        )
        let marker1 = makePose(
            markerId: 1,
            rotationVector: SIMD3(-0.15, 0.05, 0.3),
            translation: SIMD3(11, 4, 8)
        )
        let globalRotation = PoseMath.rotationMatrix(
            fromRodrigues: SIMD3(0.2, -0.1, 0.4)
        )
        let globalTranslation = SIMD3<Double>(50, -20, 7)
        let transformed = [marker0, marker1].map { pose in
            makePose(
                markerId: pose.markerId,
                rotationMatrix: globalRotation * pose.rotationMatrix,
                translation: globalRotation * pose.translationVector + globalTranslation
            )
        }

        let comparison = ScanSessionReplayPairwiseGeometryComparator.compare(
            allPoses: [marker0, marker1],
            filteredPoses: transformed
        )
        XCTAssertEqual(comparison.comparedPairCount, 1)
        XCTAssertEqual(comparison.pairs[0].absoluteDistanceDeltaMm, 0, accuracy: 1e-9)
        XCTAssertEqual(comparison.pairs[0].relativeRotationDeltaDegrees, 0, accuracy: 1e-6)
    }

    func testPairwiseGeometryComparisonReportsChangedGeometry() {
        let all = [
            makePose(markerId: 0, rotationVector: SIMD3(0, 0, 0.1), translation: .zero),
            makePose(markerId: 1, rotationVector: SIMD3(0, 0, 0.2), translation: SIMD3(10, 0, 0))
        ]
        let filtered = [
            makePose(markerId: 0, rotationVector: SIMD3(0, 0, 0.1), translation: .zero),
            makePose(markerId: 1, rotationVector: SIMD3(0, 0, 0.3), translation: SIMD3(12, 0, 0))
        ]

        let comparison = ScanSessionReplayPairwiseGeometryComparator.compare(
            allPoses: all,
            filteredPoses: filtered
        )
        XCTAssertEqual(comparison.pairs[0].signedDistanceDeltaMm, 2, accuracy: 1e-9)
        XCTAssertEqual(comparison.pairs[0].absoluteDistanceDeltaMm, 2, accuracy: 1e-9)
        XCTAssertGreaterThan(comparison.pairs[0].relativeRotationDeltaDegrees, 5)
    }

    func testABSummaryExporterUsesDedicatedFilenameAndEncodesRunnerSummary() throws {
        let result = try ScanSessionPreAccumulationGateABReplayRunner().run(
            sessionFileURL: fixtureURL("pregate_ab_valid")
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let scanURL = directory.appendingPathComponent("Scan_2026-07-12_23-30.stl")

        let outputURL = try ScanSessionReplaySummaryExporter.write(
            result.summary,
            forScanFileURL: scanURL
        )
        XCTAssertEqual(
            outputURL.lastPathComponent,
            "Scan_2026-07-12_23-30_pregate_ab_replay_summary.json"
        )
        let decoded = try JSONDecoder().decode(
            ScanSessionPreAccumulationGateABReplaySummary.self,
            from: Data(contentsOf: outputURL)
        )
        XCTAssertEqual(decoded, result.summary)
    }

    func testUnsupportedSchemaIsRejected() {
        assertReplayError("unsupported_schema") { error in
            guard case .unsupportedSchemaVersion(_, 2) = error else { return false }
            return true
        }
    }

    func testMalformedJSONIsRejected() {
        assertReplayError("malformed_record") { error in
            guard case .malformedJSON = error else { return false }
            return true
        }
    }

    func testMissingHeaderIsRejected() {
        assertReplayError("missing_header") { $0 == .missingHeader }
    }

    func testMissingFooterIsRejected() {
        assertReplayError("missing_footer") { $0 == .missingFooter }
    }

    func testFrameBeforeHeaderIsRejected() {
        assertReplayError("frame_before_header") { error in
            guard case .frameBeforeHeader = error else { return false }
            return true
        }
    }

    func testRecordAfterFooterIsRejected() {
        assertReplayError("record_after_footer") { error in
            guard case .recordAfterFooter = error else { return false }
            return true
        }
    }

    func testDuplicateFrameIndexIsRejected() {
        assertReplayError("duplicate_frame_index") { error in
            guard case let .nonIncreasingFrameIndex(_, previous, current) = error else {
                return false
            }
            return previous == 0 && current == 0
        }
    }

    func testMalformedRotationMatrixRowsAreRejected() {
        assertReplayError("malformed_rotation_matrix") { error in
            guard case let .invalidPose(_, _, _, reason) = error else { return false }
            return reason.contains("exactly three rows")
        }
    }

    func testNonFiniteReplayCriticalPoseIsRejected() {
        assertReplayError("nonfinite_pose") { error in
            guard case let .invalidPose(_, _, _, reason) = error else { return false }
            return reason.contains("rotationVector is non-finite")
        }
    }

    func testIncompleteSessionRequiresExplicitOptIn() throws {
        assertReplayError("incomplete_session") { $0 == .incompleteSession }

        let summary = try ScanSessionSchemaV1Reader().read(
            from: fixtureURL("incomplete_session"),
            options: ScanSessionReplayOptions(requireCompletedSession: false),
            onFrame: { _ in }
        )
        XCTAssertFalse(summary.footerCompleted)
        XCTAssertEqual(summary.framesRead, 0)
    }

    func testExternalPhysicalSessionReplayWhenPathIsProvided() throws {
        guard let path = ProcessInfo.processInfo.environment["DENTALSCANNER_REPLAY_FILE"],
              !path.isEmpty
        else {
            throw XCTSkip("Set DENTALSCANNER_REPLAY_FILE to run an external read-only replay.")
        }

        let result = try ScanSessionDeterministicReplayRunner().verifyDeterminism(
            sessionFileURL: URL(fileURLWithPath: path)
        )
        XCTAssertTrue(result.summary.determinism.replayDeterministic)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(result.summary)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        print("SPEC18B_REPLAY_SUMMARY\n\(json)")
    }

    private func assertReplayError(
        _ fixtureName: String,
        matches: (ScanSessionReplayError) -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try ScanSessionSchemaV1Reader().read(
                from: fixtureURL(fixtureName),
                onFrame: { _ in }
            ),
            file: file,
            line: line
        ) { error in
            guard let replayError = error as? ScanSessionReplayError else {
                return XCTFail("Unexpected error type: \(error)", file: file, line: line)
            }
            XCTAssertTrue(matches(replayError), "Unexpected error: \(replayError)", file: file, line: line)
        }
    }

    private func fixtureURL(
        _ name: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> URL {
        let bundle = Bundle(for: Self.self)
        let url = bundle.url(forResource: name, withExtension: "ndjson") ??
            bundle.url(forResource: name, withExtension: "ndjson", subdirectory: "Fixtures")
        guard let url else {
            XCTFail("Missing fixture \(name).ndjson", file: file, line: line)
            return URL(fileURLWithPath: "/missing-fixture/\(name).ndjson")
        }
        return url
    }

    private func makePose(
        markerId: Int,
        rotationVector: SIMD3<Double> = .zero,
        rotationMatrix: simd_double3x3? = nil,
        translation: SIMD3<Double>
    ) -> PoseResult {
        PoseResult(
            markerId: markerId,
            rotationVector: rotationVector,
            rotationMatrix: rotationMatrix,
            translationVector: translation,
            distanceMm: simd_length(translation),
            reprojectionError: 0.2,
            markerAreaPixels: 500,
            usedPointCount: 4
        )
    }
}
