import CoreGraphics
import Foundation

struct ScannerDebugSnapshot: Equatable {
    static let missingValue = "N/A"

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
        let staticPoseStabilityMode: String
        let requiredAngularCoverage: String
        let minimumDualTagFrames: String
        let minimumDualAngularCoverage: String
        let precisionModeV2: String
        let preferDualTagForFinalExport: String
        let minimumGoodFrames: String
        let targetValidFrames: String
        let minimumAllowedSharpness: String
        let minimumPreferredSharpness: String
        let lensPositionChangeThreshold: String
        let focusSettleTimeSeconds: String
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
        let focusRecoveryState: String
        let lastFocusTarget: String
        let lastFocusPoint: String
        let focusCooldownRemaining: String
        let arucoVisible: String
        let arucoLostAge: String
        let recoveringFocus: String
        let arucoLostCount: String
        let centerFocusRecoveryCount: String
        let distanceGuideState: String
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
        let screenAwake: String
        let idleTimerDisabled: String
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

    struct ExportQualitySection: Equatable {
        let confidence: String
        let highMarkers: String
        let mediumMarkers: String
        let lowMarkers: String
        let worstMarker: String
        let mainIssue: String
        let finalObservationsUsed: String
        let rejectedByFocus: String
        let rejectedByBlur: String
        let rejectedByCamera: String
        let rejectedByNormal: String
        let rejectedByFallback: String
        let rejectedByEdge: String
        let rejectedByMotion: String
        let penalizedByARKit: String
    }

    struct ExportGateSection: Equatable {
        let profile: String
        let scanConfidence: String
        let visualMarkerCount: String
        let currentPoseMarkerCount: String
        let observedMarkerCount: String
        let expectedMarkerCount: String
        let exportableMarkerCount: String
        let markerCountSummary: String
        let missingMarkerIds: String
        let invalidMarkerIds: String
        let lastBlockedReason: String
    }

    struct PerformanceSection: Equatable {
        let estimatedFPS: String
        let processedFrames: String
        let finalObservationBuffer: String
        let finalObservationsByMarker: String
        let finalObservationLimitPerMarker: String
        let staticPoseSamples: String
        let staticPosePairSamples: String
        let staticPosePlaneSamples: String
        let lastFrameProcessingTimeMs: String
        let diagnosticsUpdateHz: String
    }

    struct DiagnosticsSection: Equatable {
        let userFeedbackState: String
        let userFeedbackMessage: String
        let captureProgress: String
        let refinementProgress: String
        let friendlyBlockingReason: String
        let enabled: String
        let eventsCount: String
        let lastEvent: String
        let fileAvailable: String
        let fpsMean: String
        let fpsMin: String
        let scanDuration: String
        let expectedMarkerIds: String
        let unexpectedMarkerIdsSeen: String
        let currentBlockingReason: String
        let lastExportBlockReason: String
        let lastBlockingReasonBeforeExport: String
        let slowestMarker: String
        let slowestExpectedMarker: String
        let timeToAllMarkersSeen: String
        let timeToAllMarkersExportable: String
        let extraTimeAfter100Percent: String
        let distanceSamples: String
        let distanceValidPercent: String
        let normalFinalizationState: String
        let normalFinalizationStartedAt: String
        let normalFinalizationElapsed: String
        let normalFinalizationMaxSeconds: String
        let normalFinalizationStableSeconds: String
        let normalFinalizationFramesAccepted: String
        let normalFinalizationRejectedByFocus: String
        let normalFinalizationRejectedByMotion: String
        let normalFinalizationRejectedByReprojection: String
        let normalFinalizationRejectedByNormal: String
        let normalFinalizationWillAutoExport: String
        let normalFinalizationMinObservationsPerMarker: String
        let normalFinalizationTargetAverageObservationsPerMarker: String
        let normalFinalizationObservationsByMarker: String
        let normalFinalizationAverageObservationsPerMarker: String
        let normalFinalizationMinObservationsReached: String
        let normalFinalizationAverageObservationsReached: String
        let normalFinalizationNormalGatePassed: String
        let normalFinalizationWorstNormalStd: String
        let normalFinalizationMaturityGatePassed: String
        let normalFinalizationAutoExportReason: String
        let normalFinalizationBlockedReason: String
        let allExpectedMarkersAt100Percent: String
        let expectedMarkerProgressById: String
        let normalFinalizationCanStart: String
        let normalFinalizationCanAutoExport: String
    }

    struct FrameObservationsSection: Equatable {
        let enabled: String
        let bufferedFrames: String
        let bufferLimit: String
        let dropped: String
        let oldestTimestamp: String
        let newestTimestamp: String
        let framesWithMarkers: String
        let framesWithExpectedMarkers: String
        let marker0Observations: String
        let marker1Observations: String
        let marker2Observations: String
        let marker3Observations: String
        let incompleteExpectedPoseSets: String
        let poseMappingMismatches: String
        let pointCountMismatches: String
        let missingIntrinsics: String
        let nonFinitePoses: String
    }

    struct SessionObservationCaptureSection: Equatable {
        let enabled: String
        let active: String
        let completed: String
        let schema: String
        let enqueued: String
        let written: String
        let writeFailures: String
        let orderViolations: String
        let limitReached: String
        let fileSize: String
        let lastEnqueuedFrame: String
        let lastWrittenFrame: String
        let filename: String
    }

    struct PreAccumulationGateSection: Equatable {
        let diagnosticsEnabled: String
        let blockingEnabled: String
        let raw: String
        let wouldAccept: String
        let wouldReject: String
        let acceptRatio: String
        let rejectRatio: String
        let topRejectReason: String
        let frameMask: String
        let tooClose: String
        let tooFar: String
        let focusRisk: String
        let highReprojection: String
        let highMotion: String
        let invalidPose: String
        let missingOrInvalidIntrinsics: String
        let experimentalComparisonAvailable: String
        let agreement: String
        let disagreement: String
    }

    struct GuidedStaticSection: Equatable {
        let enabled: String
        let currentStage: String
        let stageProgress: String
        let stageState: String
        let completedStages: String
        let requiredStages: String
        let framesPerStage: String
        let minStableTime: String
        let maxNormalStdDegrees: String
        let requireAllMarkersPerStage: String
        let framesRejectedByFocus: String
        let framesRejectedByMotion: String
        let framesRejectedByNormal: String
        let framesRejectedByReprojection: String
        let markersSeenThisStage: String
        let markersAcceptedThisStage: String
    }

    struct GuidedStaticStageRow: Equatable, Identifiable {
        let stageIndex: Int
        let stageName: String
        let status: String
        let framesAccepted: String
        let framesRejectedByFocus: String
        let framesRejectedByMotion: String
        let framesRejectedByNormal: String
        let framesRejectedByReprojection: String
        let markersSeen: String
        let markersAccepted: String
        let normalStdDegreesMean: String

        var id: Int {
            stageIndex
        }
    }

    struct MarkerExportGateRow: Equatable, Identifiable {
        let markerId: Int
        let status: String
        let reason: String
        let visuallyRecent: String
        let hasCurrentPose: String
        let accumulatedObservations: String
        let finalObservationsUsed: String

        var id: Int {
            markerId
        }
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
    let exportQuality: ExportQualitySection
    let exportGate: ExportGateSection
    let performance: PerformanceSection
    let diagnostics: DiagnosticsSection
    let frameObservations: FrameObservationsSection
    let sessionObservationCapture: SessionObservationCaptureSection
    let preAccumulationGate: PreAccumulationGateSection
    let guidedStatic: GuidedStaticSection
    let isDualArucoV2: Bool
    let markerV2Rows: [MarkerV2Row]
    let markerExportGateRows: [MarkerExportGateRow]
    let guidedStaticStageRows: [GuidedStaticStageRow]
}

extension ScannerViewModel {
    var scannerDebugSnapshot: ScannerDebugSnapshot {
        let frameObservationDiagnostics = frameObservationDiagnosticsForDebug
        let sessionCaptureDiagnostics = scanSessionObservationCaptureDiagnosticsForDebug
        let preAccumulationDiagnostics = preAccumulationObservationGateDiagnosticsForDebug
        return ScannerDebugSnapshot(
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
                staticPoseStabilityMode: debugBool(staticPoseStabilityMode),
                requiredAngularCoverage: Self.debugPercent(scanRequiredAngularCoveragePercent),
                minimumDualTagFrames: "\(scanMinimumDualTagFrameCount)",
                minimumDualAngularCoverage: Self.debugPercent(scanRequiredDualAngularCoveragePercent),
                precisionModeV2: debugBool(precisionModeV2),
                preferDualTagForFinalExport: debugBool(preferDualTagForFinalExport),
                minimumGoodFrames: "\(scanMinimumGoodFrameCount)",
                targetValidFrames: "\(scanTargetValidFrameCount)",
                minimumAllowedSharpness: Self.debugNumber(minimumAllowedSharpness, decimals: 1),
                minimumPreferredSharpness: Self.debugNumber(minimumPreferredSharpness, decimals: 1),
                lensPositionChangeThreshold: Self.debugNumber(cameraLensPositionChangeThreshold, decimals: 3),
                focusSettleTimeSeconds: Self.debugSeconds(cameraFocusSettleTimeSeconds)
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
                focusRecoveryState: focusRecoveryState.debugTitle,
                lastFocusTarget: lastFocusTarget,
                lastFocusPoint: lastFocusPoint,
                focusCooldownRemaining: focusCooldownRemaining(at: lastFrameTimestamp),
                arucoVisible: isArucoVisibleForFocus,
                arucoLostAge: arucoLostAge(at: lastFrameTimestamp),
                recoveringFocus: focusRecoveryState == .recoveringFocus,
                arucoLostCount: arucoLostCount,
                centerFocusRecoveryCount: centerFocusRecoveryCount,
                distanceGuideState: distanceGuideStateTitle,
                lastArucoFocusError: lastArucoFocusErrorMessage,
                screenAwake: screenAwakeEnabled,
                idleTimerDisabled: idleTimerDisabled
            ),
            arkit: Self.debugARKitSection(
                currentARKitFrameQuality,
                penalizedFrames: scanARKitPenalizedFrameCount
            ),
            exportQuality: ScannerDebugSnapshot.ExportQualitySection(
                confidence: debugString(scanFinalConfidenceSummary),
                highMarkers: "\(scanFinalHighConfidenceMarkerCount)",
                mediumMarkers: "\(scanFinalMediumConfidenceMarkerCount)",
                lowMarkers: "\(scanFinalLowConfidenceMarkerCount)",
                worstMarker: debugString(scanFinalWorstMarkerSummary),
                mainIssue: debugString(scanFinalMainIssueSummary),
                finalObservationsUsed: "\(scanFinalUsedObservationCount)",
                rejectedByFocus: "\(scanFinalRejectedByFocusCount)",
                rejectedByBlur: "\(scanFinalRejectedByBlurCount)",
                rejectedByCamera: "\(scanFinalRejectedByCameraCount)",
                rejectedByNormal: "\(scanFinalRejectedByNormalCount)",
                rejectedByFallback: "\(scanFinalRejectedByFallbackCount)",
                rejectedByEdge: "\(scanFinalRejectedByEdgeCount)",
                rejectedByMotion: "\(scanFinalRejectedByMotionCount)",
                penalizedByARKit: "\(scanFinalPenalizedByARKitCount)"
            ),
            exportGate: ScannerDebugSnapshot.ExportGateSection(
                profile: exportGateMarkerProfile.debugTitle,
                scanConfidence: debugString(scanFinalConfidenceSummary),
                visualMarkerCount: "\(exportGateMarkerValidations.filter(\.isVisuallyRecent).count)",
                currentPoseMarkerCount: "\(exportGateMarkerValidations.filter(\.hasCurrentPose).count)",
                observedMarkerCount: "\(exportGateMarkerValidations.filter { $0.accumulatedObservationCount > 0 }.count)",
                expectedMarkerCount: exportGateExpectedMarkerCount > 0
                    ? "\(exportGateExpectedMarkerCount)"
                    : ScannerDebugSnapshot.missingValue,
                exportableMarkerCount: "\(exportGateExportableMarkerCount)",
                markerCountSummary: exportGateExpectedMarkerCount > 0
                    ? "\(exportGateExportableMarkerCount)/\(exportGateExpectedMarkerCount)"
                    : "\(exportGateExportableMarkerCount)",
                missingMarkerIds: Self.debugIntList(exportGateMissingMarkerIds),
                invalidMarkerIds: Self.debugIntList(exportGateInvalidMarkerIds),
                lastBlockedReason: debugString(exportGateBlockedReason ?? "Nenhum")
            ),
            performance: ScannerDebugSnapshot.PerformanceSection(
                estimatedFPS: Self.debugNumber(estimatedFPS, decimals: 1),
                processedFrames: "\(totalFramesReceived)",
                finalObservationBuffer:
                    "\(scanFinalPoseObservationCount) obs",
                finalObservationsByMarker: Self.debugIntDictionary(
                    scanFinalPoseObservationCountsByMarkerId,
                    valuePrefix: "M"
                ),
                finalObservationLimitPerMarker:
                    "\(scanFinalPoseObservationLimitPerMarker)/marker",
                staticPoseSamples: "\(scanStaticPoseSampleCount)",
                staticPosePairSamples: "\(scanStaticPosePairSampleCount)",
                staticPosePlaneSamples: "\(scanStaticPosePlaneSampleCount)",
                lastFrameProcessingTimeMs: Self.debugMilliseconds(scanLastFrameProcessingTimeMs),
                diagnosticsUpdateHz: Self.debugNumber(diagnosticsUpdateHz, decimals: 1)
            ),
            diagnostics: Self.debugDiagnosticsSection(
                currentScanDiagnosticsSnapshot,
                enabled: diagnosticsEnabled,
                fileAvailable: diagnosticsFileAvailable,
                lastExportBlockReason: exportGateBlockedReason,
                normalFinalizationState: normalFinalizationState,
                normalFinalizationStartedAtTimestamp: normalFinalizationStartedAtTimestamp,
                normalFinalizationElapsedSeconds: normalFinalizationElapsedSeconds(),
                normalFinalizationMaxSeconds: normalFinalizationMaxSecondsForDebug,
                normalFinalizationStableSecondsCollected: normalFinalizationStableSecondsCollected,
                normalFinalizationFramesAccepted: normalFinalizationFramesAccepted,
                normalFinalizationFramesRejectedByFocus: normalFinalizationFramesRejectedByFocus,
                normalFinalizationFramesRejectedByMotion: normalFinalizationFramesRejectedByMotion,
                normalFinalizationFramesRejectedByReprojection: normalFinalizationFramesRejectedByReprojection,
                normalFinalizationFramesRejectedByNormal: normalFinalizationFramesRejectedByNormal,
                normalFinalizationWillAutoExport: shouldUseNormalScanFinalization &&
                    normalFinalizationState == .stabilizing,
                normalFinalizationMinFinalObservationsPerMarker:
                    normalFinalizationMinFinalObservationsPerMarkerForDebug,
                normalFinalizationTargetAverageObservationsPerMarker:
                    normalFinalizationTargetAverageObservationsPerMarkerForDebug,
                normalFinalizationMinObservationsByMarker:
                    normalFinalizationMinObservationsByMarker,
                normalFinalizationAverageObservationsPerMarker:
                    normalFinalizationAverageObservationsPerMarker,
                normalFinalizationMinObservationsReached:
                    normalFinalizationMinObservationsReached,
                normalFinalizationAverageObservationsReached:
                    normalFinalizationAverageObservationsReached,
                normalFinalizationNormalGatePassed:
                    normalFinalizationNormalGatePassed,
                normalFinalizationWorstNormalStdDegrees:
                    normalFinalizationWorstNormalStdDegrees,
                normalFinalizationMaturityGatePassed:
                    normalFinalizationMaturityGatePassed,
                normalFinalizationAutoExportReason:
                    normalFinalizationAutoExportReason,
                normalFinalizationBlockedReason:
                    normalFinalizationBlockedReason,
                allExpectedMarkersAt100Percent:
                    normalFinalizationAllExpectedMarkersAt100Percent,
                expectedMarkerProgressById:
                    normalFinalizationExpectedMarkerProgressById,
                normalFinalizationCanStart:
                    normalFinalizationCanStart,
                normalFinalizationCanAutoExport:
                    normalFinalizationCanAutoExport,
                userFeedbackState: scanUserFeedbackState,
                userFeedbackMessage: scanUserFeedbackMessage,
                captureProgressPercent: scanCaptureProgressPercent,
                refinementProgressPercent: scanRefinementProgressPercent,
                friendlyBlockingReason: scanFriendlyBlockingReason
            ),
            frameObservations: ScannerDebugSnapshot.FrameObservationsSection(
                enabled: debugBool(frameObservationDiagnostics.frameObservationModelEnabled),
                bufferedFrames: "\(frameObservationDiagnostics.frameObservationCount)",
                bufferLimit: "\(frameObservationDiagnostics.frameObservationBufferLimit)",
                dropped: "\(frameObservationDiagnostics.frameObservationDroppedCount)",
                oldestTimestamp: Self.debugNumber(
                    frameObservationDiagnostics.frameObservationOldestTimestamp,
                    decimals: 3
                ),
                newestTimestamp: Self.debugNumber(
                    frameObservationDiagnostics.frameObservationNewestTimestamp,
                    decimals: 3
                ),
                framesWithMarkers:
                    "\(frameObservationDiagnostics.framesWithAnyMarkerObservationCount)",
                framesWithExpectedMarkers:
                    "\(frameObservationDiagnostics.framesWithExpectedMarkersObservationCount)",
                marker0Observations:
                    "\(frameObservationDiagnostics.perMarkerFrameObservationCount[0, default: 0])",
                marker1Observations:
                    "\(frameObservationDiagnostics.perMarkerFrameObservationCount[1, default: 0])",
                marker2Observations:
                    "\(frameObservationDiagnostics.perMarkerFrameObservationCount[2, default: 0])",
                marker3Observations:
                    "\(frameObservationDiagnostics.perMarkerFrameObservationCount[3, default: 0])",
                incompleteExpectedPoseSets:
                    "\(frameObservationDiagnostics.frameObservationIncompleteExpectedPoseSetCount)",
                poseMappingMismatches:
                    "\(frameObservationDiagnostics.frameObservationPoseMappingMismatchCount)",
                pointCountMismatches:
                    "\(frameObservationDiagnostics.frameObservationPointCountMismatchCount)",
                missingIntrinsics:
                    "\(frameObservationDiagnostics.frameObservationMissingIntrinsicsCount)",
                nonFinitePoses:
                    "\(frameObservationDiagnostics.frameObservationNonFinitePoseCount)"
            ),
            sessionObservationCapture: ScannerDebugSnapshot.SessionObservationCaptureSection(
                enabled: debugBool(sessionCaptureDiagnostics.enabled),
                active: debugBool(sessionCaptureDiagnostics.active),
                completed: debugBool(sessionCaptureDiagnostics.completed),
                schema: "\(sessionCaptureDiagnostics.schemaVersion)",
                enqueued: "\(sessionCaptureDiagnostics.framesEnqueued)",
                written: "\(sessionCaptureDiagnostics.framesWritten)",
                writeFailures: "\(sessionCaptureDiagnostics.frameWriteFailureCount)",
                orderViolations: "\(sessionCaptureDiagnostics.frameOrderViolationCount)",
                limitReached: debugBool(sessionCaptureDiagnostics.limitReached),
                fileSize: "\(sessionCaptureDiagnostics.fileSizeBytes)",
                lastEnqueuedFrame: sessionCaptureDiagnostics.lastEnqueuedFrameIndex.map(String.init)
                    ?? ScannerDebugSnapshot.missingValue,
                lastWrittenFrame: sessionCaptureDiagnostics.lastWrittenFrameIndex.map(String.init)
                    ?? ScannerDebugSnapshot.missingValue,
                filename: debugString(sessionCaptureDiagnostics.filename)
            ),
            preAccumulationGate: ScannerDebugSnapshot.PreAccumulationGateSection(
                diagnosticsEnabled: debugBool(preAccumulationDiagnostics.diagnosticsEnabled),
                blockingEnabled: debugBool(preAccumulationDiagnostics.blockingEnabled),
                raw: "\(preAccumulationDiagnostics.rawObservationCount)",
                wouldAccept: "\(preAccumulationDiagnostics.wouldAcceptCount)",
                wouldReject: "\(preAccumulationDiagnostics.wouldRejectCount)",
                acceptRatio: Self.debugUnitIntervalPercent(
                    preAccumulationDiagnostics.wouldAcceptRatio
                ),
                rejectRatio: Self.debugUnitIntervalPercent(
                    preAccumulationDiagnostics.wouldRejectRatio
                ),
                topRejectReason: debugString(
                    preAccumulationDiagnostics.topRejectReason
                ),
                frameMask: "\(preAccumulationDiagnostics.wouldRejectByFrameMaskCount)",
                tooClose: "\(preAccumulationDiagnostics.wouldRejectByTooCloseCount)",
                tooFar: "\(preAccumulationDiagnostics.wouldRejectByTooFarCount)",
                focusRisk: "\(preAccumulationDiagnostics.wouldRejectByFocusRiskCount)",
                highReprojection:
                    "\(preAccumulationDiagnostics.wouldRejectByHighReprojectionCount)",
                highMotion: "\(preAccumulationDiagnostics.wouldRejectByHighMotionCount)",
                invalidPose:
                    "\(preAccumulationDiagnostics.wouldRejectByInvalidPoseCount + preAccumulationDiagnostics.wouldRejectByNotFinitePoseCount)",
                missingOrInvalidIntrinsics:
                    "\(preAccumulationDiagnostics.wouldRejectByMissingIntrinsicsCount + preAccumulationDiagnostics.wouldRejectByInvalidIntrinsicsCount)",
                experimentalComparisonAvailable: debugBool(
                    preAccumulationDiagnostics.experimentalComparisonAvailable
                ),
                agreement: "\(preAccumulationDiagnostics.experimentalAgreementCount)",
                disagreement: "\(preAccumulationDiagnostics.experimentalDisagreementCount)"
            ),
            guidedStatic: Self.debugGuidedStaticSection(
                enabled: guidedStaticCaptureEnabled,
                currentStage: guidedStaticStageSnapshots.first {
                    $0.stageIndex == guidedStaticCurrentStageIndex && !$0.isCompleted
                },
                stageState: guidedStaticStageState,
                completedStageCount: guidedStaticCompletedStageCount,
                requiredStageCount: guidedStaticRequiredStages,
                framesPerStage: guidedStaticFramesPerStage,
                minStableTimeSeconds: guidedStaticMinStableTimeSeconds,
                maxNormalStdDegrees: guidedStaticMaxNormalStdDegreesPerStage,
                requireAllMarkersPerStage: guidedStaticRequireAllMarkersPerStage,
                framesRejectedByFocus: guidedStaticFramesRejectedByFocus,
                framesRejectedByMotion: guidedStaticFramesRejectedByMotion,
                framesRejectedByNormal: guidedStaticFramesRejectedByNormal,
                framesRejectedByReprojection: guidedStaticFramesRejectedByReprojection
            ),
            isDualArucoV2: markerProfile == .dualArucoV2,
            markerV2Rows: markerProfile == .dualArucoV2
                ? dualMarkerDebugStates
                    .sorted { $0.physicalMarkerId < $1.physicalMarkerId }
                    .map(Self.debugMarkerV2Row)
                : [],
            markerExportGateRows: exportGateMarkerValidations
                .sorted { $0.markerId < $1.markerId }
                .map(Self.debugMarkerExportGateRow),
            guidedStaticStageRows: guidedStaticStageSnapshots
                .sorted { $0.stageIndex < $1.stageIndex }
                .map(Self.debugGuidedStaticStageRow)
        )
    }

    private static func debugGuidedStaticSection(
        enabled: Bool,
        currentStage: GuidedStaticStageSnapshot?,
        stageState: String,
        completedStageCount: Int,
        requiredStageCount: Int,
        framesPerStage: Int,
        minStableTimeSeconds: Double,
        maxNormalStdDegrees: Double,
        requireAllMarkersPerStage: Bool,
        framesRejectedByFocus: Int,
        framesRejectedByMotion: Int,
        framesRejectedByNormal: Int,
        framesRejectedByReprojection: Int
    ) -> ScannerDebugSnapshot.GuidedStaticSection {
        let stageProgress: String
        let currentStageName: String
        let markersSeen: String
        let markersAccepted: String

        if let currentStage {
            currentStageName = currentStage.stageName
            stageProgress = "\(currentStage.framesAccepted)/\(framesPerStage)"
            markersSeen = debugIntList(currentStage.markersSeen)
            markersAccepted = debugIntList(currentStage.markersAccepted)
        } else {
            currentStageName = enabled ? "concluida" : ScannerDebugSnapshot.missingValue
            stageProgress = enabled ? "\(completedStageCount)/\(requiredStageCount) etapas" : ScannerDebugSnapshot.missingValue
            markersSeen = ScannerDebugSnapshot.missingValue
            markersAccepted = ScannerDebugSnapshot.missingValue
        }

        return ScannerDebugSnapshot.GuidedStaticSection(
            enabled: enabled ? "Sim" : "Nao",
            currentStage: currentStageName,
            stageProgress: stageProgress,
            stageState: debugText(stageState),
            completedStages: "\(completedStageCount)/\(requiredStageCount)",
            requiredStages: "\(requiredStageCount)",
            framesPerStage: "\(framesPerStage)",
            minStableTime: debugSeconds(minStableTimeSeconds),
            maxNormalStdDegrees: debugDegrees(maxNormalStdDegrees),
            requireAllMarkersPerStage: requireAllMarkersPerStage ? "Sim" : "Nao",
            framesRejectedByFocus: "\(framesRejectedByFocus)",
            framesRejectedByMotion: "\(framesRejectedByMotion)",
            framesRejectedByNormal: "\(framesRejectedByNormal)",
            framesRejectedByReprojection: "\(framesRejectedByReprojection)",
            markersSeenThisStage: markersSeen,
            markersAcceptedThisStage: markersAccepted
        )
    }

    private static func debugDiagnosticsSection(
        _ snapshot: ScanDiagnosticsSnapshot,
        enabled: Bool,
        fileAvailable: Bool,
        lastExportBlockReason: String?,
        normalFinalizationState: NormalScanFinalizationState,
        normalFinalizationStartedAtTimestamp: Double?,
        normalFinalizationElapsedSeconds: Double?,
        normalFinalizationMaxSeconds: Double,
        normalFinalizationStableSecondsCollected: Double,
        normalFinalizationFramesAccepted: Int,
        normalFinalizationFramesRejectedByFocus: Int,
        normalFinalizationFramesRejectedByMotion: Int,
        normalFinalizationFramesRejectedByReprojection: Int,
        normalFinalizationFramesRejectedByNormal: Int,
        normalFinalizationWillAutoExport: Bool,
        normalFinalizationMinFinalObservationsPerMarker: Int,
        normalFinalizationTargetAverageObservationsPerMarker: Int,
        normalFinalizationMinObservationsByMarker: [Int: Int],
        normalFinalizationAverageObservationsPerMarker: Double?,
        normalFinalizationMinObservationsReached: Bool,
        normalFinalizationAverageObservationsReached: Bool,
        normalFinalizationNormalGatePassed: Bool,
        normalFinalizationWorstNormalStdDegrees: Double?,
        normalFinalizationMaturityGatePassed: Bool,
        normalFinalizationAutoExportReason: String?,
        normalFinalizationBlockedReason: String?,
        allExpectedMarkersAt100Percent: Bool,
        expectedMarkerProgressById: [Int: Double],
        normalFinalizationCanStart: Bool,
        normalFinalizationCanAutoExport: Bool,
        userFeedbackState: String,
        userFeedbackMessage: String,
        captureProgressPercent: Double,
        refinementProgressPercent: Double?,
        friendlyBlockingReason: String
    ) -> ScannerDebugSnapshot.DiagnosticsSection {
        ScannerDebugSnapshot.DiagnosticsSection(
            userFeedbackState: debugText(userFeedbackState),
            userFeedbackMessage: debugText(userFeedbackMessage),
            captureProgress: debugPercent(captureProgressPercent),
            refinementProgress: debugPercent(refinementProgressPercent),
            friendlyBlockingReason: debugText(friendlyBlockingReason),
            enabled: enabled ? "Sim" : "Nao",
            eventsCount: "\(snapshot.eventsCount)",
            lastEvent: debugText(snapshot.lastEventName),
            fileAvailable: fileAvailable ? "Sim" : "Nao",
            fpsMean: debugNumber(snapshot.fpsMean, decimals: 1),
            fpsMin: debugNumber(snapshot.fpsMin, decimals: 1),
            scanDuration: debugSeconds(snapshot.scanDurationSeconds),
            expectedMarkerIds: debugIntList(snapshot.expectedMarkerIds),
            unexpectedMarkerIdsSeen: debugIntList(snapshot.unexpectedMarkerIdsSeen),
            currentBlockingReason: debugText(snapshot.currentBlockingReason),
            lastExportBlockReason: debugText(lastExportBlockReason),
            lastBlockingReasonBeforeExport: debugText(snapshot.lastBlockingReasonBeforeExport),
            slowestMarker: snapshot.slowestMarkerId.map { "M\($0)" } ?? ScannerDebugSnapshot.missingValue,
            slowestExpectedMarker: snapshot.slowestExpectedMarkerId.map { "M\($0)" } ??
                ScannerDebugSnapshot.missingValue,
            timeToAllMarkersSeen: debugSeconds(snapshot.timeToAllMarkersSeenSeconds),
            timeToAllMarkersExportable: debugSeconds(snapshot.timeToAllMarkersExportableSeconds),
            extraTimeAfter100Percent: debugSeconds(snapshot.extraTimeAfterAllMarkers100PercentSeconds),
            distanceSamples: "\(snapshot.distanceSamplesValid)/\(snapshot.distanceSamplesTotal)",
            distanceValidPercent: debugPercent(snapshot.distanceValidPercent),
            normalFinalizationState: normalFinalizationState.debugTitle,
            normalFinalizationStartedAt: normalFinalizationStartedAtTimestamp == nil
                ? ScannerDebugSnapshot.missingValue
                : "Sim",
            normalFinalizationElapsed: debugSeconds(normalFinalizationElapsedSeconds),
            normalFinalizationMaxSeconds: debugSeconds(normalFinalizationMaxSeconds),
            normalFinalizationStableSeconds: debugSeconds(normalFinalizationStableSecondsCollected),
            normalFinalizationFramesAccepted: "\(normalFinalizationFramesAccepted)",
            normalFinalizationRejectedByFocus: "\(normalFinalizationFramesRejectedByFocus)",
            normalFinalizationRejectedByMotion: "\(normalFinalizationFramesRejectedByMotion)",
            normalFinalizationRejectedByReprojection: "\(normalFinalizationFramesRejectedByReprojection)",
            normalFinalizationRejectedByNormal: "\(normalFinalizationFramesRejectedByNormal)",
            normalFinalizationWillAutoExport: normalFinalizationWillAutoExport ? "Sim" : "Nao",
            normalFinalizationMinObservationsPerMarker:
                "\(normalFinalizationMinFinalObservationsPerMarker)",
            normalFinalizationTargetAverageObservationsPerMarker:
                "\(normalFinalizationTargetAverageObservationsPerMarker)",
            normalFinalizationObservationsByMarker: debugIntDictionary(
                normalFinalizationMinObservationsByMarker,
                valuePrefix: "M"
            ),
            normalFinalizationAverageObservationsPerMarker:
                debugNumber(normalFinalizationAverageObservationsPerMarker, decimals: 1),
            normalFinalizationMinObservationsReached:
                normalFinalizationMinObservationsReached ? "Sim" : "Nao",
            normalFinalizationAverageObservationsReached:
                normalFinalizationAverageObservationsReached ? "Sim" : "Nao",
            normalFinalizationNormalGatePassed:
                normalFinalizationNormalGatePassed ? "Sim" : "Nao",
            normalFinalizationWorstNormalStd:
                debugDegrees(normalFinalizationWorstNormalStdDegrees),
            normalFinalizationMaturityGatePassed:
                normalFinalizationMaturityGatePassed ? "Sim" : "Nao",
            normalFinalizationAutoExportReason:
                debugText(normalFinalizationAutoExportReason),
            normalFinalizationBlockedReason:
                debugText(normalFinalizationBlockedReason),
            allExpectedMarkersAt100Percent:
                allExpectedMarkersAt100Percent ? "Sim" : "Nao",
            expectedMarkerProgressById:
                debugProgressDictionary(expectedMarkerProgressById, valuePrefix: "M"),
            normalFinalizationCanStart:
                normalFinalizationCanStart ? "Sim" : "Nao",
            normalFinalizationCanAutoExport:
                normalFinalizationCanAutoExport ? "Sim" : "Nao"
        )
    }

    private static func debugGuidedStaticStageRow(
        _ stage: GuidedStaticStageSnapshot
    ) -> ScannerDebugSnapshot.GuidedStaticStageRow {
        ScannerDebugSnapshot.GuidedStaticStageRow(
            stageIndex: stage.stageIndex,
            stageName: stage.stageName,
            status: stage.isCompleted ? "concluida" : "pendente",
            framesAccepted: "\(stage.framesAccepted)",
            framesRejectedByFocus: "\(stage.framesRejectedByFocus)",
            framesRejectedByMotion: "\(stage.framesRejectedByMotion)",
            framesRejectedByNormal: "\(stage.framesRejectedByNormal)",
            framesRejectedByReprojection: "\(stage.framesRejectedByReprojection)",
            markersSeen: debugIntList(stage.markersSeen),
            markersAccepted: debugIntList(stage.markersAccepted),
            normalStdDegreesMean: debugDegrees(stage.normalStdDegreesMean)
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
        focusRecoveryState: String,
        lastFocusTarget: String,
        lastFocusPoint: CGPoint?,
        focusCooldownRemaining: Double?,
        arucoVisible: Bool,
        arucoLostAge: Double,
        recoveringFocus: Bool,
        arucoLostCount: Int,
        centerFocusRecoveryCount: Int,
        distanceGuideState: String,
        lastArucoFocusError: String?,
        screenAwake: Bool,
        idleTimerDisabled: Bool
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
            focusRecoveryState: debugText(focusRecoveryState),
            lastFocusTarget: debugText(lastFocusTarget),
            lastFocusPoint: debugPoint(lastFocusPoint),
            focusCooldownRemaining: debugSeconds(focusCooldownRemaining),
            arucoVisible: arucoVisible ? "Sim" : "Nao",
            arucoLostAge: arucoLostAge.isFinite ? debugSeconds(arucoLostAge) : ScannerDebugSnapshot.missingValue,
            recoveringFocus: recoveringFocus ? "Sim" : "Nao",
            arucoLostCount: "\(arucoLostCount)",
            centerFocusRecoveryCount: "\(centerFocusRecoveryCount)",
            distanceGuideState: debugText(distanceGuideState),
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
            distanceReady: distanceReady ? "Sim" : "Nao",
            screenAwake: screenAwake ? "on" : "off",
            idleTimerDisabled: idleTimerDisabled ? "true" : "false"
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

    private static func debugMarkerExportGateRow(
        _ validation: ExportableMarkerValidation
    ) -> ScannerDebugSnapshot.MarkerExportGateRow {
        ScannerDebugSnapshot.MarkerExportGateRow(
            markerId: validation.markerId,
            status: validation.isExportable ? "exportavel" : "nao exportavel",
            reason: debugText(validation.reason ?? "ok"),
            visuallyRecent: validation.isVisuallyRecent ? "Sim" : "Nao",
            hasCurrentPose: validation.hasCurrentPose ? "Sim" : "Nao",
            accumulatedObservations: "\(validation.accumulatedObservationCount)",
            finalObservationsUsed: validation.finalObservationsUsed.map(String.init) ??
                ScannerDebugSnapshot.missingValue
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

    private static func debugMilliseconds(_ milliseconds: Double?) -> String {
        guard let milliseconds, milliseconds.isFinite else {
            return ScannerDebugSnapshot.missingValue
        }

        return "\(String(format: "%.1f", milliseconds)) ms"
    }

    private static func debugMillimeters(_ value: Double?) -> String {
        guard let value, value.isFinite else {
            return ScannerDebugSnapshot.missingValue
        }

        return "\(String(format: "%.1f", value)) mm"
    }

    private static func debugDegrees(_ value: Double?) -> String {
        guard let value, value.isFinite else {
            return ScannerDebugSnapshot.missingValue
        }

        return "\(String(format: "%.1f", value)) deg"
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

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ScannerDebugSnapshot.missingValue
        }

        let lowercased = trimmed.lowercased()
        if lowercased == "nan" ||
            lowercased == "inf" ||
            lowercased == "infinity" ||
            lowercased == "-inf" ||
            lowercased == "-infinity" {
            return ScannerDebugSnapshot.missingValue
        }

        return trimmed
    }

    private static func debugIntList(_ values: [Int]) -> String {
        guard !values.isEmpty else {
            return ScannerDebugSnapshot.missingValue
        }

        return values.sorted().map(String.init).joined(separator: ", ")
    }

    private static func debugIntDictionary(
        _ values: [Int: Int],
        valuePrefix: String = ""
    ) -> String {
        guard !values.isEmpty else {
            return ScannerDebugSnapshot.missingValue
        }

        return values
            .keys
            .sorted()
            .prefix(16)
            .map { key in "\(valuePrefix)\(key): \(values[key] ?? 0)" }
            .joined(separator: ", ")
    }

    private static func debugProgressDictionary(
        _ values: [Int: Double],
        valuePrefix: String = ""
    ) -> String {
        guard !values.isEmpty else {
            return ScannerDebugSnapshot.missingValue
        }

        return values
            .keys
            .sorted()
            .prefix(16)
            .map { key in
                let value = values[key]
                return "\(valuePrefix)\(key): \(debugPercent(value))"
            }
            .joined(separator: ", ")
    }
}
