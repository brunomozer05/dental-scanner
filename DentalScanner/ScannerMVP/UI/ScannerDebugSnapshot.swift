import Foundation

struct ScannerDebugSnapshot: Equatable {
    static let missingValue = "\u{2014}"

    struct StateSection: Equatable {
        let scanState: String
        let markerProfile: String
        let readinessMessage: String
        let currentMarkerCount: String
        let detectedMarkerIds: String
        let exportablePoseCount: String
    }

    struct ExportSection: Equatable {
        let isGeneratingSTL: String
        let stlURLExists: String
        let stlFileExists: String
        let stlError: String
        let currentExportableTagPoseCount: String
        let lastSTLExportPoseCount: String
    }

    struct ReadinessSection: Equatable {
        let coverageReady: String
        let goodFramesReady: String
        let reprojectionReady: String
        let distanceReady: String
        let jitterReady: String
        let stableReady: String
        let currentFrameGood: String
        let dualTagReady: String
        let dualAngularReady: String
    }

    struct ConfigurationSection: Equatable {
        let markerProfile: String
        let showDistanceGuide: String
        let requiredAngularCoverage: String
        let minimumDualTagFrames: String
        let minimumDualAngularCoverage: String
        let precisionModeV2: String
        let preferDualTagForFinalExport: String
        let minimumGoodFrames: String
        let targetValidFrames: String
    }

    struct MarkerV2Row: Equatable, Identifiable {
        let markerId: Int
        let dualFrames: String
        let topFallbackFrames: String
        let bottomFallbackFrames: String
        let dualPercent: String
        let dominantMode: String

        var id: Int {
            markerId
        }
    }

    let state: StateSection
    let export: ExportSection
    let readiness: ReadinessSection
    let configuration: ConfigurationSection
    let isDualArucoV2: Bool
    let markerV2Rows: [MarkerV2Row]
}

extension ScannerViewModel {
    var scannerDebugSnapshot: ScannerDebugSnapshot {
        ScannerDebugSnapshot(
            state: ScannerDebugSnapshot.StateSection(
                scanState: Self.debugScanStateTitle(scanState),
                markerProfile: markerProfile.debugTitle,
                readinessMessage: debugString(scanReadinessMessage),
                currentMarkerCount: "\(detectedMarkerCount)",
                detectedMarkerIds: Self.debugIntList(detectedMarkerIds),
                exportablePoseCount: "\(currentExportableTagPoseCount)"
            ),
            export: ScannerDebugSnapshot.ExportSection(
                isGeneratingSTL: debugBool(isGeneratingSTL),
                stlURLExists: debugBool(hasSTLExportURL),
                stlFileExists: debugBool(hasSTLExportFile),
                stlError: debugString(stlExportErrorMessage ?? "Nenhum"),
                currentExportableTagPoseCount: "\(currentExportableTagPoseCount)",
                lastSTLExportPoseCount: "\(lastSTLExportTagPoseCount)"
            ),
            readiness: ScannerDebugSnapshot.ReadinessSection(
                coverageReady: debugBool(scanCoverageReady),
                goodFramesReady: debugBool(scanGoodFramesReady),
                reprojectionReady: debugBool(scanReprojectionReady),
                distanceReady: debugBool(scanDistanceReady),
                jitterReady: debugBool(scanJitterReady),
                stableReady: debugBool(scanStableReady),
                currentFrameGood: debugBool(scanCurrentFrameGood),
                dualTagReady: debugBool(scanDualTagReady),
                dualAngularReady: debugBool(scanDualAngularCoverageReady)
            ),
            configuration: ScannerDebugSnapshot.ConfigurationSection(
                markerProfile: markerProfile.debugTitle,
                showDistanceGuide: debugBool(showDistanceGuide),
                requiredAngularCoverage: Self.debugPercent(scanRequiredAngularCoveragePercent),
                minimumDualTagFrames: "\(scanMinimumDualTagFrameCount)",
                minimumDualAngularCoverage: Self.debugPercent(scanRequiredDualAngularCoveragePercent),
                precisionModeV2: debugBool(precisionModeV2),
                preferDualTagForFinalExport: debugBool(preferDualTagForFinalExport),
                minimumGoodFrames: "\(scanMinimumGoodFrameCount)",
                targetValidFrames: "\(scanTargetValidFrameCount)"
            ),
            isDualArucoV2: markerProfile == .dualArucoV2,
            markerV2Rows: markerProfile == .dualArucoV2
                ? dualMarkerDebugStates
                    .sorted { $0.physicalMarkerId < $1.physicalMarkerId }
                    .map(Self.debugMarkerV2Row)
                : []
        )
    }

    private static func debugMarkerV2Row(_ state: DualArucoMarkerDebugState) -> ScannerDebugSnapshot.MarkerV2Row {
        ScannerDebugSnapshot.MarkerV2Row(
            markerId: state.physicalMarkerId,
            dualFrames: "\(state.scanDualTagFrameCount)",
            topFallbackFrames: "\(state.scanTopFallbackFrameCount)",
            bottomFallbackFrames: "\(state.scanBottomFallbackFrameCount)",
            dualPercent: debugPercent(state.scanDualTagPosePercent),
            dominantMode: state.scanDominantPoseSource?.debugTitle ?? ScannerDebugSnapshot.missingValue
        )
    }

    private static func debugScanStateTitle(_ scanState: ScanState) -> String {
        switch scanState {
        case .idle:
            return "Idle"
        case .scanning:
            return "Scanning"
        case .stabilizing:
            return "Stabilizing"
        case .ready:
            return "Ready"
        }
    }

    private func debugString(_ value: String?) -> String {
        guard let value, !value.isEmpty else {
            return ScannerDebugSnapshot.missingValue
        }

        return value
    }

    private func debugBool(_ value: Bool) -> String {
        value ? "Sim" : "Nao"
    }

    private static func debugPercent(_ value: Double?) -> String {
        guard let value, value.isFinite else {
            return ScannerDebugSnapshot.missingValue
        }

        return "\(String(format: "%.1f", value))%"
    }

    private static func debugIntList(_ values: [Int]) -> String {
        guard !values.isEmpty else {
            return ScannerDebugSnapshot.missingValue
        }

        return values.sorted().map(String.init).joined(separator: ", ")
    }
}
