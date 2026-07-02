import Foundation

final class ScanDiagnosticsRecorder {
    private struct MarkerState {
        var firstSeenAt: Double?
        var lastSeenAt: Double?
        var totalVisibleSeconds: Double = 0
        var becameExportableAt: Double?
        var observationsAccumulated: Int = 0
        var finalObservationsUsed: Int?
        var qualityScore: Double?
        var normalStdDegrees: Double?
        var reprojectionError: Double?
        var exportable: Bool = false
        var invalidReason: String?
        var waitingReason: String?
    }

    private let maxEvents: Int
    private var events: [ScanDiagnosticEvent] = []
    private var markerStates: [Int: MarkerState] = [:]
    private var scanStartedAt: Double?
    private var createdAt: String?
    private var markerProfile: String?
    private var expectedMarkerIds: [Int] = []
    private var expectedMarkerIdSet: Set<Int> = []
    private var unexpectedMarkerIdsSeen: Set<Int> = []
    private var allMarkersSeenAt: Double?
    private var allMarkersExportableAt: Double?
    private var firstMarkerSeenAt: Double?
    private var fpsSum: Double = 0
    private var fpsSampleCount: Int = 0
    private var fpsMinValue: Double?
    private var distanceSampleCount: Int = 0
    private var distanceValidSampleCount: Int = 0
    private var lastDistanceState: String?
    private var lastFocusStable: Bool?
    private var didRecordFPSDrop = false
    private(set) var lastSnapshot: ScanDiagnosticsSnapshot = .empty

    init(maxEvents: Int = 500) {
        self.maxEvents = max(10, maxEvents)
    }

    func startScan(
        markerProfile: String,
        expectedMarkerIds: [Int],
        timestamp: Double,
        createdAt: String
    ) {
        events = []
        markerStates = [:]
        scanStartedAt = sanitizedTimestamp(timestamp)
        self.createdAt = createdAt
        self.markerProfile = markerProfile
        self.expectedMarkerIds = expectedMarkerIds.sorted()
        expectedMarkerIdSet = Set(expectedMarkerIds)
        unexpectedMarkerIdsSeen = []
        allMarkersSeenAt = nil
        allMarkersExportableAt = nil
        firstMarkerSeenAt = nil
        fpsSum = 0
        fpsSampleCount = 0
        fpsMinValue = nil
        distanceSampleCount = 0
        distanceValidSampleCount = 0
        lastDistanceState = nil
        lastFocusStable = nil
        didRecordFPSDrop = false
        lastSnapshot = .empty

        for markerId in expectedMarkerIds {
            markerStates[markerId] = MarkerState()
        }

        record(
            name: "scan_started",
            timestamp: timestamp,
            metadata: ["markerProfile": markerProfile]
        )
    }

    func record(
        name: String,
        timestamp: Double,
        markerId: Int? = nil,
        message: String? = nil,
        metadata: [String: String]? = nil
    ) {
        let event = ScanDiagnosticEvent(
            name: name,
            timestampSeconds: relativeTime(from: timestamp),
            markerId: markerId,
            message: message,
            metadata: metadata
        )
        events.append(event)
        if events.count > maxEvents {
            events.removeFirst(events.count - maxEvents)
        }
    }

    func recordFrame(
        timestamp: Double,
        fps: Double,
        accepted: Bool,
        rejectedByFocus: Bool,
        rejectedByBlur: Bool,
        rejectedByMotion: Bool,
        rejectedByNormal: Bool,
        rejectedByReprojection: Bool
    ) {
        if fps.isFinite, fps > 0 {
            fpsSum += fps
            fpsSampleCount += 1
            fpsMinValue = min(fpsMinValue ?? fps, fps)
            if fps < 15.0, !didRecordFPSDrop {
                record(name: "fps_drop_detected", timestamp: timestamp, message: String(format: "%.1f fps", fps))
                didRecordFPSDrop = true
            }
        }

        var snapshot = lastSnapshot
        snapshot.framesProcessed += 1
        if accepted {
            snapshot.framesAccepted += 1
        }
        if rejectedByFocus {
            snapshot.framesRejectedByFocus += 1
        }
        if rejectedByBlur {
            snapshot.framesRejectedByBlur += 1
        }
        if rejectedByMotion {
            snapshot.framesRejectedByMotion += 1
        }
        if rejectedByNormal {
            snapshot.framesRejectedByNormal += 1
        }
        if rejectedByReprojection {
            snapshot.framesRejectedByReprojection += 1
        }
        lastSnapshot = snapshot
    }

    func recordFocusState(isStable: Bool, timestamp: Double) {
        guard lastFocusStable != isStable else {
            return
        }

        if let lastFocusStable {
            record(
                name: isStable ? "focus_recovered" : "focus_lost",
                timestamp: timestamp,
                message: lastFocusStable ? "focus changed" : nil
            )
        }
        lastFocusStable = isStable
    }

    func recordDistanceState(
        state: String,
        distanceMm: Double?,
        isReliable: Bool,
        timestamp: Double
    ) {
        distanceSampleCount += 1
        if isReliableDistanceSample(state: state, distanceMm: distanceMm, isReliable: isReliable) {
            distanceValidSampleCount += 1
        }

        guard lastDistanceState != state else {
            return
        }

        record(
            name: "distance_state_changed",
            timestamp: timestamp,
            message: state,
            metadata: distanceMm.flatMap { $0.isFinite ? ["distanceMm": String(format: "%.1f", $0)] : nil }
        )
        lastDistanceState = state
    }

    func recordMarkersSeen(
        markerIds: [Int],
        timestamp: Double,
        expectedMarkerIds: [Int]
    ) {
        let relativeTimestamp = relativeTime(from: timestamp)
        for markerId in markerIds {
            guard expectedMarkerIdSet.contains(markerId) else {
                if unexpectedMarkerIdsSeen.insert(markerId).inserted {
                    record(
                        name: "unexpected_marker_seen",
                        timestamp: timestamp,
                        markerId: markerId
                    )
                }
                continue
            }

            var state = markerStates[markerId] ?? MarkerState()
            if state.firstSeenAt == nil {
                state.firstSeenAt = relativeTimestamp
                if firstMarkerSeenAt == nil {
                    firstMarkerSeenAt = relativeTimestamp
                    record(name: "marker_seen", timestamp: timestamp, markerId: markerId)
                } else {
                    record(name: "marker_seen", timestamp: timestamp, markerId: markerId)
                }
            }
            if let lastSeenAt = state.lastSeenAt,
               relativeTimestamp > lastSeenAt {
                state.totalVisibleSeconds += min(relativeTimestamp - lastSeenAt, 1.0)
            }
            state.lastSeenAt = relativeTimestamp
            markerStates[markerId] = state
        }

        if allMarkersSeenAt == nil {
            if !expectedMarkerIdSet.isEmpty,
               expectedMarkerIdSet.allSatisfy({ markerStates[$0]?.firstSeenAt != nil }) {
                allMarkersSeenAt = relativeTimestamp
            }
        }
    }

    func updateMarkerSummaries(
        validations: [ExportableMarkerValidation],
        diagnosticsByMarkerId: [Int: FinalPoseObservationSelectionDiagnostics],
        timestamp: Double,
        expectedMarkerIds: [Int]
    ) {
        let relativeTimestamp = relativeTime(from: timestamp)
        let previousExportableIds = Set(markerStates.compactMap { $0.value.exportable ? $0.key : nil })

        for validation in validations {
            guard expectedMarkerIdSet.contains(validation.markerId) else {
                if unexpectedMarkerIdsSeen.insert(validation.markerId).inserted {
                    record(
                        name: "unexpected_marker_seen",
                        timestamp: timestamp,
                        markerId: validation.markerId,
                        message: "export_validation"
                    )
                }
                continue
            }

            var state = markerStates[validation.markerId] ?? MarkerState()
            state.observationsAccumulated = validation.accumulatedObservationCount
            state.finalObservationsUsed = validation.finalObservationsUsed
            state.exportable = validation.isExportable
            state.invalidReason = validation.isExportable ? nil : validation.reason
            state.waitingReason = validation.isExportable ? nil : validation.reason

            if validation.isExportable, state.becameExportableAt == nil {
                state.becameExportableAt = relativeTimestamp
                record(name: "marker_exportable", timestamp: timestamp, markerId: validation.markerId)
            } else if !validation.isExportable,
                      let reason = validation.reason,
                      !reason.isEmpty {
                record(name: "marker_invalid", timestamp: timestamp, markerId: validation.markerId, message: reason)
            }

            if let diagnostics = diagnosticsByMarkerId[validation.markerId] {
                state.finalObservationsUsed = diagnostics.selectedObservationCount
                state.qualityScore = diagnostics.finalAverageQualityScore
                state.normalStdDegrees = diagnostics.finalNormalStdDevDegrees
                state.reprojectionError = diagnostics.finalAverageReprojectionError
            }
            markerStates[validation.markerId] = state
        }

        let exportableIds = Set(markerStates.compactMap { $0.value.exportable ? $0.key : nil })
        if allMarkersExportableAt == nil,
           !expectedMarkerIdSet.isEmpty,
           expectedMarkerIdSet.allSatisfy({ exportableIds.contains($0) }) {
            allMarkersExportableAt = relativeTimestamp
        }

        for lostMarkerId in previousExportableIds.subtracting(exportableIds) {
            record(name: "marker_lost", timestamp: timestamp, markerId: lostMarkerId)
        }
    }

    func makeSnapshot(
        timestamp: Double,
        markerProfile: String,
        deviceModelIdentifier: String?,
        deviceMarketingName: String?,
        cameraProfileId: String?,
        cameraProfileName: String?,
        cameraRecommendedProfileId: String?,
        cameraRecommendedProfileName: String?,
        cameraProfileTooCloseFocusRiskDistanceMm: Double?,
        cameraProfilePreferredMinScanDistanceMm: Double?,
        cameraProfilePreferredIdealMinScanDistanceMm: Double?,
        cameraProfilePreferredIdealMaxScanDistanceMm: Double?,
        cameraProfilePreferredMaxScanDistanceMm: Double?,
        deviceQualityClass: String?,
        deviceQualityProfileName: String?,
        deviceQualityIsKnown: Bool?,
        deviceQualityWarning: String?,
        deviceQualityMinDistanceMm: Double?,
        deviceQualityIdealMinDistanceMm: Double?,
        deviceQualityIdealMaxDistanceMm: Double?,
        deviceQualityMaxDistanceMm: Double?,
        deviceQualityTooCloseFocusRiskDistanceMm: Double?,
        deviceQualityFocusVarianceThreshold: Double?,
        deviceQualityOverlayScale: Double?,
        deviceQualityFrameMaskVerticalBorderPercent: Double?,
        deviceQualityFrameMaskHorizontalBorderPercent: Double?,
        selectedCameraLocalizedName: String?,
        selectedCameraDeviceType: String?,
        requestedZoomFactor: Double?,
        appliedZoomFactor: Double?,
        currentVideoZoomFactor: Double?,
        focusMode: String?,
        exposureMode: String?,
        isAdjustingFocus: Bool?,
        isAdjustingExposure: Bool?,
        cameraIntrinsicMatrixAvailable: Bool?,
        cameraIntrinsicFx: Double?,
        cameraIntrinsicFy: Double?,
        cameraIntrinsicCx: Double?,
        cameraIntrinsicCy: Double?,
        activeVideoDimensions: String?,
        activeFormatDescription: String?,
        cameraProfileEvaluationScore: Double?,
        cameraProfileEvaluationWarnings: [String]?,
        exportGateReason: String?,
        scanConfidence: String?,
        mainIssue: String?,
        focusRecoveryState: String?,
        focusRecoveryCount: Int,
        arucoLostCount: Int,
        centerFocusRecoveryCount: Int,
        distanceGuideState: String?,
        distanceGuideMessage: String?,
        lastDistanceMm: Double?,
        distanceGuideBarMinMm: Double?,
        distanceGuideBarMaxMm: Double?,
        distanceGuideIdealBandMinMm: Double?,
        distanceGuideIdealBandMaxMm: Double?,
        frameMaskDiagnostics: FrameMaskDiagnostics?,
        experimentalQualityDiagnostics: ExperimentalQualityDiagnostics?,
        userFeedbackState: String?,
        userFeedbackMessage: String?,
        captureProgressPercent: Double?,
        refinementProgressPercent: Double?,
        friendlyBlockingReason: String?,
        currentBlockingReason: String?,
        lastBlockingReasonBeforeExport: String?,
        normalFinalizationState: String?,
        normalFinalizationStartedAt: Double?,
        normalFinalizationDurationSeconds: Double?,
        normalFinalizationFramesAccepted: Int,
        normalFinalizationFramesRejectedByFocus: Int,
        normalFinalizationFramesRejectedByMotion: Int,
        normalFinalizationFramesRejectedByReprojection: Int,
        normalFinalizationFramesRejectedByNormal: Int,
        autoExportTriggered: Bool,
        normalFinalizationMinFinalObservationsPerMarker: Int?,
        normalFinalizationTargetAverageObservationsPerMarker: Int?,
        normalFinalizationMinObservationsReached: Bool?,
        normalFinalizationAverageObservationsReached: Bool?,
        normalFinalizationAverageObservationsPerMarker: Double?,
        normalFinalizationMaxNormalStdDegrees: Double?,
        normalFinalizationNormalGatePassed: Bool?,
        normalFinalizationMaturityGatePassed: Bool?,
        normalFinalizationAutoExportReason: String?,
        normalFinalizationBlockedReason: String?,
        normalFinalizationMinObservationsByMarker: [Int: Int]?,
        allExpectedMarkersAt100Percent: Bool?,
        expectedMarkerProgressById: [Int: Double]?,
        usedBestFinalPoseCandidate: Bool?,
        bestFinalPoseCandidateSaved: Bool?,
        bestFinalPoseCandidateScore: Double?,
        bestFinalPoseCandidateTimestamp: Double?,
        bestFinalPoseCandidateLastUpdatedAt: Double?,
        bestFinalPoseCandidateAgeSeconds: Double?,
        bestFinalPoseCandidateWorstNormalStd: Double?,
        bestFinalPoseCandidateWorstReprojection: Double?,
        bestFinalPoseCandidateObservationsByMarker: [Int: Int]?,
        bestFinalPoseCandidateReason: String?,
        bestFinalPoseCandidateMarkerIds: [Int]?,
        bestFinalPoseCandidateHasExportablePoses: Bool?,
        bestFinalPoseCandidateAcceptedCount: Int?,
        bestFinalPoseCandidateLastRejectReason: String?,
        bestFinalPoseCandidateGeometryAdjustedScore: Double?,
        bestFinalPoseCandidateGeometryPenalty: Double?,
        bestFinalPoseCandidateGeometryScoreSource: String?,
        relativeMarkerDistanceM01: Double?,
        relativeMarkerDistanceM02: Double?,
        relativeMarkerDistanceM03: Double?,
        relativeMarkerDistanceM12: Double?,
        relativeMarkerDistanceM13: Double?,
        relativeMarkerDistanceM23: Double?,
        relativeMarkerDistanceStdMean: Double?,
        relativeMarkerDistanceStdMax: Double?,
        relativeMarkerGeometryScore: Double?,
        candidateVsFinalTranslationDeltaMean: Double?,
        candidateVsFinalRotationDeltaMean: Double?,
        candidateVsFinalGeometryDelta: Double?,
        markerFrameMaskDiagnosticsByMarkerId: [Int: MarkerFrameMaskDiagnostics],
        experimentalMarkerDiagnosticsByMarkerId: [Int: ExperimentalMarkerQualityDiagnostics],
        guidedStaticCaptureEnabled: Bool,
        guidedStages: [ScanDiagnosticsSnapshot.GuidedStageSummary]?
    ) -> ScanDiagnosticsSnapshot {
        let currentRelativeTime = relativeTime(from: timestamp)
        let slowestExpectedMarkerId = markerStates
            .filter { expectedMarkerIdSet.contains($0.key) && ($0.value.becameExportableAt != nil || $0.value.firstSeenAt != nil) }
            .max { lhs, rhs in
                let lhsTime = lhs.value.becameExportableAt ?? currentRelativeTime
                let rhsTime = rhs.value.becameExportableAt ?? currentRelativeTime
                return lhsTime < rhsTime
            }?
            .key

        let distanceValidPercent = distanceSampleCount > 0
            ? Double(distanceValidSampleCount) / Double(distanceSampleCount) * 100.0
            : nil

        let markerSummaries = expectedMarkerIds
            .sorted()
            .map { markerId in
                let state = markerStates[markerId] ?? MarkerState()
                let frameMaskDiagnostics = markerFrameMaskDiagnosticsByMarkerId[markerId]
                let experimentalDiagnostics = experimentalMarkerDiagnosticsByMarkerId[markerId]
                return ScanDiagnosticsSnapshot.MarkerSummary(
                    markerId: markerId,
                    firstSeenAtSeconds: finite(state.firstSeenAt),
                    becameExportableAtSeconds: finite(state.becameExportableAt),
                    totalVisibleSeconds: finite(state.totalVisibleSeconds),
                    observationsAccumulated: state.observationsAccumulated,
                    finalObservationsUsed: state.finalObservationsUsed,
                    qualityScore: finite(state.qualityScore),
                    normalStdDegrees: finite(state.normalStdDegrees),
                    reprojectionError: finite(state.reprojectionError),
                    exportable: state.exportable,
                    invalidReason: state.invalidReason,
                    waitingReason: state.waitingReason,
                    markerFrameCenterX: finite(frameMaskDiagnostics?.markerFrameCenterX),
                    markerFrameCenterY: finite(frameMaskDiagnostics?.markerFrameCenterY),
                    markerFrameNormalizedCenterX: finite(frameMaskDiagnostics?.markerFrameNormalizedCenterX),
                    markerFrameNormalizedCenterY: finite(frameMaskDiagnostics?.markerFrameNormalizedCenterY),
                    markerFrameMinX: finite(frameMaskDiagnostics?.markerFrameMinX),
                    markerFrameMinY: finite(frameMaskDiagnostics?.markerFrameMinY),
                    markerFrameMaxX: finite(frameMaskDiagnostics?.markerFrameMaxX),
                    markerFrameMaxY: finite(frameMaskDiagnostics?.markerFrameMaxY),
                    markerInsideFrameMask: frameMaskDiagnostics?.markerInsideFrameMask,
                    markerFrameMaskViolation: frameMaskDiagnostics?.markerFrameMaskViolation,
                    markerDistanceToFrameMaskEdgePx:
                        finite(frameMaskDiagnostics?.markerDistanceToFrameMaskEdgePx),
                    markerDistanceToFrameMaskEdgeNormalized:
                        finite(frameMaskDiagnostics?.markerDistanceToFrameMaskEdgeNormalized),
                    markerNearFrameEdgeWarning: frameMaskDiagnostics?.markerNearFrameEdgeWarning,
                    markerExperimentalRawObservationCount:
                        experimentalDiagnostics?.rawObservationCount,
                    markerExperimentalAcceptedObservationCount:
                        experimentalDiagnostics?.acceptedObservationCount,
                    markerExperimentalRejectedObservationCount:
                        experimentalDiagnostics?.rejectedObservationCount,
                    markerExperimentalRejectedByFrameMaskCount:
                        experimentalDiagnostics?.rejectedByFrameMaskCount,
                    markerExperimentalRejectedByTooCloseCount:
                        experimentalDiagnostics?.rejectedByTooCloseCount,
                    markerExperimentalRejectedByTooFarCount:
                        experimentalDiagnostics?.rejectedByTooFarCount,
                    markerExperimentalRejectedByFocusRiskCount:
                        experimentalDiagnostics?.rejectedByFocusRiskCount,
                    markerExperimentalRejectedByInvalidPoseCount:
                        experimentalDiagnostics?.rejectedByInvalidPoseCount,
                    markerExperimentalRejectedByNotFiniteCount:
                        experimentalDiagnostics?.rejectedByNotFiniteCount,
                    markerExperimentalRejectedByUnknownCount:
                        experimentalDiagnostics?.rejectedByUnknownCount,
                    markerExperimentalUsefulProgress:
                        finite(experimentalDiagnostics?.usefulProgress),
                    markerExperimentalUsefulReady:
                        experimentalDiagnostics?.usefulReady
                )
            }

        let snapshot = ScanDiagnosticsSnapshot(
            createdAt: createdAt,
            markerProfile: markerProfile,
            deviceModelIdentifier: deviceModelIdentifier,
            deviceMarketingName: deviceMarketingName,
            cameraProfileId: cameraProfileId,
            cameraProfileName: cameraProfileName,
            cameraRecommendedProfileId: cameraRecommendedProfileId,
            cameraRecommendedProfileName: cameraRecommendedProfileName,
            cameraProfileTooCloseFocusRiskDistanceMm: finite(cameraProfileTooCloseFocusRiskDistanceMm),
            cameraProfilePreferredMinScanDistanceMm: finite(cameraProfilePreferredMinScanDistanceMm),
            cameraProfilePreferredIdealMinScanDistanceMm:
                finite(cameraProfilePreferredIdealMinScanDistanceMm),
            cameraProfilePreferredIdealMaxScanDistanceMm:
                finite(cameraProfilePreferredIdealMaxScanDistanceMm),
            cameraProfilePreferredMaxScanDistanceMm: finite(cameraProfilePreferredMaxScanDistanceMm),
            deviceQualityClass: deviceQualityClass,
            deviceQualityProfileName: deviceQualityProfileName,
            deviceQualityIsKnown: deviceQualityIsKnown,
            deviceQualityWarning: deviceQualityWarning,
            deviceQualityMinDistanceMm: finite(deviceQualityMinDistanceMm),
            deviceQualityIdealMinDistanceMm: finite(deviceQualityIdealMinDistanceMm),
            deviceQualityIdealMaxDistanceMm: finite(deviceQualityIdealMaxDistanceMm),
            deviceQualityMaxDistanceMm: finite(deviceQualityMaxDistanceMm),
            deviceQualityTooCloseFocusRiskDistanceMm: finite(deviceQualityTooCloseFocusRiskDistanceMm),
            deviceQualityFocusVarianceThreshold: finite(deviceQualityFocusVarianceThreshold),
            deviceQualityOverlayScale: finite(deviceQualityOverlayScale),
            deviceQualityFrameMaskVerticalBorderPercent: finite(deviceQualityFrameMaskVerticalBorderPercent),
            deviceQualityFrameMaskHorizontalBorderPercent:
                finite(deviceQualityFrameMaskHorizontalBorderPercent),
            selectedCameraLocalizedName: selectedCameraLocalizedName,
            selectedCameraDeviceType: selectedCameraDeviceType,
            requestedZoomFactor: finite(requestedZoomFactor),
            appliedZoomFactor: finite(appliedZoomFactor),
            currentVideoZoomFactor: finite(currentVideoZoomFactor),
            focusMode: focusMode,
            exposureMode: exposureMode,
            isAdjustingFocus: isAdjustingFocus,
            isAdjustingExposure: isAdjustingExposure,
            cameraIntrinsicMatrixAvailable: cameraIntrinsicMatrixAvailable,
            cameraIntrinsicFx: finite(cameraIntrinsicFx),
            cameraIntrinsicFy: finite(cameraIntrinsicFy),
            cameraIntrinsicCx: finite(cameraIntrinsicCx),
            cameraIntrinsicCy: finite(cameraIntrinsicCy),
            activeVideoDimensions: activeVideoDimensions,
            activeFormatDescription: activeFormatDescription,
            cameraProfileEvaluationScore: finite(cameraProfileEvaluationScore),
            cameraProfileEvaluationWarnings:
                cameraProfileEvaluationWarnings?.isEmpty == true ? nil : cameraProfileEvaluationWarnings,
            scanDurationSeconds: finite(currentRelativeTime),
            timeToFirstMarkerSeconds: finite(firstMarkerSeenAt),
            timeToAllMarkersSeenSeconds: finite(allMarkersSeenAt),
            timeToAllMarkersExportableSeconds: finite(allMarkersExportableAt),
            extraTimeAfterAllMarkers100PercentSeconds: extraTimeAfterAllMarkersExportable(
                currentRelativeTime: currentRelativeTime
            ),
            expectedMarkerIds: expectedMarkerIds,
            unexpectedMarkerIdsSeen: unexpectedMarkerIdsSeen.sorted(),
            fpsMean: fpsSampleCount > 0 ? finite(fpsSum / Double(fpsSampleCount)) : nil,
            fpsMin: finite(fpsMinValue),
            framesProcessed: lastSnapshot.framesProcessed,
            framesAccepted: lastSnapshot.framesAccepted,
            framesRejectedByFocus: lastSnapshot.framesRejectedByFocus,
            framesRejectedByBlur: lastSnapshot.framesRejectedByBlur,
            framesRejectedByMotion: lastSnapshot.framesRejectedByMotion,
            framesRejectedByNormal: lastSnapshot.framesRejectedByNormal,
            framesRejectedByReprojection: lastSnapshot.framesRejectedByReprojection,
            exportGateReason: exportGateReason,
            scanConfidence: scanConfidence,
            mainIssue: mainIssue,
            focusRecoveryState: focusRecoveryState,
            focusRecoveryCount: focusRecoveryCount,
            arucoLostCount: arucoLostCount,
            centerFocusRecoveryCount: centerFocusRecoveryCount,
            distanceGuideState: distanceGuideState,
            distanceGuideMessage: distanceGuideMessage,
            lastDistanceMm: finite(lastDistanceMm),
            distanceGuideBarMinMm: finite(distanceGuideBarMinMm),
            distanceGuideBarMaxMm: finite(distanceGuideBarMaxMm),
            distanceGuideIdealBandMinMm: finite(distanceGuideIdealBandMinMm),
            distanceGuideIdealBandMaxMm: finite(distanceGuideIdealBandMaxMm),
            frameMaskSafeRectMinX: finite(frameMaskDiagnostics?.frameMaskSafeRectMinX),
            frameMaskSafeRectMinY: finite(frameMaskDiagnostics?.frameMaskSafeRectMinY),
            frameMaskSafeRectMaxX: finite(frameMaskDiagnostics?.frameMaskSafeRectMaxX),
            frameMaskSafeRectMaxY: finite(frameMaskDiagnostics?.frameMaskSafeRectMaxY),
            visibleMarkersInsideFrameMaskCount:
                frameMaskDiagnostics?.visibleMarkersInsideFrameMaskCount,
            visibleMarkersViolatingFrameMaskCount:
                frameMaskDiagnostics?.visibleMarkersViolatingFrameMaskCount,
            anyMarkerNearFrameEdge: frameMaskDiagnostics?.anyMarkerNearFrameEdge,
            frameMaskQualityState: frameMaskDiagnostics?.frameMaskQualityState,
            frameMaskQualityMessage: frameMaskDiagnostics?.frameMaskQualityMessage,
            experimentalQualityModeEnabled:
                experimentalQualityDiagnostics?.experimentalQualityModeEnabled,
            experimentalObservationGateEnabled:
                experimentalQualityDiagnostics?.experimentalObservationGateEnabled,
            experimentalMinValidFramesPerMarker:
                experimentalQualityDiagnostics?.experimentalMinValidFramesPerMarker,
            experimentalTargetOptimizationFrames:
                experimentalQualityDiagnostics?.experimentalTargetOptimizationFrames,
            experimentalRawObservationCount:
                experimentalQualityDiagnostics?.experimentalRawObservationCount,
            experimentalAcceptedObservationCount:
                experimentalQualityDiagnostics?.experimentalAcceptedObservationCount,
            experimentalRejectedObservationCount:
                experimentalQualityDiagnostics?.experimentalRejectedObservationCount,
            experimentalRejectedByFrameMaskCount:
                experimentalQualityDiagnostics?.experimentalRejectedByFrameMaskCount,
            experimentalRejectedByTooCloseCount:
                experimentalQualityDiagnostics?.experimentalRejectedByTooCloseCount,
            experimentalRejectedByTooFarCount:
                experimentalQualityDiagnostics?.experimentalRejectedByTooFarCount,
            experimentalRejectedByFocusRiskCount:
                experimentalQualityDiagnostics?.experimentalRejectedByFocusRiskCount,
            experimentalRejectedByInvalidPoseCount:
                experimentalQualityDiagnostics?.experimentalRejectedByInvalidPoseCount,
            experimentalRejectedByNotFiniteCount:
                experimentalQualityDiagnostics?.experimentalRejectedByNotFiniteCount,
            experimentalRejectedByUnknownCount:
                experimentalQualityDiagnostics?.experimentalRejectedByUnknownCount,
            experimentalUsefulMarkersReadyCount:
                experimentalQualityDiagnostics?.experimentalUsefulMarkersReadyCount,
            experimentalUsefulAllMarkersReady:
                experimentalQualityDiagnostics?.experimentalUsefulAllMarkersReady,
            experimentalOverallUsefulProgress:
                finite(experimentalQualityDiagnostics?.experimentalOverallUsefulProgress),
            cameraHighResolutionProfileAvailable:
                experimentalQualityDiagnostics?.cameraHighResolutionProfileAvailable,
            cameraHighResolutionProfileSelected:
                experimentalQualityDiagnostics?.cameraHighResolutionProfileSelected,
            cameraRequestedHighResolutionDimensions:
                experimentalQualityDiagnostics?.cameraRequestedHighResolutionDimensions,
            cameraAppliedHighResolutionDimensions:
                experimentalQualityDiagnostics?.cameraAppliedHighResolutionDimensions,
            cameraHighResolutionFallbackReason:
                experimentalQualityDiagnostics?.cameraHighResolutionFallbackReason,
            referenceCameraMatrixDiagnosticsEnabled:
                experimentalQualityDiagnostics?.referenceCameraMatrixDiagnosticsEnabled,
            referenceCameraMatrixSource:
                experimentalQualityDiagnostics?.referenceCameraMatrixSource,
            referenceCameraMatrixFx: finite(experimentalQualityDiagnostics?.referenceCameraMatrixFx),
            referenceCameraMatrixFy: finite(experimentalQualityDiagnostics?.referenceCameraMatrixFy),
            referenceCameraMatrixCx: finite(experimentalQualityDiagnostics?.referenceCameraMatrixCx),
            referenceCameraMatrixCy: finite(experimentalQualityDiagnostics?.referenceCameraMatrixCy),
            activeCameraIntrinsicFx: finite(experimentalQualityDiagnostics?.activeCameraIntrinsicFx),
            activeCameraIntrinsicFy: finite(experimentalQualityDiagnostics?.activeCameraIntrinsicFy),
            activeCameraIntrinsicCx: finite(experimentalQualityDiagnostics?.activeCameraIntrinsicCx),
            activeCameraIntrinsicCy: finite(experimentalQualityDiagnostics?.activeCameraIntrinsicCy),
            referenceVsActiveFxDelta: finite(experimentalQualityDiagnostics?.referenceVsActiveFxDelta),
            referenceVsActiveFyDelta: finite(experimentalQualityDiagnostics?.referenceVsActiveFyDelta),
            referenceVsActiveCxDelta: finite(experimentalQualityDiagnostics?.referenceVsActiveCxDelta),
            referenceVsActiveCyDelta: finite(experimentalQualityDiagnostics?.referenceVsActiveCyDelta),
            referenceVsActiveFxRatio: finite(experimentalQualityDiagnostics?.referenceVsActiveFxRatio),
            referenceVsActiveFyRatio: finite(experimentalQualityDiagnostics?.referenceVsActiveFyRatio),
            referenceCameraMatrixResolutionMismatchWarning:
                experimentalQualityDiagnostics?.referenceCameraMatrixResolutionMismatchWarning,
            roiCenterNormalizedX: finite(experimentalQualityDiagnostics?.roiCenterNormalizedX),
            roiCenterNormalizedY: finite(experimentalQualityDiagnostics?.roiCenterNormalizedY),
            lastFocusPointNormalizedX:
                finite(experimentalQualityDiagnostics?.lastFocusPointNormalizedX),
            lastFocusPointNormalizedY:
                finite(experimentalQualityDiagnostics?.lastFocusPointNormalizedY),
            lastExposurePointNormalizedX:
                finite(experimentalQualityDiagnostics?.lastExposurePointNormalizedX),
            lastExposurePointNormalizedY:
                finite(experimentalQualityDiagnostics?.lastExposurePointNormalizedY),
            focusPointInsideROI: experimentalQualityDiagnostics?.focusPointInsideROI,
            focusPointDistanceToROICenter:
                finite(experimentalQualityDiagnostics?.focusPointDistanceToROICenter),
            experimentalAngularSamplesCount:
                experimentalQualityDiagnostics?.experimentalAngularSamplesCount,
            experimentalAngularUsefulSamplesCount:
                experimentalQualityDiagnostics?.experimentalAngularUsefulSamplesCount,
            experimentalAngularStdDeg:
                finite(experimentalQualityDiagnostics?.experimentalAngularStdDeg),
            experimentalAngularMinSeparationDeg:
                finite(experimentalQualityDiagnostics?.experimentalAngularMinSeparationDeg),
            experimentalAngleDiversityScore:
                finite(experimentalQualityDiagnostics?.experimentalAngleDiversityScore),
            experimentalAngleDiversityReady:
                experimentalQualityDiagnostics?.experimentalAngleDiversityReady,
            distanceSamplesTotal: distanceSampleCount,
            distanceSamplesValid: distanceValidSampleCount,
            distanceValidPercent: finite(distanceValidPercent),
            userFeedbackState: userFeedbackState,
            userFeedbackMessage: userFeedbackMessage,
            captureProgressPercent: finite(captureProgressPercent),
            refinementProgressPercent: finite(refinementProgressPercent),
            friendlyBlockingReason: friendlyBlockingReason,
            guidedStaticCaptureEnabled: guidedStaticCaptureEnabled,
            guidedStages: guidedStages,
            slowestMarkerId: slowestExpectedMarkerId,
            slowestExpectedMarkerId: slowestExpectedMarkerId,
            currentBlockingReason: currentBlockingReason,
            lastBlockingReasonBeforeExport: lastBlockingReasonBeforeExport,
            normalFinalizationState: normalFinalizationState,
            normalFinalizationStartedAtSeconds: finite(normalFinalizationStartedAt.map { relativeTime(from: $0) }),
            normalFinalizationDurationSeconds: finite(normalFinalizationDurationSeconds),
            normalFinalizationFramesAccepted: normalFinalizationFramesAccepted,
            normalFinalizationFramesRejectedByFocus: normalFinalizationFramesRejectedByFocus,
            normalFinalizationFramesRejectedByMotion: normalFinalizationFramesRejectedByMotion,
            normalFinalizationFramesRejectedByReprojection: normalFinalizationFramesRejectedByReprojection,
            normalFinalizationFramesRejectedByNormal: normalFinalizationFramesRejectedByNormal,
            autoExportTriggered: autoExportTriggered,
            normalFinalizationMinFinalObservationsPerMarker:
                normalFinalizationMinFinalObservationsPerMarker,
            normalFinalizationTargetAverageObservationsPerMarker:
                normalFinalizationTargetAverageObservationsPerMarker,
            normalFinalizationMinObservationsReached: normalFinalizationMinObservationsReached,
            normalFinalizationAverageObservationsReached: normalFinalizationAverageObservationsReached,
            normalFinalizationAverageObservationsPerMarker:
                finite(normalFinalizationAverageObservationsPerMarker),
            normalFinalizationMaxNormalStdDegrees: finite(normalFinalizationMaxNormalStdDegrees),
            normalFinalizationNormalGatePassed: normalFinalizationNormalGatePassed,
            normalFinalizationMaturityGatePassed: normalFinalizationMaturityGatePassed,
            normalFinalizationAutoExportReason: normalFinalizationAutoExportReason,
            normalFinalizationBlockedReason: normalFinalizationBlockedReason,
            normalFinalizationMinObservationsByMarker: normalFinalizationMinObservationsByMarker,
            allExpectedMarkersAt100Percent: allExpectedMarkersAt100Percent,
            expectedMarkerProgressById: sanitizedProgress(expectedMarkerProgressById),
            usedBestFinalPoseCandidate: usedBestFinalPoseCandidate,
            bestFinalPoseCandidateSaved: bestFinalPoseCandidateSaved,
            bestFinalPoseCandidateScore: finite(bestFinalPoseCandidateScore),
            bestFinalPoseCandidateTimestampSeconds:
                finite(bestFinalPoseCandidateTimestamp.map { relativeTime(from: $0) }),
            bestFinalPoseCandidateLastUpdatedAtSeconds:
                finite(bestFinalPoseCandidateLastUpdatedAt.map { relativeTime(from: $0) }),
            bestFinalPoseCandidateAgeSeconds: finite(bestFinalPoseCandidateAgeSeconds),
            bestFinalPoseCandidateWorstNormalStd: finite(bestFinalPoseCandidateWorstNormalStd),
            bestFinalPoseCandidateWorstReprojection: finite(bestFinalPoseCandidateWorstReprojection),
            bestFinalPoseCandidateObservationsByMarker: bestFinalPoseCandidateObservationsByMarker,
            bestFinalPoseCandidateReason: bestFinalPoseCandidateReason,
            bestFinalPoseCandidateMarkerIds: bestFinalPoseCandidateMarkerIds,
            bestFinalPoseCandidateHasExportablePoses: bestFinalPoseCandidateHasExportablePoses,
            bestFinalPoseCandidateAcceptedCount: bestFinalPoseCandidateAcceptedCount,
            bestFinalPoseCandidateLastRejectReason: bestFinalPoseCandidateLastRejectReason,
            bestFinalPoseCandidateGeometryAdjustedScore:
                finite(bestFinalPoseCandidateGeometryAdjustedScore),
            bestFinalPoseCandidateGeometryPenalty:
                finite(bestFinalPoseCandidateGeometryPenalty),
            bestFinalPoseCandidateGeometryScoreSource: bestFinalPoseCandidateGeometryScoreSource,
            relativeMarkerDistanceM01: finite(relativeMarkerDistanceM01),
            relativeMarkerDistanceM02: finite(relativeMarkerDistanceM02),
            relativeMarkerDistanceM03: finite(relativeMarkerDistanceM03),
            relativeMarkerDistanceM12: finite(relativeMarkerDistanceM12),
            relativeMarkerDistanceM13: finite(relativeMarkerDistanceM13),
            relativeMarkerDistanceM23: finite(relativeMarkerDistanceM23),
            relativeMarkerDistanceStdMean: finite(relativeMarkerDistanceStdMean),
            relativeMarkerDistanceStdMax: finite(relativeMarkerDistanceStdMax),
            relativeMarkerGeometryScore: finite(relativeMarkerGeometryScore),
            candidateVsFinalTranslationDeltaMean: finite(candidateVsFinalTranslationDeltaMean),
            candidateVsFinalRotationDeltaMean: finite(candidateVsFinalRotationDeltaMean),
            candidateVsFinalGeometryDelta: finite(candidateVsFinalGeometryDelta),
            lastEventName: events.last?.name,
            eventsCount: events.count,
            events: events,
            markers: markerSummaries
        )
        lastSnapshot = snapshot
        return snapshot
    }

    private func extraTimeAfterAllMarkersExportable(currentRelativeTime: Double) -> Double? {
        guard let allMarkersExportableAt else {
            return nil
        }

        return finite(max(currentRelativeTime - allMarkersExportableAt, 0.0))
    }

    private func sanitizedTimestamp(_ timestamp: Double) -> Double {
        timestamp.isFinite ? timestamp : Date().timeIntervalSinceReferenceDate
    }

    private func isReliableDistanceSample(
        state: String,
        distanceMm: Double?,
        isReliable: Bool
    ) -> Bool {
        guard let distanceMm,
              distanceMm.isFinite,
              distanceMm > 0
        else {
            return false
        }

        if isReliable {
            return true
        }

        let unstableStates = [
            "Sem marker confiavel",
            "Pose instavel",
            "Foco ruim",
            "Distancia indisponivel"
        ]
        return !unstableStates.contains(state)
    }

    private func relativeTime(from timestamp: Double) -> Double {
        let safeTimestamp = sanitizedTimestamp(timestamp)
        guard let scanStartedAt else {
            return 0
        }

        return max(safeTimestamp - scanStartedAt, 0.0)
    }

    private func finite(_ value: Double?) -> Double? {
        guard let value, value.isFinite else {
            return nil
        }

        return value
    }

    private func sanitizedProgress(_ values: [Int: Double]?) -> [Int: Double]? {
        guard let values else {
            return nil
        }

        let sanitized = values.reduce(into: [Int: Double]()) { partialResult, entry in
            guard entry.value.isFinite else {
                return
            }

            partialResult[entry.key] = entry.value
        }

        return sanitized.isEmpty ? nil : sanitized
    }
}
