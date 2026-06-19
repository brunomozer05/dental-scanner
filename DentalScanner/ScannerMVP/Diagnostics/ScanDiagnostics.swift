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
