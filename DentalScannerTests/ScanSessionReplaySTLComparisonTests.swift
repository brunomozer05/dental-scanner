import Foundation
import simd
import XCTest
@testable import DentalScanner

final class ScanSessionReplaySTLComparisonTests: XCTestCase {
    func testSelectsLowestCommonMarkerAsDeterministicBase() throws {
        let result = try DiagnosticMarkerPoseNormalizer.normalize(
            allPoses: [pose(4), pose(1), pose(3)],
            filteredPoses: [pose(3), pose(4), pose(2)]
        )

        XCTAssertEqual(result.baseMarkerId, 3)
        XCTAssertEqual(result.commonMarkerIds, [3, 4])
    }

    func testFailsWhenPoseSetsHaveNoCommonMarker() {
        XCTAssertThrowsError(
            try DiagnosticMarkerPoseNormalizer.normalize(
                allPoses: [pose(0), pose(1)],
                filteredPoses: [pose(2), pose(3)]
            )
        ) { error in
            XCTAssertEqual(error as? DiagnosticMarkerAssemblyError, .noCommonMarker)
        }
    }

    func testRebaseMakesBaseMarkerExactlyIdentity() throws {
        let poses = nontrivialPoses()
        let rebased = try DiagnosticMarkerPoseNormalizer.rebase(
            poses: poses,
            to: 1,
            policy: "TEST"
        )
        let base = try XCTUnwrap(rebased.first { $0.markerId == 1 })

        assertIdentity(base.rotationMatrix)
        XCTAssertEqual(base.translationVector, .zero)
        XCTAssertEqual(base.rotationVector, .zero)
        XCTAssertEqual(base.distanceMm, 0)
    }

    func testRebasePreservesAllPairwiseDistances() throws {
        let original = nontrivialPoses()
        let rebased = try DiagnosticMarkerPoseNormalizer.rebase(
            poses: original,
            to: 1,
            policy: "TEST"
        )

        for pair in markerPairs(original.map(\.markerId)) {
            XCTAssertEqual(
                relativeDistance(pair, in: original),
                relativeDistance(pair, in: rebased),
                accuracy: 1e-9
            )
        }
    }

    func testRebasePreservesAllPairwiseRotations() throws {
        let original = nontrivialPoses()
        let rebased = try DiagnosticMarkerPoseNormalizer.rebase(
            poses: original,
            to: 1,
            policy: "TEST"
        )

        for pair in markerPairs(original.map(\.markerId)) {
            let originalRelative = relativeRotation(pair, in: original)
            let rebasedRelative = relativeRotation(pair, in: rebased)
            XCTAssertEqual(
                rotationDeltaDegrees(originalRelative, rebasedRelative),
                0,
                accuracy: 1e-6
            )
        }
    }

    func testNormalizationIsInvariantToArbitraryGlobalTransform() throws {
        let original = nontrivialPoses()
        let globalRotation = PoseMath.rotationMatrix(
            fromRodrigues: SIMD3(0.31, -0.17, 0.23)
        )
        let globalTranslation = SIMD3<Double>(91, -34, 12)
        let transformed = original.map {
            applyGlobalTransform(
                to: $0,
                rotation: globalRotation,
                translation: globalTranslation
            )
        }

        let first = try DiagnosticMarkerPoseNormalizer.rebase(
            poses: original,
            to: 1,
            policy: "FIRST"
        )
        let second = try DiagnosticMarkerPoseNormalizer.rebase(
            poses: transformed,
            to: 1,
            policy: "SECOND"
        )
        assertPoseGeometryEqual(first, second)
    }

    func testAllAndFilteredUseSameCanonicalFrame() throws {
        let all = nontrivialPoses()
        let globalRotation = PoseMath.rotationMatrix(
            fromRodrigues: SIMD3(-0.2, 0.1, 0.35)
        )
        let filtered = all.map {
            applyGlobalTransform(
                to: $0,
                rotation: globalRotation,
                translation: SIMD3(44, 7, -9)
            )
        }
        let normalized = try DiagnosticMarkerPoseNormalizer.normalize(
            allPoses: all,
            filteredPoses: filtered
        )

        let allBase = try XCTUnwrap(
            normalized.allPoses.first { $0.markerId == normalized.baseMarkerId }
        )
        let filteredBase = try XCTUnwrap(
            normalized.filteredPoses.first { $0.markerId == normalized.baseMarkerId }
        )
        assertIdentity(allBase.rotationMatrix)
        assertIdentity(filteredBase.rotationMatrix)
        XCTAssertEqual(allBase.translationVector, .zero)
        XCTAssertEqual(filteredBase.translationVector, .zero)
        assertPoseGeometryEqual(normalized.allPoses, normalized.filteredPoses)
    }

    func testMarkerIdsProfilesAndModelContextRemainCorrect() throws {
        var receivedProfile: MarkerProfile?
        var receivedMarkerIds: [Int] = []
        let markerExporter = DiagnosticMarkerAssemblySTLExporter {
            profile, poses, _ in
            receivedProfile = profile
            receivedMarkerIds = poses.map(\.markerId)
            return "solid test\nendsolid test\n"
        }
        let input = makeInput(
            allPoses: nontrivialPoses(profile: .dualArucoV2),
            filteredPoses: nontrivialPoses(profile: .dualArucoV2)
        )

        _ = try withTemporaryScanFiles { scanURL, sessionURL in
            try ScanSessionReplaySTLComparisonExporter(
                markerAssemblyExporter: markerExporter
            ).export(
                input: input,
                sourceSessionFileURL: sessionURL,
                sourceScanFileURL: scanURL
            )
        }

        XCTAssertEqual(receivedProfile, .dualArucoV2)
        XCTAssertEqual(receivedMarkerIds, nontrivialPoses().map(\.markerId))
    }

    func testAllSTLFilenameUsesDedicatedSuffix() {
        let scanURL = URL(fileURLWithPath: "/tmp/Scan_2026-07-16_10-30.stl")
        XCTAssertEqual(
            ScanSessionReplaySTLComparisonExporter
                .allSTLOutputURL(forScanFileURL: scanURL)
                .lastPathComponent,
            "Scan_2026-07-16_10-30_replay_all.stl"
        )
    }

    func testFilteredSTLFilenameUsesDedicatedSuffix() {
        let scanURL = URL(fileURLWithPath: "/tmp/Scan_2026-07-16_10-30.stl")
        XCTAssertEqual(
            ScanSessionReplaySTLComparisonExporter
                .filteredSTLOutputURL(forScanFileURL: scanURL)
                .lastPathComponent,
            "Scan_2026-07-16_10-30_replay_pregate_filtered.stl"
        )
    }

    func testManifestFilenameAndRequiredFieldsAreCorrect() throws {
        let artifacts = try exportWithDeterministicGenerator(
            input: makeInput(
                allPoses: nontrivialPoses(),
                filteredPoses: Array(changedFilteredPoses().prefix(2))
            )
        )
        let manifest = artifacts.manifest

        XCTAssertEqual(
            artifacts.manifestURL.lastPathComponent,
            "SavedScan_replay_stl_comparison.json"
        )
        XCTAssertEqual(manifest.schemaVersion, 1)
        XCTAssertEqual(manifest.sourceSessionSchemaVersion, 1)
        XCTAssertEqual(manifest.sessionIdentifier, "test-session")
        XCTAssertEqual(manifest.sourceSessionFilename, "SavedScan_session.ndjson")
        XCTAssertEqual(manifest.sourceScanFilename, "SavedScan.stl")
        XCTAssertEqual(manifest.allReplayPolicy, "allPersisted")
        XCTAssertEqual(manifest.filteredReplayPolicy, "preAccumulationGateAcceptedOnly")
        XCTAssertEqual(manifest.comparisonBaseMarkerId, 1)
        XCTAssertEqual(manifest.allMarkerIds, [1, 2, 3])
        XCTAssertEqual(manifest.filteredMarkerIds, [1, 2])
        XCTAssertEqual(manifest.commonMarkerIds, [1, 2])
        XCTAssertEqual(manifest.missingFromAll, [])
        XCTAssertEqual(manifest.missingFromFiltered, [3])
        XCTAssertEqual(manifest.markerProfile, "singleArucoV1")
        XCTAssertEqual(manifest.referenceModelFilename, "marker_reference.stl")
        XCTAssertTrue(manifest.allDeterministic)
        XCTAssertTrue(manifest.filteredDeterministic)
        XCTAssertTrue(manifest.offlineFilteredReplayUsesPersistedDecisions)
        XCTAssertEqual(manifest.livePreAccumulationBlockingEnabledAtCapture, false)
        XCTAssertEqual(manifest.integrityResult, "valid")
        XCTAssertGreaterThan(manifest.allSTLFileSizeBytes, 0)
        XCTAssertGreaterThan(manifest.filteredSTLFileSizeBytes, 0)
    }

    func testManifestJSONUsesDeterministicSortedKeys() throws {
        let artifacts = try exportWithDeterministicGenerator(
            input: makeInput(
                allPoses: nontrivialPoses(),
                filteredPoses: changedFilteredPoses()
            )
        )
        let first = try ScanSessionReplaySTLComparisonExporter.encode(
            artifacts.manifest
        )
        let second = try ScanSessionReplaySTLComparisonExporter.encode(
            artifacts.manifest
        )
        XCTAssertEqual(first, second)

        let json = try XCTUnwrap(String(data: first, encoding: .utf8))
        let allKey = try XCTUnwrap(json.range(of: "\"allDeterministic\""))
        let schemaKey = try XCTUnwrap(json.range(of: "\"schemaVersion\""))
        XCTAssertLessThan(allKey.lowerBound, schemaKey.lowerBound)
    }

    func testNormalSTLIsNotOverwritten() throws {
        let normalData = Data("production-stl".utf8)
        try withTemporaryScanFiles(scanData: normalData) { scanURL, sessionURL in
            _ = try exporterWithDeterministicGenerator().export(
                input: makeInput(
                    allPoses: nontrivialPoses(),
                    filteredPoses: changedFilteredPoses()
                ),
                sourceSessionFileURL: sessionURL,
                sourceScanFileURL: scanURL
            )
            XCTAssertEqual(try Data(contentsOf: scanURL), normalData)
        }
    }

    func testExistingDiagnosticArtifactsAreNotOverwritten() throws {
        try withTemporaryScanFiles { scanURL, sessionURL in
            let directory = scanURL.deletingLastPathComponent()
            let protectedNames = [
                "SavedScan_report.json",
                "SavedScan_diagnostics.json",
                "SavedScan_replay_summary.json",
                "SavedScan_pregate_ab_replay_summary.json"
            ]
            let sentinel = Data("protected".utf8)
            let protectedURLs = protectedNames.map {
                directory.appendingPathComponent($0)
            }
            for url in protectedURLs {
                try sentinel.write(to: url)
            }

            _ = try exporterWithDeterministicGenerator().export(
                input: makeInput(
                    allPoses: nontrivialPoses(),
                    filteredPoses: changedFilteredPoses()
                ),
                sourceSessionFileURL: sessionURL,
                sourceScanFileURL: scanURL
            )

            XCTAssertEqual(try Data(contentsOf: sessionURL), Data("session".utf8))
            for url in protectedURLs {
                XCTAssertEqual(try Data(contentsOf: url), sentinel)
            }
        }
    }

    func testExportFailsWhenEitherReplayIsNotDeterministic() throws {
        let allFailed = makeInput(
            allPoses: nontrivialPoses(),
            filteredPoses: nontrivialPoses(),
            allDeterministic: false
        )
        let filteredFailed = makeInput(
            allPoses: nontrivialPoses(),
            filteredPoses: nontrivialPoses(),
            filteredDeterministic: false
        )

        try withTemporaryScanFiles { scanURL, sessionURL in
            XCTAssertThrowsError(
                try exporterWithDeterministicGenerator().export(
                    input: allFailed,
                    sourceSessionFileURL: sessionURL,
                    sourceScanFileURL: scanURL
                )
            ) { error in
                XCTAssertEqual(
                    error as? ScanSessionReplaySTLComparisonExportError,
                    .nonDeterministicReplay(policy: "ALL")
                )
            }
            XCTAssertThrowsError(
                try exporterWithDeterministicGenerator().export(
                    input: filteredFailed,
                    sourceSessionFileURL: sessionURL,
                    sourceScanFileURL: scanURL
                )
            ) { error in
                XCTAssertEqual(
                    error as? ScanSessionReplaySTLComparisonExportError,
                    .nonDeterministicReplay(policy: "FILTERED")
                )
            }
        }
    }

    func testExportFailsWhenRequiredMarkerModelIsUnavailable() throws {
        let missingModelExporter = DiagnosticMarkerAssemblySTLExporter {
            _, _, _ in
            throw STLExporter.ExportError.missingReferenceModel(
                fileName: "missing_test_model"
            )
        }

        try withTemporaryScanFiles { scanURL, sessionURL in
            XCTAssertThrowsError(
                try ScanSessionReplaySTLComparisonExporter(
                    markerAssemblyExporter: missingModelExporter
                ).export(
                    input: makeInput(
                        allPoses: nontrivialPoses(),
                        filteredPoses: nontrivialPoses()
                    ),
                    sourceSessionFileURL: sessionURL,
                    sourceScanFileURL: scanURL
                )
            ) { error in
                guard let exportError = error as? STLExporter.ExportError,
                      case .missingReferenceModel = exportError
                else {
                    return XCTFail("Unexpected error: \(error)")
                }
            }
        }
    }

    func testNontrivialDifferentGeometryProducesDifferentSTLBytes() throws {
        let artifacts = try exportWithDeterministicGenerator(
            input: makeInput(
                allPoses: nontrivialPoses(),
                filteredPoses: changedFilteredPoses()
            )
        )
        XCTAssertNotEqual(
            try Data(contentsOf: artifacts.allSTLURL),
            try Data(contentsOf: artifacts.filteredSTLURL)
        )
    }

    func testEquivalentGeometryProducesEquivalentNormalizedAssemblies() throws {
        let all = nontrivialPoses()
        let transformed = all.map {
            applyGlobalTransform(
                to: $0,
                rotation: PoseMath.rotationMatrix(
                    fromRodrigues: SIMD3(0.2, 0.1, -0.15)
                ),
                translation: SIMD3(8, -4, 21)
            )
        }
        let normalized = try DiagnosticMarkerPoseNormalizer.normalize(
            allPoses: all,
            filteredPoses: transformed
        )
        assertPoseGeometryEqual(normalized.allPoses, normalized.filteredPoses)
    }

    func testArtifactsExposeAllThreeFilesForShareSheet() throws {
        let artifacts = try exportWithDeterministicGenerator(
            input: makeInput(
                allPoses: nontrivialPoses(),
                filteredPoses: changedFilteredPoses()
            )
        )

        XCTAssertEqual(artifacts.shareURLs.count, 3)
        XCTAssertEqual(
            artifacts.shareURLs,
            [artifacts.allSTLURL, artifacts.filteredSTLURL, artifacts.manifestURL]
        )
    }

    func testRepeatedExportProducesDeterministicBytes() throws {
        let input = makeInput(
            allPoses: nontrivialPoses(),
            filteredPoses: changedFilteredPoses()
        )
        try withTemporaryScanFiles { scanURL, sessionURL in
            let exporter = ScanSessionReplaySTLComparisonExporter()
            let first = try exporter.export(
                input: input,
                sourceSessionFileURL: sessionURL,
                sourceScanFileURL: scanURL
            )
            let firstBytes = try first.shareURLs.map { try Data(contentsOf: $0) }
            let second = try exporter.export(
                input: input,
                sourceSessionFileURL: sessionURL,
                sourceScanFileURL: scanURL
            )
            let secondBytes = try second.shareURLs.map { try Data(contentsOf: $0) }
            XCTAssertEqual(firstBytes, secondBytes)
        }
    }

    func testDefaultExporterUsesBundledReferenceMarkerModel() throws {
        let artifacts = try withTemporaryScanFiles { scanURL, sessionURL in
            try ScanSessionReplaySTLComparisonExporter().export(
                input: makeInput(
                    allPoses: nontrivialPoses(),
                    filteredPoses: changedFilteredPoses()
                ),
                sourceSessionFileURL: sessionURL,
                sourceScanFileURL: scanURL
            )
        }

        XCTAssertGreaterThan(artifacts.manifest.allSTLFileSizeBytes, 0)
        XCTAssertGreaterThan(artifacts.manifest.filteredSTLFileSizeBytes, 0)
    }

    private func pose(
        _ markerId: Int,
        profile: MarkerProfile = .singleArucoV1,
        rotation: SIMD3<Double> = SIMD3(0.1, -0.05, 0.08),
        translation: SIMD3<Double>? = nil
    ) -> PoseResult {
        let translation = translation ?? SIMD3(
            Double(markerId) * 11.0,
            Double(markerId) * -3.0,
            Double(markerId) * 2.5
        )
        return PoseResult(
            markerId: markerId,
            markerProfile: profile,
            poseSource: profile == .singleArucoV1 ? .singleArucoV1 : .dualTag,
            rotationVector: rotation,
            translationVector: translation,
            distanceMm: simd_length(translation),
            reprojectionError: 0.25,
            markerAreaPixels: 600,
            usedPointCount: profile == .singleArucoV1 ? 4 : 8
        )
    }

    private func nontrivialPoses(
        profile: MarkerProfile = .singleArucoV1
    ) -> [PoseResult] {
        [
            pose(
                1,
                profile: profile,
                rotation: SIMD3(0.12, -0.08, 0.19),
                translation: SIMD3(13, -4, 7)
            ),
            pose(
                2,
                profile: profile,
                rotation: SIMD3(-0.21, 0.14, 0.07),
                translation: SIMD3(38, 9, -3)
            ),
            pose(
                3,
                profile: profile,
                rotation: SIMD3(0.05, 0.28, -0.16),
                translation: SIMD3(-11, 31, 14)
            )
        ]
    }

    private func changedFilteredPoses() -> [PoseResult] {
        [
            pose(
                1,
                rotation: SIMD3(0.12, -0.08, 0.19),
                translation: SIMD3(13, -4, 7)
            ),
            pose(
                2,
                rotation: SIMD3(-0.17, 0.19, 0.13),
                translation: SIMD3(41, 7, -1)
            ),
            pose(
                3,
                rotation: SIMD3(0.09, 0.24, -0.11),
                translation: SIMD3(-8, 34, 11)
            )
        ]
    }

    private func makeInput(
        allPoses: [PoseResult],
        filteredPoses: [PoseResult],
        allDeterministic: Bool = true,
        filteredDeterministic: Bool = true
    ) -> ScanSessionReplaySTLComparisonExportInput {
        ScanSessionReplaySTLComparisonExportInput(
            sessionIdentifier: "test-session",
            sourceSchemaVersion: 1,
            appVersion: "0.1.0",
            appBuildIdentifier: "1",
            appGitCommitHash: "test-commit",
            allPoses: allPoses,
            filteredPoses: filteredPoses,
            allDeterministic: allDeterministic,
            filteredDeterministic: filteredDeterministic,
            provenanceCaveats: ["fixture"]
        )
    }

    private func exporterWithDeterministicGenerator()
        -> ScanSessionReplaySTLComparisonExporter {
        let markerExporter = DiagnosticMarkerAssemblySTLExporter {
            profile, poses, _ in
            let lines = poses.sorted { $0.markerId < $1.markerId }.map { pose in
                let rotationRows = (0..<3).map { row in
                    (0..<3).map {
                        format(PoseMath.matrixElement(
                            pose.rotationMatrix,
                            row: row,
                            column: $0
                        ))
                    }.joined(separator: ",")
                }.joined(separator: ";")
                return [
                    String(pose.markerId),
                    profile.rawValue,
                    rotationRows,
                    format(pose.translationVector.x),
                    format(pose.translationVector.y),
                    format(pose.translationVector.z)
                ].joined(separator: "|")
            }
            return lines.joined(separator: "\n") + "\n"
        }
        return ScanSessionReplaySTLComparisonExporter(
            markerAssemblyExporter: markerExporter
        )
    }

    private func exportWithDeterministicGenerator(
        input: ScanSessionReplaySTLComparisonExportInput
    ) throws -> ScanSessionReplaySTLComparisonArtifacts {
        var retainedDirectory: URL?
        let artifacts = try withTemporaryScanFiles(removeDirectory: false) {
            scanURL, sessionURL in
            retainedDirectory = scanURL.deletingLastPathComponent()
            return try exporterWithDeterministicGenerator().export(
                input: input,
                sourceSessionFileURL: sessionURL,
                sourceScanFileURL: scanURL
            )
        }
        addTeardownBlock {
            if let retainedDirectory {
                try? FileManager.default.removeItem(at: retainedDirectory)
            }
        }
        return artifacts
    }

    private func withTemporaryScanFiles<T>(
        scanData: Data = Data("production".utf8),
        removeDirectory: Bool = true,
        _ body: (URL, URL) throws -> T
    ) throws -> T {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer {
            if removeDirectory {
                try? FileManager.default.removeItem(at: directory)
            }
        }
        let scanURL = directory.appendingPathComponent("SavedScan.stl")
        let sessionURL = directory.appendingPathComponent("SavedScan_session.ndjson")
        try scanData.write(to: scanURL)
        try Data("session".utf8).write(to: sessionURL)
        return try body(scanURL, sessionURL)
    }

    private func applyGlobalTransform(
        to pose: PoseResult,
        rotation: simd_double3x3,
        translation: SIMD3<Double>
    ) -> PoseResult {
        let transformedRotation = rotation * pose.rotationMatrix
        let transformedTranslation = rotation * pose.translationVector + translation
        return PoseResult(
            markerId: pose.markerId,
            markerProfile: pose.markerProfile,
            poseSource: pose.poseSource,
            rotationVector: PoseMath.rotationVector(from: transformedRotation) ?? .zero,
            rotationMatrix: transformedRotation,
            translationVector: transformedTranslation,
            distanceMm: simd_length(transformedTranslation),
            reprojectionError: pose.reprojectionError,
            markerAreaPixels: pose.markerAreaPixels,
            usedPointCount: pose.usedPointCount,
            detectedTopTagId: pose.detectedTopTagId,
            detectedBottomTagId: pose.detectedBottomTagId
        )
    }

    private func markerPairs(_ markerIds: [Int]) -> [(Int, Int)] {
        let ids = markerIds.sorted()
        var pairs: [(Int, Int)] = []
        for first in ids.indices {
            for second in ids.index(after: first)..<ids.endIndex {
                pairs.append((ids[first], ids[second]))
            }
        }
        return pairs
    }

    private func relativeDistance(
        _ pair: (Int, Int),
        in poses: [PoseResult]
    ) -> Double {
        guard let first = poses.first(where: { $0.markerId == pair.0 }),
              let second = poses.first(where: { $0.markerId == pair.1 })
        else {
            return .nan
        }
        return simd_length(
            simd_transpose(first.rotationMatrix) *
                (second.translationVector - first.translationVector)
        )
    }

    private func relativeRotation(
        _ pair: (Int, Int),
        in poses: [PoseResult]
    ) -> simd_double3x3 {
        guard let first = poses.first(where: { $0.markerId == pair.0 }),
              let second = poses.first(where: { $0.markerId == pair.1 })
        else {
            let invalidColumn = SIMD3<Double>(repeating: .nan)
            return simd_double3x3(columns: (
                invalidColumn,
                invalidColumn,
                invalidColumn
            ))
        }
        return simd_transpose(first.rotationMatrix) * second.rotationMatrix
    }

    private func rotationDeltaDegrees(
        _ lhs: simd_double3x3,
        _ rhs: simd_double3x3
    ) -> Double {
        let delta = simd_transpose(lhs) * rhs
        let trace = PoseMath.matrixElement(delta, row: 0, column: 0) +
            PoseMath.matrixElement(delta, row: 1, column: 1) +
            PoseMath.matrixElement(delta, row: 2, column: 2)
        return acos(min(max((trace - 1) / 2, -1), 1)) * 180 / Double.pi
    }

    private func assertPoseGeometryEqual(
        _ lhs: [PoseResult],
        _ rhs: [PoseResult],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(lhs.map(\.markerId), rhs.map(\.markerId), file: file, line: line)
        for markerId in lhs.map(\.markerId) {
            guard let first = lhs.first(where: { $0.markerId == markerId }),
                  let second = rhs.first(where: { $0.markerId == markerId })
            else {
                XCTFail("Missing marker \(markerId)", file: file, line: line)
                return
            }
            XCTAssertEqual(
                simd_distance(first.translationVector, second.translationVector),
                0,
                accuracy: 1e-9,
                file: file,
                line: line
            )
            XCTAssertEqual(
                rotationDeltaDegrees(first.rotationMatrix, second.rotationMatrix),
                0,
                accuracy: 1e-6,
                file: file,
                line: line
            )
        }
    }

    private func assertIdentity(
        _ matrix: simd_double3x3,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for row in 0..<3 {
            for column in 0..<3 {
                XCTAssertEqual(
                    PoseMath.matrixElement(matrix, row: row, column: column),
                    row == column ? 1 : 0,
                    accuracy: 0,
                    file: file,
                    line: line
                )
            }
        }
    }

    private func format(_ value: Double) -> String {
        String(
            format: "%.9f",
            locale: Locale(identifier: "en_US_POSIX"),
            arguments: [value]
        )
    }
}
