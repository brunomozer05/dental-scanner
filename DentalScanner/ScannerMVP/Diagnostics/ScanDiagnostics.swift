import Foundation

struct ScanDiagnosticEvent: Codable, Equatable, Identifiable {
    let id: UUID
    let name: String
    let timestampSeconds: Double
    let markerId: Int?
    let message: String?
    let metadata: [String: String]?

    init(
        name: String,
        timestampSeconds: Double,
        markerId: Int? = nil,
        message: String? = nil,
        metadata: [String: String]? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.timestampSeconds = timestampSeconds
        self.markerId = markerId
        self.message = message
        self.metadata = metadata?.isEmpty == true ? nil : metadata
    }
}

struct ScanDiagnosticsSnapshot: Codable, Equatable {
    var createdAt: String?
    var markerProfile: String?
    var deviceModelIdentifier: String?
    var deviceMarketingName: String?
    var cameraProfileId: String?
    var cameraProfileName: String?
    var cameraRecommendedProfileId: String?
    var cameraRecommendedProfileName: String?
    var cameraProfileTooCloseFocusRiskDistanceMm: Double?
    var cameraProfilePreferredMinScanDistanceMm: Double?
    var cameraProfilePreferredIdealMinScanDistanceMm: Double?
    var cameraProfilePreferredIdealMaxScanDistanceMm: Double?
    var cameraProfilePreferredMaxScanDistanceMm: Double?
    var deviceQualityClass: String?
    var deviceQualityProfileName: String?
    var deviceQualityIsKnown: Bool?
    var deviceQualityWarning: String?
    var deviceQualityMinDistanceMm: Double?
    var deviceQualityIdealMinDistanceMm: Double?
    var deviceQualityIdealMaxDistanceMm: Double?
    var deviceQualityMaxDistanceMm: Double?
    var deviceQualityTooCloseFocusRiskDistanceMm: Double?
    var deviceQualityFocusVarianceThreshold: Double?
    var deviceQualityOverlayScale: Double?
    var deviceQualityFrameMaskVerticalBorderPercent: Double?
    var deviceQualityFrameMaskHorizontalBorderPercent: Double?
    var selectedCameraLocalizedName: String?
    var selectedCameraDeviceType: String?
    var requestedZoomFactor: Double?
    var appliedZoomFactor: Double?
    var currentVideoZoomFactor: Double?
    var focusMode: String?
    var exposureMode: String?
    var isAdjustingFocus: Bool?
    var isAdjustingExposure: Bool?
    var cameraIntrinsicMatrixAvailable: Bool?
    var cameraIntrinsicFx: Double?
    var cameraIntrinsicFy: Double?
    var cameraIntrinsicCx: Double?
    var cameraIntrinsicCy: Double?
    var activeVideoDimensions: String?
    var activeFormatDescription: String?
    var cameraProfileEvaluationScore: Double?
    var cameraProfileEvaluationWarnings: [String]?
    var scanDurationSeconds: Double?
    var timeToFirstMarkerSeconds: Double?
    var timeToAllMarkersSeenSeconds: Double?
    var timeToAllMarkersExportableSeconds: Double?
    var extraTimeAfterAllMarkers100PercentSeconds: Double?
    var expectedMarkerIds: [Int]
    var unexpectedMarkerIdsSeen: [Int]
    var fpsMean: Double?
    var fpsMin: Double?
    var framesProcessed: Int
    var framesAccepted: Int
    var framesRejectedByFocus: Int
    var framesRejectedByBlur: Int
    var framesRejectedByMotion: Int
    var framesRejectedByNormal: Int
    var framesRejectedByReprojection: Int
    var exportGateReason: String?
    var scanConfidence: String?
    var mainIssue: String?
    var focusRecoveryState: String?
    var focusRecoveryCount: Int
    var arucoLostCount: Int
    var centerFocusRecoveryCount: Int
    var distanceGuideState: String?
    var distanceGuideMessage: String?
    var lastDistanceMm: Double?
    var distanceGuideBarMinMm: Double?
    var distanceGuideBarMaxMm: Double?
    var distanceGuideIdealBandMinMm: Double?
    var distanceGuideIdealBandMaxMm: Double?
    var frameMaskSafeRectMinX: Double?
    var frameMaskSafeRectMinY: Double?
    var frameMaskSafeRectMaxX: Double?
    var frameMaskSafeRectMaxY: Double?
    var visibleMarkersInsideFrameMaskCount: Int?
    var visibleMarkersViolatingFrameMaskCount: Int?
    var anyMarkerNearFrameEdge: Bool?
    var frameMaskQualityState: String?
    var frameMaskQualityMessage: String?
    var frameObservationModelEnabled: Bool?
    var frameObservationCount: Int?
    var frameObservationDroppedCount: Int?
    var frameObservationBufferLimit: Int?
    var frameObservationOldestTimestamp: Double?
    var frameObservationNewestTimestamp: Double?
    var framesWithAnyMarkerObservationCount: Int?
    var framesWithExpectedMarkersObservationCount: Int?
    var markerFrameObservationCountM0: Int?
    var markerFrameObservationCountM1: Int?
    var markerFrameObservationCountM2: Int?
    var markerFrameObservationCountM3: Int?
    var frameObservationMarkerCountMismatchCount: Int?
    var frameObservationPointCountMismatchCount: Int?
    var frameObservationMissingIntrinsicsCount: Int?
    var frameObservationNonFinitePoseCount: Int?
    var preAccumulationGateDiagnosticsEnabled: Bool?
    var preAccumulationGateBlockingEnabled: Bool?
    var preAccumulationRawObservationCount: Int?
    var preAccumulationWouldAcceptCount: Int?
    var preAccumulationWouldRejectCount: Int?
    var preAccumulationAccumulatorInsertedCount: Int?
    var preAccumulationWouldRejectByUnexpectedMarkerCount: Int?
    var preAccumulationWouldRejectByMissingIntrinsicsCount: Int?
    var preAccumulationWouldRejectByInvalidIntrinsicsCount: Int?
    var preAccumulationWouldRejectByNotFinitePoseCount: Int?
    var preAccumulationWouldRejectByInvalidPoseCount: Int?
    var preAccumulationWouldRejectByFrameMaskCount: Int?
    var preAccumulationWouldRejectByTooCloseCount: Int?
    var preAccumulationWouldRejectByTooFarCount: Int?
    var preAccumulationWouldRejectByFocusRiskCount: Int?
    var preAccumulationWouldRejectByHighReprojectionCount: Int?
    var preAccumulationWouldRejectByHighMotionCount: Int?
    var preAccumulationWouldRejectByUnknownCount: Int?
    var preAccumulationWouldAcceptRatio: Double?
    var preAccumulationWouldRejectRatio: Double?
    var preAccumulationTopRejectReason: String?
    var preAccumulationReprojectionEvaluationUnavailableCount: Int?
    var preAccumulationMotionEvaluationUnavailableCount: Int?
    var preGateExperimentalComparisonAvailable: Bool?
    var preGateVsExperimentalAgreementCount: Int?
    var preGateVsExperimentalDisagreementCount: Int?
    var preGateAcceptedExperimentalAcceptedCount: Int?
    var preGateAcceptedExperimentalRejectedCount: Int?
    var preGateRejectedExperimentalAcceptedCount: Int?
    var preGateRejectedExperimentalRejectedCount: Int?
    var preAccumulationMarkerM0: PreAccumulationMarkerGateReportSummary?
    var preAccumulationMarkerM1: PreAccumulationMarkerGateReportSummary?
    var preAccumulationMarkerM2: PreAccumulationMarkerGateReportSummary?
    var preAccumulationMarkerM3: PreAccumulationMarkerGateReportSummary?
    var experimentalQualityModeEnabled: Bool?
    var experimentalObservationGateEnabled: Bool?
    var experimentalMinValidFramesPerMarker: Int?
    var experimentalTargetOptimizationFrames: Int?
    var experimentalRawObservationCount: Int?
    var experimentalAcceptedObservationCount: Int?
    var experimentalRejectedObservationCount: Int?
    var experimentalRejectedByFrameMaskCount: Int?
    var experimentalRejectedByTooCloseCount: Int?
    var experimentalRejectedByTooFarCount: Int?
    var experimentalRejectedByFocusRiskCount: Int?
    var experimentalRejectedByInvalidPoseCount: Int?
    var experimentalRejectedByNotFiniteCount: Int?
    var experimentalRejectedByUnknownCount: Int?
    var experimentalUsefulMarkersReadyCount: Int?
    var experimentalUsefulAllMarkersReady: Bool?
    var experimentalOverallUsefulProgress: Double?
    var cameraHighResolutionProfileAvailable: Bool?
    var cameraHighResolutionProfileSelected: Bool?
    var cameraRequestedHighResolutionDimensions: String?
    var cameraAppliedHighResolutionDimensions: String?
    var cameraHighResolutionFallbackReason: String?
    var cameraAvailableFormatCount: Int?
    var cameraAvailableMaxResolutionWidth: Int?
    var cameraAvailableMaxResolutionHeight: Int?
    var cameraFramePixelBufferWidth: Int?
    var cameraFramePixelBufferHeight: Int?
    var cameraFrameProcessingWidth: Int?
    var cameraFrameProcessingHeight: Int?
    var cameraFrameDownscaleApplied: Bool?
    var cameraFrameDownscaleFactorX: Double?
    var cameraFrameDownscaleFactorY: Double?
    var cameraFramesReceivedCount: Int?
    var cameraFramesProcessedCount: Int?
    var cameraFramesDroppedCount: Int?
    var cameraLastFrameProcessingMs: Double?
    var cameraAverageFrameProcessingMs: Double?
    var arucoDetectedMarkerCountLastFrame: Int?
    var arucoDetectedExpectedMarkerCountLastFrame: Int?
    var arucoLastDetectionTimestamp: Double?
    var arucoFramesWithAnyMarkerCount: Int?
    var arucoFramesWithExpectedMarkerCount: Int?
    var poseAcceptedLastFrame: Bool?
    var poseRejectedLastFrame: Bool?
    var poseLastRejectReason: String?
    var referenceCameraMatrixDiagnosticsEnabled: Bool?
    var referenceCameraMatrixSource: String?
    var referenceCameraMatrixFx: Double?
    var referenceCameraMatrixFy: Double?
    var referenceCameraMatrixCx: Double?
    var referenceCameraMatrixCy: Double?
    var activeCameraIntrinsicFx: Double?
    var activeCameraIntrinsicFy: Double?
    var activeCameraIntrinsicCx: Double?
    var activeCameraIntrinsicCy: Double?
    var referenceVsActiveFxDelta: Double?
    var referenceVsActiveFyDelta: Double?
    var referenceVsActiveCxDelta: Double?
    var referenceVsActiveCyDelta: Double?
    var referenceVsActiveFxRatio: Double?
    var referenceVsActiveFyRatio: Double?
    var referenceCameraMatrixResolutionMismatchWarning: String?
    var roiCenterNormalizedX: Double?
    var roiCenterNormalizedY: Double?
    var lastFocusPointNormalizedX: Double?
    var lastFocusPointNormalizedY: Double?
    var lastExposurePointNormalizedX: Double?
    var lastExposurePointNormalizedY: Double?
    var focusPointInsideROI: Bool?
    var focusPointDistanceToROICenter: Double?
    var experimentalAngularSamplesCount: Int?
    var experimentalAngularUsefulSamplesCount: Int?
    var experimentalAngularStdDeg: Double?
    var experimentalAngularMinSeparationDeg: Double?
    var experimentalAngleDiversityScore: Double?
    var experimentalAngleDiversityReady: Bool?
    var distanceSamplesTotal: Int
    var distanceSamplesValid: Int
    var distanceValidPercent: Double?
    var userFeedbackState: String?
    var userFeedbackMessage: String?
    var captureProgressPercent: Double?
    var refinementProgressPercent: Double?
    var friendlyBlockingReason: String?
    var guidedStaticCaptureEnabled: Bool
    var guidedStages: [GuidedStageSummary]?
    var slowestMarkerId: Int?
    var slowestExpectedMarkerId: Int?
    var currentBlockingReason: String?
    var lastBlockingReasonBeforeExport: String?
    var normalFinalizationState: String?
    var normalFinalizationStartedAtSeconds: Double?
    var normalFinalizationDurationSeconds: Double?
    var normalFinalizationFramesAccepted: Int
    var normalFinalizationFramesRejectedByFocus: Int
    var normalFinalizationFramesRejectedByMotion: Int
    var normalFinalizationFramesRejectedByReprojection: Int
    var normalFinalizationFramesRejectedByNormal: Int
    var autoExportTriggered: Bool
    var normalFinalizationMinFinalObservationsPerMarker: Int?
    var normalFinalizationTargetAverageObservationsPerMarker: Int?
    var normalFinalizationMinObservationsReached: Bool?
    var normalFinalizationAverageObservationsReached: Bool?
    var normalFinalizationAverageObservationsPerMarker: Double?
    var normalFinalizationMaxNormalStdDegrees: Double?
    var normalFinalizationNormalGatePassed: Bool?
    var normalFinalizationMaturityGatePassed: Bool?
    var normalFinalizationAutoExportReason: String?
    var normalFinalizationBlockedReason: String?
    var normalFinalizationMinObservationsByMarker: [Int: Int]?
    var allExpectedMarkersAt100Percent: Bool?
    var expectedMarkerProgressById: [Int: Double]?
    var usedBestFinalPoseCandidate: Bool?
    var bestFinalPoseCandidateSaved: Bool?
    var bestFinalPoseCandidateScore: Double?
    var bestFinalPoseCandidateTimestampSeconds: Double?
    var bestFinalPoseCandidateLastUpdatedAtSeconds: Double?
    var bestFinalPoseCandidateAgeSeconds: Double?
    var bestFinalPoseCandidateWorstNormalStd: Double?
    var bestFinalPoseCandidateWorstReprojection: Double?
    var bestFinalPoseCandidateObservationsByMarker: [Int: Int]?
    var bestFinalPoseCandidateReason: String?
    var bestFinalPoseCandidateMarkerIds: [Int]?
    var bestFinalPoseCandidateHasExportablePoses: Bool?
    var bestFinalPoseCandidateAcceptedCount: Int?
    var bestFinalPoseCandidateLastRejectReason: String?
    var bestFinalPoseCandidateGeometryAdjustedScore: Double?
    var bestFinalPoseCandidateGeometryPenalty: Double?
    var bestFinalPoseCandidateGeometryScoreSource: String?
    var relativeMarkerDistanceM01: Double?
    var relativeMarkerDistanceM02: Double?
    var relativeMarkerDistanceM03: Double?
    var relativeMarkerDistanceM12: Double?
    var relativeMarkerDistanceM13: Double?
    var relativeMarkerDistanceM23: Double?
    var relativeMarkerDistanceStdMean: Double?
    var relativeMarkerDistanceStdMax: Double?
    var relativeMarkerGeometryScore: Double?
    var candidateVsFinalTranslationDeltaMean: Double?
    var candidateVsFinalRotationDeltaMean: Double?
    var candidateVsFinalGeometryDelta: Double?
    var lastEventName: String?
    var eventsCount: Int
    var events: [ScanDiagnosticEvent]
    var markers: [MarkerSummary]

    static let empty = ScanDiagnosticsSnapshot(
        createdAt: nil,
        markerProfile: nil,
        deviceModelIdentifier: nil,
        deviceMarketingName: nil,
        cameraProfileId: nil,
        cameraProfileName: nil,
        cameraRecommendedProfileId: nil,
        cameraRecommendedProfileName: nil,
        cameraProfileTooCloseFocusRiskDistanceMm: nil,
        cameraProfilePreferredMinScanDistanceMm: nil,
        cameraProfilePreferredIdealMinScanDistanceMm: nil,
        cameraProfilePreferredIdealMaxScanDistanceMm: nil,
        cameraProfilePreferredMaxScanDistanceMm: nil,
        deviceQualityClass: nil,
        deviceQualityProfileName: nil,
        deviceQualityIsKnown: nil,
        deviceQualityWarning: nil,
        deviceQualityMinDistanceMm: nil,
        deviceQualityIdealMinDistanceMm: nil,
        deviceQualityIdealMaxDistanceMm: nil,
        deviceQualityMaxDistanceMm: nil,
        deviceQualityTooCloseFocusRiskDistanceMm: nil,
        deviceQualityFocusVarianceThreshold: nil,
        deviceQualityOverlayScale: nil,
        deviceQualityFrameMaskVerticalBorderPercent: nil,
        deviceQualityFrameMaskHorizontalBorderPercent: nil,
        selectedCameraLocalizedName: nil,
        selectedCameraDeviceType: nil,
        requestedZoomFactor: nil,
        appliedZoomFactor: nil,
        currentVideoZoomFactor: nil,
        focusMode: nil,
        exposureMode: nil,
        isAdjustingFocus: nil,
        isAdjustingExposure: nil,
        cameraIntrinsicMatrixAvailable: nil,
        cameraIntrinsicFx: nil,
        cameraIntrinsicFy: nil,
        cameraIntrinsicCx: nil,
        cameraIntrinsicCy: nil,
        activeVideoDimensions: nil,
        activeFormatDescription: nil,
        cameraProfileEvaluationScore: nil,
        cameraProfileEvaluationWarnings: nil,
        scanDurationSeconds: nil,
        timeToFirstMarkerSeconds: nil,
        timeToAllMarkersSeenSeconds: nil,
        timeToAllMarkersExportableSeconds: nil,
        extraTimeAfterAllMarkers100PercentSeconds: nil,
        expectedMarkerIds: [],
        unexpectedMarkerIdsSeen: [],
        fpsMean: nil,
        fpsMin: nil,
        framesProcessed: 0,
        framesAccepted: 0,
        framesRejectedByFocus: 0,
        framesRejectedByBlur: 0,
        framesRejectedByMotion: 0,
        framesRejectedByNormal: 0,
        framesRejectedByReprojection: 0,
        exportGateReason: nil,
        scanConfidence: nil,
        mainIssue: nil,
        focusRecoveryState: nil,
        focusRecoveryCount: 0,
        arucoLostCount: 0,
        centerFocusRecoveryCount: 0,
        distanceGuideState: nil,
        distanceGuideMessage: nil,
        lastDistanceMm: nil,
        distanceGuideBarMinMm: nil,
        distanceGuideBarMaxMm: nil,
        distanceGuideIdealBandMinMm: nil,
        distanceGuideIdealBandMaxMm: nil,
        frameMaskSafeRectMinX: nil,
        frameMaskSafeRectMinY: nil,
        frameMaskSafeRectMaxX: nil,
        frameMaskSafeRectMaxY: nil,
        visibleMarkersInsideFrameMaskCount: nil,
        visibleMarkersViolatingFrameMaskCount: nil,
        anyMarkerNearFrameEdge: nil,
        frameMaskQualityState: nil,
        frameMaskQualityMessage: nil,
        experimentalQualityModeEnabled: nil,
        experimentalObservationGateEnabled: nil,
        experimentalMinValidFramesPerMarker: nil,
        experimentalTargetOptimizationFrames: nil,
        experimentalRawObservationCount: nil,
        experimentalAcceptedObservationCount: nil,
        experimentalRejectedObservationCount: nil,
        experimentalRejectedByFrameMaskCount: nil,
        experimentalRejectedByTooCloseCount: nil,
        experimentalRejectedByTooFarCount: nil,
        experimentalRejectedByFocusRiskCount: nil,
        experimentalRejectedByInvalidPoseCount: nil,
        experimentalRejectedByNotFiniteCount: nil,
        experimentalRejectedByUnknownCount: nil,
        experimentalUsefulMarkersReadyCount: nil,
        experimentalUsefulAllMarkersReady: nil,
        experimentalOverallUsefulProgress: nil,
        cameraHighResolutionProfileAvailable: nil,
        cameraHighResolutionProfileSelected: nil,
        cameraRequestedHighResolutionDimensions: nil,
        cameraAppliedHighResolutionDimensions: nil,
        cameraHighResolutionFallbackReason: nil,
        cameraAvailableFormatCount: nil,
        cameraAvailableMaxResolutionWidth: nil,
        cameraAvailableMaxResolutionHeight: nil,
        cameraFramePixelBufferWidth: nil,
        cameraFramePixelBufferHeight: nil,
        cameraFrameProcessingWidth: nil,
        cameraFrameProcessingHeight: nil,
        cameraFrameDownscaleApplied: nil,
        cameraFrameDownscaleFactorX: nil,
        cameraFrameDownscaleFactorY: nil,
        cameraFramesReceivedCount: nil,
        cameraFramesProcessedCount: nil,
        cameraFramesDroppedCount: nil,
        cameraLastFrameProcessingMs: nil,
        cameraAverageFrameProcessingMs: nil,
        arucoDetectedMarkerCountLastFrame: nil,
        arucoDetectedExpectedMarkerCountLastFrame: nil,
        arucoLastDetectionTimestamp: nil,
        arucoFramesWithAnyMarkerCount: nil,
        arucoFramesWithExpectedMarkerCount: nil,
        poseAcceptedLastFrame: nil,
        poseRejectedLastFrame: nil,
        poseLastRejectReason: nil,
        referenceCameraMatrixDiagnosticsEnabled: nil,
        referenceCameraMatrixSource: nil,
        referenceCameraMatrixFx: nil,
        referenceCameraMatrixFy: nil,
        referenceCameraMatrixCx: nil,
        referenceCameraMatrixCy: nil,
        activeCameraIntrinsicFx: nil,
        activeCameraIntrinsicFy: nil,
        activeCameraIntrinsicCx: nil,
        activeCameraIntrinsicCy: nil,
        referenceVsActiveFxDelta: nil,
        referenceVsActiveFyDelta: nil,
        referenceVsActiveCxDelta: nil,
        referenceVsActiveCyDelta: nil,
        referenceVsActiveFxRatio: nil,
        referenceVsActiveFyRatio: nil,
        referenceCameraMatrixResolutionMismatchWarning: nil,
        roiCenterNormalizedX: nil,
        roiCenterNormalizedY: nil,
        lastFocusPointNormalizedX: nil,
        lastFocusPointNormalizedY: nil,
        lastExposurePointNormalizedX: nil,
        lastExposurePointNormalizedY: nil,
        focusPointInsideROI: nil,
        focusPointDistanceToROICenter: nil,
        experimentalAngularSamplesCount: nil,
        experimentalAngularUsefulSamplesCount: nil,
        experimentalAngularStdDeg: nil,
        experimentalAngularMinSeparationDeg: nil,
        experimentalAngleDiversityScore: nil,
        experimentalAngleDiversityReady: nil,
        distanceSamplesTotal: 0,
        distanceSamplesValid: 0,
        distanceValidPercent: nil,
        userFeedbackState: nil,
        userFeedbackMessage: nil,
        captureProgressPercent: nil,
        refinementProgressPercent: nil,
        friendlyBlockingReason: nil,
        guidedStaticCaptureEnabled: false,
        guidedStages: nil,
        slowestMarkerId: nil,
        slowestExpectedMarkerId: nil,
        currentBlockingReason: nil,
        lastBlockingReasonBeforeExport: nil,
        normalFinalizationState: nil,
        normalFinalizationStartedAtSeconds: nil,
        normalFinalizationDurationSeconds: nil,
        normalFinalizationFramesAccepted: 0,
        normalFinalizationFramesRejectedByFocus: 0,
        normalFinalizationFramesRejectedByMotion: 0,
        normalFinalizationFramesRejectedByReprojection: 0,
        normalFinalizationFramesRejectedByNormal: 0,
        autoExportTriggered: false,
        normalFinalizationMinFinalObservationsPerMarker: nil,
        normalFinalizationTargetAverageObservationsPerMarker: nil,
        normalFinalizationMinObservationsReached: nil,
        normalFinalizationAverageObservationsReached: nil,
        normalFinalizationAverageObservationsPerMarker: nil,
        normalFinalizationMaxNormalStdDegrees: nil,
        normalFinalizationNormalGatePassed: nil,
        normalFinalizationMaturityGatePassed: nil,
        normalFinalizationAutoExportReason: nil,
        normalFinalizationBlockedReason: nil,
        normalFinalizationMinObservationsByMarker: nil,
        allExpectedMarkersAt100Percent: nil,
        expectedMarkerProgressById: nil,
        usedBestFinalPoseCandidate: nil,
        bestFinalPoseCandidateSaved: nil,
        bestFinalPoseCandidateScore: nil,
        bestFinalPoseCandidateTimestampSeconds: nil,
        bestFinalPoseCandidateLastUpdatedAtSeconds: nil,
        bestFinalPoseCandidateAgeSeconds: nil,
        bestFinalPoseCandidateWorstNormalStd: nil,
        bestFinalPoseCandidateWorstReprojection: nil,
        bestFinalPoseCandidateObservationsByMarker: nil,
        bestFinalPoseCandidateReason: nil,
        bestFinalPoseCandidateMarkerIds: nil,
        bestFinalPoseCandidateHasExportablePoses: nil,
        bestFinalPoseCandidateAcceptedCount: nil,
        bestFinalPoseCandidateLastRejectReason: nil,
        bestFinalPoseCandidateGeometryAdjustedScore: nil,
        bestFinalPoseCandidateGeometryPenalty: nil,
        bestFinalPoseCandidateGeometryScoreSource: nil,
        relativeMarkerDistanceM01: nil,
        relativeMarkerDistanceM02: nil,
        relativeMarkerDistanceM03: nil,
        relativeMarkerDistanceM12: nil,
        relativeMarkerDistanceM13: nil,
        relativeMarkerDistanceM23: nil,
        relativeMarkerDistanceStdMean: nil,
        relativeMarkerDistanceStdMax: nil,
        relativeMarkerGeometryScore: nil,
        candidateVsFinalTranslationDeltaMean: nil,
        candidateVsFinalRotationDeltaMean: nil,
        candidateVsFinalGeometryDelta: nil,
        lastEventName: nil,
        eventsCount: 0,
        events: [],
        markers: []
    )

    struct MarkerSummary: Codable, Equatable, Identifiable {
        let markerId: Int
        var firstSeenAtSeconds: Double?
        var becameExportableAtSeconds: Double?
        var totalVisibleSeconds: Double?
        var observationsAccumulated: Int
        var finalObservationsUsed: Int?
        var qualityScore: Double?
        var normalStdDegrees: Double?
        var reprojectionError: Double?
        var exportable: Bool
        var invalidReason: String?
        var waitingReason: String?
        var markerFrameCenterX: Double?
        var markerFrameCenterY: Double?
        var markerFrameNormalizedCenterX: Double?
        var markerFrameNormalizedCenterY: Double?
        var markerFrameMinX: Double?
        var markerFrameMinY: Double?
        var markerFrameMaxX: Double?
        var markerFrameMaxY: Double?
        var markerInsideFrameMask: Bool?
        var markerFrameMaskViolation: String?
        var markerDistanceToFrameMaskEdgePx: Double?
        var markerDistanceToFrameMaskEdgeNormalized: Double?
        var markerNearFrameEdgeWarning: Bool?
        var markerExperimentalRawObservationCount: Int?
        var markerExperimentalAcceptedObservationCount: Int?
        var markerExperimentalRejectedObservationCount: Int?
        var markerExperimentalRejectedByFrameMaskCount: Int?
        var markerExperimentalRejectedByTooCloseCount: Int?
        var markerExperimentalRejectedByTooFarCount: Int?
        var markerExperimentalRejectedByFocusRiskCount: Int?
        var markerExperimentalRejectedByInvalidPoseCount: Int?
        var markerExperimentalRejectedByNotFiniteCount: Int?
        var markerExperimentalRejectedByUnknownCount: Int?
        var markerExperimentalUsefulProgress: Double?
        var markerExperimentalUsefulReady: Bool?

        var id: Int {
            markerId
        }
    }

    struct GuidedStageSummary: Codable, Equatable {
        var stageName: String
        var framesAccepted: Int
        var framesRejectedByFocus: Int
        var framesRejectedByMotion: Int
        var framesRejectedByNormal: Int
        var framesRejectedByReprojection: Int
        var markersSeen: [Int]?
        var markersAccepted: [Int]?
        var normalStdDegreesMean: Double?
    }
}

struct DiagnosticsExportBundle: Codable, Equatable {
    var stlFileName: String?
    var reportFileName: String?
    var diagnosticsFileName: String?
}

protocol CrashReportingService {
    func record(error: Error, context: [String: String])
    func record(message: String, context: [String: String])
}

struct NoopCrashReportingService: CrashReportingService {
    func record(error: Error, context: [String: String]) {}
    func record(message: String, context: [String: String]) {}
}
