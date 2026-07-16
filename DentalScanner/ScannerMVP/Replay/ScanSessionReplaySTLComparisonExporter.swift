import Foundation

struct ScanSessionReplaySTLComparisonManifest: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let sourceSessionSchemaVersion: Int
    let sessionIdentifier: String
    let appVersion: String?
    let appBuildIdentifier: String?
    let appGitCommitHash: String?
    let sourceSessionFilename: String
    let sourceScanFilename: String
    let allReplayPolicy: String
    let filteredReplayPolicy: String
    let comparisonBaseMarkerId: Int
    let markerProfile: String
    let referenceModelFilename: String
    let allMarkerIds: [Int]
    let filteredMarkerIds: [Int]
    let commonMarkerIds: [Int]
    let missingFromAll: [Int]
    let missingFromFiltered: [Int]
    let allDeterministic: Bool
    let filteredDeterministic: Bool
    let allSTLFilename: String
    let filteredSTLFilename: String
    let allSTLFileSizeBytes: Int64
    let filteredSTLFileSizeBytes: Int64
    let pairwiseRelativeGeometry: ScanSessionReplayPairwiseGeometryComparison
    let coordinateNormalizationDescription: String
    let offlineFilteredReplayUsesPersistedDecisions: Bool
    let livePreAccumulationBlockingEnabledAtCapture: Bool?
    let integrityResult: String
    let provenanceCaveats: [String]
}

struct ScanSessionReplaySTLComparisonExportInput {
    let sessionIdentifier: String
    let sourceSchemaVersion: Int
    let appVersion: String?
    let appBuildIdentifier: String?
    let appGitCommitHash: String?
    let allReplayPolicy: String
    let filteredReplayPolicy: String
    let allPoses: [PoseResult]
    let filteredPoses: [PoseResult]
    let allDeterministic: Bool
    let filteredDeterministic: Bool
    let offlineFilteredReplayUsesPersistedDecisions: Bool
    let livePreAccumulationBlockingEnabledAtCapture: Bool?
    let integrityResult: String
    let provenanceCaveats: [String]

    init(replayResult: ScanSessionPreAccumulationGateABReplayResult) {
        let summary = replayResult.summary
        sessionIdentifier = summary.sessionIdentifier
        sourceSchemaVersion = summary.schemaVersion
        appVersion = summary.appVersion
        appBuildIdentifier = summary.appBuildIdentifier
        appGitCommitHash = summary.appGitCommitHash
        allReplayPolicy = summary.baselineReplayPolicy
        filteredReplayPolicy = summary.filteredReplayPolicy
        allPoses = replayResult.allReplay.replayAFinalPoses
        filteredPoses = replayResult.filteredReplay.replayAFinalPoses
        allDeterministic = summary.allDeterminism.replayDeterministic
        filteredDeterministic = summary.filteredDeterminism.replayDeterministic
        offlineFilteredReplayUsesPersistedDecisions =
            summary.offlineFilteredReplayUsesPersistedDecisions
        livePreAccumulationBlockingEnabledAtCapture =
            summary.livePreAccumulationBlockingEnabledAtCapture
        integrityResult = summary.integrityResult
        provenanceCaveats = summary.provenanceCaveats
    }

    init(
        sessionIdentifier: String,
        sourceSchemaVersion: Int = 1,
        appVersion: String? = nil,
        appBuildIdentifier: String? = nil,
        appGitCommitHash: String? = nil,
        allReplayPolicy: String = ScanSessionReplayObservationPolicy.allPersisted.rawValue,
        filteredReplayPolicy: String = ScanSessionReplayObservationPolicy
            .preAccumulationGateAcceptedOnly.rawValue,
        allPoses: [PoseResult],
        filteredPoses: [PoseResult],
        allDeterministic: Bool = true,
        filteredDeterministic: Bool = true,
        offlineFilteredReplayUsesPersistedDecisions: Bool = true,
        livePreAccumulationBlockingEnabledAtCapture: Bool? = false,
        integrityResult: String = "valid",
        provenanceCaveats: [String] = []
    ) {
        self.sessionIdentifier = sessionIdentifier
        self.sourceSchemaVersion = sourceSchemaVersion
        self.appVersion = appVersion
        self.appBuildIdentifier = appBuildIdentifier
        self.appGitCommitHash = appGitCommitHash
        self.allReplayPolicy = allReplayPolicy
        self.filteredReplayPolicy = filteredReplayPolicy
        self.allPoses = allPoses
        self.filteredPoses = filteredPoses
        self.allDeterministic = allDeterministic
        self.filteredDeterministic = filteredDeterministic
        self.offlineFilteredReplayUsesPersistedDecisions =
            offlineFilteredReplayUsesPersistedDecisions
        self.livePreAccumulationBlockingEnabledAtCapture =
            livePreAccumulationBlockingEnabledAtCapture
        self.integrityResult = integrityResult
        self.provenanceCaveats = provenanceCaveats
    }
}

struct ScanSessionReplaySTLComparisonArtifacts {
    let allSTLURL: URL
    let filteredSTLURL: URL
    let manifestURL: URL
    let manifest: ScanSessionReplaySTLComparisonManifest

    var shareURLs: [URL] {
        [allSTLURL, filteredSTLURL, manifestURL]
    }
}

enum ScanSessionReplaySTLComparisonExportError: LocalizedError, Equatable {
    case nonDeterministicReplay(policy: String)
    case inconsistentMarkerProfiles
    case outputCollidesWithSource(filename: String)

    var errorDescription: String? {
        switch self {
        case let .nonDeterministicReplay(policy):
            return "O replay \(policy) não passou na verificação de determinismo."
        case .inconsistentMarkerProfiles:
            return "ALL e FILTERED não possuem um único perfil de marker compatível."
        case let .outputCollidesWithSource(filename):
            return "O arquivo diagnóstico tentaria sobrescrever \(filename)."
        }
    }
}

struct ScanSessionReplaySTLComparisonExporter {
    static let manifestSchemaVersion = 1
    static let coordinateNormalizationDescription =
        "Both replay pose sets are rebased independently to the lowest common marker ID using " +
        "T_base_marker = inverse(T_output_base) * T_output_marker; the common base marker is " +
        "identity in both diagnostic STL assemblies."

    private let markerAssemblyExporter: DiagnosticMarkerAssemblySTLExporter

    init(
        markerAssemblyExporter: DiagnosticMarkerAssemblySTLExporter =
            DiagnosticMarkerAssemblySTLExporter()
    ) {
        self.markerAssemblyExporter = markerAssemblyExporter
    }

    static func allSTLOutputURL(forScanFileURL scanFileURL: URL) -> URL {
        outputURL(
            forScanFileURL: scanFileURL,
            suffix: "_replay_all.stl"
        )
    }

    static func filteredSTLOutputURL(forScanFileURL scanFileURL: URL) -> URL {
        outputURL(
            forScanFileURL: scanFileURL,
            suffix: "_replay_pregate_filtered.stl"
        )
    }

    static func manifestOutputURL(forScanFileURL scanFileURL: URL) -> URL {
        outputURL(
            forScanFileURL: scanFileURL,
            suffix: "_replay_stl_comparison.json"
        )
    }

    static func encode(
        _ manifest: ScanSessionReplaySTLComparisonManifest
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(manifest)
    }

    func export(
        input: ScanSessionReplaySTLComparisonExportInput,
        sourceSessionFileURL: URL,
        sourceScanFileURL: URL
    ) throws -> ScanSessionReplaySTLComparisonArtifacts {
        guard input.allDeterministic else {
            throw ScanSessionReplaySTLComparisonExportError.nonDeterministicReplay(
                policy: "ALL"
            )
        }
        guard input.filteredDeterministic else {
            throw ScanSessionReplaySTLComparisonExportError.nonDeterministicReplay(
                policy: "FILTERED"
            )
        }

        let normalization = try DiagnosticMarkerPoseNormalizer.normalize(
            allPoses: input.allPoses,
            filteredPoses: input.filteredPoses
        )
        let markerProfile = try commonMarkerProfile(
            allPoses: normalization.allPoses,
            filteredPoses: normalization.filteredPoses
        )
        let referenceModelFilename = STLExporter(
            configuration: .referenceMarker(for: markerProfile)
        ).referenceModelFileName

        let allSTLURL = Self.allSTLOutputURL(forScanFileURL: sourceScanFileURL)
        let filteredSTLURL = Self.filteredSTLOutputURL(forScanFileURL: sourceScanFileURL)
        let manifestURL = Self.manifestOutputURL(forScanFileURL: sourceScanFileURL)
        try validateOutputURLs(
            [allSTLURL, filteredSTLURL, manifestURL],
            sourceURLs: [sourceScanFileURL, sourceSessionFileURL]
        )

        let allData = try markerAssemblyExporter.makeSTLData(
            poses: normalization.allPoses,
            markerProfile: markerProfile,
            provenance: DiagnosticMarkerAssemblyProvenance(
                sessionIdentifier: input.sessionIdentifier,
                replayPolicy: "all",
                comparisonBaseMarkerId: normalization.baseMarkerId
            )
        )
        let filteredData = try markerAssemblyExporter.makeSTLData(
            poses: normalization.filteredPoses,
            markerProfile: markerProfile,
            provenance: DiagnosticMarkerAssemblyProvenance(
                sessionIdentifier: input.sessionIdentifier,
                replayPolicy: "pregate_filtered",
                comparisonBaseMarkerId: normalization.baseMarkerId
            )
        )
        let pairwiseGeometry = ScanSessionReplayPairwiseGeometryComparator.compare(
            allPoses: normalization.allPoses,
            filteredPoses: normalization.filteredPoses
        )
        var caveats = input.provenanceCaveats
        caveats.append(
            "diagnostic STL assemblies do not replace or modify the saved production STL"
        )
        caveats.append(
            "coordinate normalization changes only the output frame and preserves each replay's internal relative geometry"
        )
        let manifest = ScanSessionReplaySTLComparisonManifest(
            schemaVersion: Self.manifestSchemaVersion,
            sourceSessionSchemaVersion: input.sourceSchemaVersion,
            sessionIdentifier: input.sessionIdentifier,
            appVersion: input.appVersion,
            appBuildIdentifier: input.appBuildIdentifier,
            appGitCommitHash: input.appGitCommitHash,
            sourceSessionFilename: sourceSessionFileURL.lastPathComponent,
            sourceScanFilename: sourceScanFileURL.lastPathComponent,
            allReplayPolicy: input.allReplayPolicy,
            filteredReplayPolicy: input.filteredReplayPolicy,
            comparisonBaseMarkerId: normalization.baseMarkerId,
            markerProfile: markerProfile.rawValue,
            referenceModelFilename: referenceModelFilename,
            allMarkerIds: normalization.allMarkerIds,
            filteredMarkerIds: normalization.filteredMarkerIds,
            commonMarkerIds: normalization.commonMarkerIds,
            missingFromAll: normalization.missingFromAll,
            missingFromFiltered: normalization.missingFromFiltered,
            allDeterministic: input.allDeterministic,
            filteredDeterministic: input.filteredDeterministic,
            allSTLFilename: allSTLURL.lastPathComponent,
            filteredSTLFilename: filteredSTLURL.lastPathComponent,
            allSTLFileSizeBytes: Int64(allData.count),
            filteredSTLFileSizeBytes: Int64(filteredData.count),
            pairwiseRelativeGeometry: pairwiseGeometry,
            coordinateNormalizationDescription: Self.coordinateNormalizationDescription,
            offlineFilteredReplayUsesPersistedDecisions:
                input.offlineFilteredReplayUsesPersistedDecisions,
            livePreAccumulationBlockingEnabledAtCapture:
                input.livePreAccumulationBlockingEnabledAtCapture,
            integrityResult: input.integrityResult,
            provenanceCaveats: caveats
        )
        let manifestData = try Self.encode(manifest)

        try allData.write(to: allSTLURL, options: .atomic)
        try filteredData.write(to: filteredSTLURL, options: .atomic)
        try manifestData.write(to: manifestURL, options: .atomic)

        return ScanSessionReplaySTLComparisonArtifacts(
            allSTLURL: allSTLURL,
            filteredSTLURL: filteredSTLURL,
            manifestURL: manifestURL,
            manifest: manifest
        )
    }

    private static func outputURL(
        forScanFileURL scanFileURL: URL,
        suffix: String
    ) -> URL {
        let baseName = scanFileURL.deletingPathExtension().lastPathComponent
        return scanFileURL
            .deletingLastPathComponent()
            .appendingPathComponent("\(baseName)\(suffix)")
    }

    private func commonMarkerProfile(
        allPoses: [PoseResult],
        filteredPoses: [PoseResult]
    ) throws -> MarkerProfile {
        let profiles = Set((allPoses + filteredPoses).map(\.markerProfile))
        guard profiles.count == 1, let markerProfile = profiles.first else {
            throw ScanSessionReplaySTLComparisonExportError.inconsistentMarkerProfiles
        }
        return markerProfile
    }

    private func validateOutputURLs(
        _ outputURLs: [URL],
        sourceURLs: [URL]
    ) throws {
        let sourcePaths = Set(sourceURLs.map { $0.standardizedFileURL.path })
        for outputURL in outputURLs where sourcePaths.contains(
            outputURL.standardizedFileURL.path
        ) {
            throw ScanSessionReplaySTLComparisonExportError.outputCollidesWithSource(
                filename: outputURL.lastPathComponent
            )
        }
    }
}
