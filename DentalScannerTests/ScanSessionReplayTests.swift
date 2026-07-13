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
        var accumulatorIdentifiers: [ObjectIdentifier] = []
        let runner = ScanSessionDeterministicReplayRunner(
            accumulatorFactory: {
                let accumulator = MultiFramePoseAccumulator()
                accumulatorIdentifiers.append(ObjectIdentifier(accumulator))
                return accumulator
            }
        )

        let result = try runner.verifyDeterminism(
            sessionFileURL: fixtureURL("valid_completed")
        )

        XCTAssertEqual(accumulatorIdentifiers.count, 2)
        XCTAssertNotEqual(accumulatorIdentifiers[0], accumulatorIdentifiers[1])
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
}
