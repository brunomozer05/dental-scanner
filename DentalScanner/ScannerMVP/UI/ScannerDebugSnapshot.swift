import CoreGraphics
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
        let lockFocusAndExposureForScan: String
        let cameraZoomFactor: String
        let manualFocusEnabled: String
        let manualLensPosition: String
        let autoFocusOnDetectedAruco: String
        let lockAfterArucoFocus: String
        let arkitAssistedCaptureEnabled: String
        let requiredAngularCoverage: String
        let minimumDualTagFrames: String
        let minimumDualAngularCoverage: String
        let precisionModeV2: String
        let preferDualTagForFinalExport: String
        let minimumGoodFrames: String
        let targetValidFrames: String
    }

    struct CameraSection: Equatable {
        let deviceName: String
        let deviceType: String
        let uniqueID: String
        let activeFormatDescription: String
        let resolution: String
        let fps: String
        let hasIntrinsics: String
        let fx: String
        let fy: String
        let cx: String
        let cy: String
        let lensPosition: String
        let lastLensPositionChangeAge: String
        let cameraFocusStable: String
        let focusSettling: String
        let sharpness: String
        let averageSharpness: String
        let minimumAllowedSharpness: String
        let minimumPreferredSharpness: String
        let isAdjustingFocus: String
        let isAdjustingExposure: String
        let isAdjustingWhiteBalance: String
        let iso: String
        let exposureDuration: String
        let cameraStabilityScore: String
        let rotationStabilityScore: String
        let automaticLockEnabled: String
        let cameraLocked: String
        let videoZoomFactor: String
        let minimumAvailableVideoZoomFactor: String
        let maximumAvailableVideoZoomFactor: String
        let manualFocusEnabled: String
        let manualLensPosition: String
        let manualFocusSupported: String
        let lockError: String
        let lastArucoFocusTagId: String
        let lastArucoFocusMarkerId: String
        let lastArucoFocusPoint: String
        let lastArucoFocusRequestAge: String
        let arucoFocusCooldown: String
        let lastArucoFocusError: String
        let focusAdjustingFrames: String
        let focusRejectedFrames: String
        let blurRejectedFrames: String
        let exposureAdjustingFrames: String
        let whiteBalanceAdjustingFrames: String
        let unstableFrames: String
        let intrinsicsChanged: String
        let deviceChanged: String
        let formatChanged: String
        let resolutionChanged: String
        let warning: String
        let lastBadFrameReason: String
        let distanceGuideSourceReliable: String
        let distanceMm: String
        let distanceReady: String
    }

    struct ARKitSection: Equatable {
        let enabled: String
        let available: String
        let trackingState: String
        let reliable: String
        let hasTransform: String
        let hasIntrinsics: String
        let motionSinceLastFrame: String
        let intrinsicsChanged: String
        let lightEstimate: String
        let stabilityScore: String
        let rotationStabilityScore: String
        let recent: String
        let penalizedFrames: String
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
    let camera: CameraSection
    let arkit: ARKitSection
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
                lockFocusAndExposureForScan: debugBool(lockFocusAndExposureForScan),
                cameraZoomFactor: Self.debugNumber(cameraZoomFactor, decimals: 1),
                manualFocusEnabled: debugBool(manualFocusEnabled),
                manualLensPosition: Self.debugNumber(manualLensPosition, decimals: 2),
                autoFocusOnDetectedAruco: debugBool(autoFocusOnDetectedAruco),
                lockAfterArucoFocus: debugBool(lockAfterArucoFocus),
                arkitAssistedCaptureEnabled: debugBool(arkitAssistedCaptureEnabled),
                requiredAngularCoverage: Self.debugPercent(scanRequiredAngularCoveragePercent),
                minimumDualTagFrames: "\(scanMinimumDualTagFrameCount)",
                minimumDualAngularCoverage: Self.debugPercent(scanRequiredDualAngularCoveragePercent),
                precisionModeV2: debugBool(precisionModeV2),
                preferDualTagForFinalExport: debugBool(preferDualTagForFinalExport),
                minimumGoodFrames: "\(scanMinimumGoodFrameCount)",
                targetValidFrames: "\(scanTargetValidFrameCount)"
            ),
            camera: Self.debugCameraSection(
                currentCameraDebugSnapshot,
                focusAdjustingFrames: cameraFocusAdjustingFrameCount,
                exposureAdjustingFrames: cameraExposureAdjustingFrameCount,
                whiteBalanceAdjustingFrames: cameraWhiteBalanceAdjustingFrameCount,
                unstableFrames: cameraUnstableFrameCount,
                intrinsicsChanged: cameraIntrinsicsChangedDuringScan,
                deviceChanged: cameraDeviceChangedDuringScan,
                formatChanged: cameraFormatChangedDuringScan,
                resolutionChanged: cameraResolutionChangedDuringScan,
                warning: cameraReadinessWarning(),
                focusRejectedFrames: cameraFocusRejectedFrameCount,
                blurRejectedFrames: cameraBlurRejectedFrameCount,
                lastBadFrameReason: scanLastBadFrameReason,
                distanceGuideSourceReliable: distanceGuideSourceReliable,
                distanceMm: poseDistanceMm,
                distanceReady: scanDistanceReady,
                lastArucoFocusTagId: lastArucoFocusTagId,
                lastArucoFocusMarkerId: lastArucoFocusMarkerId,
                lastArucoFocusPoint: lastArucoFocusPoint,
                lastArucoFocusRequestAge: lastArucoFocusRequestAge(),
                arucoFocusCooldown: arucoFocusCooldownSeconds,
                lastArucoFocusError: lastArucoFocusErrorMessage
            ),
            arkit: Self.debugARKitSection(
                currentARKitFrameQuality,
                penalizedFrames: scanARKitPenalizedFrameCount
            ),
            isDualArucoV2: markerProfile == .dualArucoV2,
            markerV2Rows: markerProfile == .dualArucoV2
                ? dualMarkerDebugStates
                    .sorted { $0.physicalMarkerId < $1.physicalMarkerId }
                    .map(Self.debugMarkerV2Row)
                : []
        )
    }

    private static func debugCameraSection(
        _ snapshot: CameraDebugSnapshot,
        focusAdjustingFrames: Int,
        exposureAdjustingFrames: Int,
        whiteBalanceAdjustingFrames: Int,
        unstableFrames: Int,
        intrinsicsChanged: Bool,
        deviceChanged: Bool,
        formatChanged: Bool,
        resolutionChanged: Bool,
        warning: String?,
        focusRejectedFrames: Int,
        blurRejectedFrames: Int,
        lastBadFrameReason: String?,
        distanceGuideSourceReliable: Bool,
        distanceMm: Double?,
        distanceReady: Bool,
        lastArucoFocusTagId: Int?,
        lastArucoFocusMarkerId: Int?,
        lastArucoFocusPoint: CGPoint?,
        lastArucoFocusRequestAge: Double?,
        arucoFocusCooldown: Double,
        lastArucoFocusError: String?
    ) -> ScannerDebugSnapshot.CameraSection {
        ScannerDebugSnapshot.CameraSection(
            deviceName: debugText(snapshot.deviceName),
            deviceType: debugText(snapshot.deviceType),
            uniqueID: debugText(snapshot.uniqueID),
            activeFormatDescription: debugText(snapshot.activeFormatDescription),
            resolution: debugText(snapshot.resolutionText),
            fps: debugText(snapshot.fpsText),
            hasIntrinsics: snapshot.hasIntrinsics ? "Sim" : "Nao",
            fx: debugNumber(snapshot.fx, decimals: 1),
            fy: debugNumber(snapshot.fy, decimals: 1),
            cx: debugNumber(snapshot.cx, decimals: 1),
            cy: debugNumber(snapshot.cy, decimals: 1),
            lensPosition: debugNumber(snapshot.lensPosition.map(Double.init), decimals: 3),
            lastLensPositionChangeAge: debugSeconds(snapshot.lastLensPositionChangeAgeSeconds),
            cameraFocusStable: debugOptionalBool(snapshot.isFocusStable),
            focusSettling: debugOptionalBool(snapshot.isFocusSettling),
            sharpness: debugNumber(snapshot.sharpness, decimals: 1),
            averageSharpness: debugNumber(snapshot.averageSharpness, decimals: 1),
            minimumAllowedSharpness: debugNumber(snapshot.minimumAllowedSharpness, decimals: 1),
            minimumPreferredSharpness: debugNumber(snapshot.minimumPreferredSharpness, decimals: 1),
            isAdjustingFocus: debugOptionalBool(snapshot.isAdjustingFocus),
            isAdjustingExposure: debugOptionalBool(snapshot.isAdjustingExposure),
            isAdjustingWhiteBalance: debugOptionalBool(snapshot.isAdjustingWhiteBalance),
            iso: debugNumber(snapshot.iso.map(Double.init), decimals: 1),
            exposureDuration: debugExposureDuration(snapshot.exposureDurationSeconds),
            cameraStabilityScore: debugUnitIntervalPercent(snapshot.cameraStabilityScore),
            rotationStabilityScore: debugUnitIntervalPercent(snapshot.rotationStabilityScore),
            automaticLockEnabled: snapshot.automaticLockEnabled ? "Sim" : "Nao",
            cameraLocked: snapshot.isCameraLocked ? "Sim" : "Nao",
            videoZoomFactor: debugNumber(snapshot.videoZoomFactor, decimals: 2),
            minimumAvailableVideoZoomFactor: debugNumber(
                snapshot.minimumAvailableVideoZoomFactor,
                decimals: 2
            ),
            maximumAvailableVideoZoomFactor: debugNumber(
                snapshot.maximumAvailableVideoZoomFactor,
                decimals: 2
            ),
            manualFocusEnabled: snapshot.manualFocusEnabled ? "Sim" : "Nao",
            manualLensPosition: debugNumber(snapshot.manualLensPosition.map(Double.init), decimals: 3),
            manualFocusSupported: debugOptionalBool(snapshot.isManualFocusSupported),
            lockError: debugText(snapshot.lockError ?? "Nenhum"),
            lastArucoFocusTagId: debugOptionalInt(lastArucoFocusTagId),
            lastArucoFocusMarkerId: debugOptionalInt(lastArucoFocusMarkerId),
            lastArucoFocusPoint: debugPoint(lastArucoFocusPoint),
            lastArucoFocusRequestAge: debugSeconds(lastArucoFocusRequestAge),
            arucoFocusCooldown: debugSeconds(arucoFocusCooldown),
            lastArucoFocusError: debugText(lastArucoFocusError ?? "Nenhum"),
            focusAdjustingFrames: "\(focusAdjustingFrames)",
            focusRejectedFrames: "\(focusRejectedFrames)",
            blurRejectedFrames: "\(blurRejectedFrames)",
            exposureAdjustingFrames: "\(exposureAdjustingFrames)",
            whiteBalanceAdjustingFrames: "\(whiteBalanceAdjustingFrames)",
            unstableFrames: "\(unstableFrames)",
            intrinsicsChanged: intrinsicsChanged ? "Sim" : "Nao",
            deviceChanged: deviceChanged ? "Sim" : "Nao",
            formatChanged: formatChanged ? "Sim" : "Nao",
            resolutionChanged: resolutionChanged ? "Sim" : "Nao",
            warning: debugText(warning),
            lastBadFrameReason: debugText(lastBadFrameReason),
            distanceGuideSourceReliable: distanceGuideSourceReliable ? "Sim" : "Nao",
            distanceMm: debugMillimeters(distanceMm),
            distanceReady: distanceReady ? "Sim" : "Nao"
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

    private static func debugARKitSection(
        _ quality: ARKitFrameQuality,
        penalizedFrames: Int
    ) -> ScannerDebugSnapshot.ARKitSection {
        ScannerDebugSnapshot.ARKitSection(
            enabled: quality.isEnabled ? "Sim" : "Nao",
            available: quality.isAvailable ? "Sim" : "Nao",
            trackingState: debugText(quality.trackingStateText),
            reliable: quality.isTrackingReliable ? "Sim" : "Nao",
            hasTransform: quality.hasCameraTransform ? "Sim" : "Nao",
            hasIntrinsics: quality.hasIntrinsics ? "Sim" : "Nao",
            motionSinceLastFrame: debugMeters(quality.cameraMotionSinceLastFrame),
            intrinsicsChanged: quality.intrinsicsChanged ? "Sim" : "Nao",
            lightEstimate: debugText(quality.lightEstimateText),
            stabilityScore: debugUnitIntervalPercent(quality.stabilityScore),
            rotationStabilityScore: debugUnitIntervalPercent(quality.rotationStabilityScore),
            recent: quality.isRecent ? "Sim" : "Nao",
            penalizedFrames: "\(penalizedFrames)"
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
        Self.debugText(value)
    }

    private func debugBool(_ value: Bool) -> String {
        value ? "Sim" : "Nao"
    }

    private func lastArucoFocusRequestAge() -> Double? {
        guard let lastArucoFocusRequestTimestamp,
              lastArucoFocusRequestTimestamp.isFinite,
              let lastFrameTimestamp,
              lastFrameTimestamp.isFinite,
              lastFrameTimestamp >= lastArucoFocusRequestTimestamp
        else {
            return nil
        }

        return lastFrameTimestamp - lastArucoFocusRequestTimestamp
    }

    private static func debugPercent(_ value: Double?) -> String {
        guard let value, value.isFinite else {
            return ScannerDebugSnapshot.missingValue
        }

        return "\(String(format: "%.1f", value))%"
    }

    private static func debugUnitIntervalPercent(_ value: Double?) -> String {
        guard let value, value.isFinite else {
            return ScannerDebugSnapshot.missingValue
        }

        return debugPercent(min(max(value, 0.0), 1.0) * 100.0)
    }

    private static func debugNumber(_ value: Double?, decimals: Int) -> String {
        guard let value, value.isFinite else {
            return ScannerDebugSnapshot.missingValue
        }

        let safeDecimals = min(max(decimals, 0), 6)
        return String(format: "%.\(safeDecimals)f", value)
    }

    private static func debugExposureDuration(_ seconds: Double?) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0 else {
            return ScannerDebugSnapshot.missingValue
        }

        if seconds == 0 {
            return "0 s"
        }

        if seconds < 0.001 {
            return String(format: "%.0f us", seconds * 1_000_000.0)
        }

        if seconds < 1 {
            return String(format: "%.2f ms", seconds * 1_000.0)
        }

        return String(format: "%.3f s", seconds)
    }

    private static func debugSeconds(_ seconds: Double?) -> String {
        guard let seconds, seconds.isFinite else {
            return ScannerDebugSnapshot.missingValue
        }

        return "\(String(format: "%.2f", seconds)) s"
    }

    private static func debugMillimeters(_ value: Double?) -> String {
        guard let value, value.isFinite else {
            return ScannerDebugSnapshot.missingValue
        }

        return "\(String(format: "%.1f", value)) mm"
    }

    private static func debugMeters(_ value: Double?) -> String {
        guard let value, value.isFinite else {
            return ScannerDebugSnapshot.missingValue
        }

        if value < 0.001 {
            return "\(String(format: "%.2f", value * 1000.0)) mm"
        }

        return "\(String(format: "%.4f", value)) m"
    }

    private static func debugOptionalBool(_ value: Bool?) -> String {
        guard let value else {
            return ScannerDebugSnapshot.missingValue
        }

        return value ? "Sim" : "Nao"
    }

    private static func debugOptionalInt(_ value: Int?) -> String {
        guard let value else {
            return ScannerDebugSnapshot.missingValue
        }

        return "\(value)"
    }

    private static func debugPoint(_ point: CGPoint?) -> String {
        guard let point,
              point.x.isFinite,
              point.y.isFinite
        else {
            return ScannerDebugSnapshot.missingValue
        }

        return "\(String(format: "%.3f", Double(point.x))), \(String(format: "%.3f", Double(point.y)))"
    }

    private static func debugText(_ value: String?) -> String {
        guard let value, !value.isEmpty else {
            return ScannerDebugSnapshot.missingValue
        }

        return value
    }

    private static func debugIntList(_ values: [Int]) -> String {
        guard !values.isEmpty else {
            return ScannerDebugSnapshot.missingValue
        }

        return values.sorted().map(String.init).joined(separator: ", ")
    }
}
