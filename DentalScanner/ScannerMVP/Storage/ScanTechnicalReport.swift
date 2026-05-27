import Foundation

struct ScanTechnicalReport: Codable {
    var createdAt: String
    var markerProfile: String
    var stlFileName: String?
    var diagnosticsFileName: String?
    var device: Device
    var cameraQuality: CameraQuality
    var markers: [Marker]
    var scanQuality: ScanQuality
    var expectedMarkerCount: Int?
    var exportedMarkerCount: Int?
    var missingMarkerIds: [Int]?
    var invalidMarkerIds: [Int]?
    var exportBlockedReason: String?
    var exportGateProfile: String?
    var markerExportValidations: [MarkerExportValidation]?
    var scanConfiguration: ScanConfiguration?
    var focusRecoveryState: String?
    var lastFocusTarget: String?
    var arucoLostCount: Int?
    var centerFocusRecoveryCount: Int?
    var distanceGuideState: String?
    var lastDistanceMm: Double?
    var tagAreaPixelsMean: Double?
    var normalFinalizationState: String?
    var normalFinalizationStartedAtSeconds: Double?
    var normalFinalizationDurationSeconds: Double?
    var normalFinalizationFramesAccepted: Int?
    var normalFinalizationFramesRejectedByFocus: Int?
    var normalFinalizationFramesRejectedByMotion: Int?
    var normalFinalizationFramesRejectedByReprojection: Int?
    var normalFinalizationFramesRejectedByNormal: Int?
    var autoExportTriggered: Bool?
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
    var guidedStaticCaptureEnabled: Bool?
    var guidedStaticStages: [GuidedStaticStage]?

    struct Device: Codable {
        var model: String?
        var iosVersion: String?
        var cameraDevice: String?
        var resolution: String?
        var zoomFactor: Double?
    }

    struct CameraQuality: Codable {
        var focusLocked: Bool?
        var sharpnessMean: Double?
        var framesRejectedByFocus: Int
        var framesRejectedByBlur: Int
    }

    struct Marker: Codable {
        var markerId: Int
        var translationVector: [Double]?
        var rotationMatrix: [[Double]]?
        var confidence: String?
        var qualityScore: Double?
        var dualFrames: Int?
        var topFallbackFrames: Int?
        var bottomFallbackFrames: Int?
        var reprojectionError: Double?
        var sharpnessMean: Double?
        var normalStdDegrees: Double?
        var finalObservationsUsed: Int?
    }

    struct ScanQuality: Codable {
        var confidence: String?
        var worstMarkerId: Int?
        var mainIssue: String?
        var planeAverageErrorMm: Double?
        var planeMaxErrorMm: Double?
    }

    struct MarkerExportValidation: Codable {
        var markerId: Int
        var exportGateProfile: String?
        var isExportable: Bool
        var reason: String?
        var isVisuallyRecent: Bool?
        var hasCurrentPose: Bool?
        var accumulatedObservationCount: Int?
        var finalObservationsUsed: Int?
    }

    struct ScanConfiguration: Codable {
        var markerProfile: String?
        var minimumCoveragePercentPerTag: Double?
        var minimumGoodFrames: Int?
        var targetGoodFrames: Int?
        var minimumDualTagFramesPerMarker: Int?
        var minimumDualAngularCoveragePercentPerMarker: Double?
        var precisionModeV2: Bool?
        var preferDualTagForFinalExport: Bool?
        var showDistanceGuide: Bool?
        var staticPoseStabilityMode: Bool?
        var arkitAssistedCaptureEnabled: Bool?
        var cameraZoomFactor: Double?
        var manualFocusEnabled: Bool?
        var manualLensPosition: Double?
        var lockFocusAndExposureForScan: Bool?
        var autoFocusOnDetectedAruco: Bool?
        var lockAfterArucoFocus: Bool?
        var guidedStaticCaptureEnabled: Bool?
        var guidedStaticRequiredStages: Int?
        var guidedStaticFramesPerStage: Int?
        var guidedStaticMinStableTimeSeconds: Double?
        var guidedStaticMaxNormalStdDegreesPerStage: Double?
        var guidedStaticRequireAllMarkersPerStage: Bool?
        var minimumAllowedSharpness: Double?
        var minimumPreferredSharpness: Double?
        var lensPositionChangeThreshold: Double?
        var focusSettleTimeSeconds: Double?
    }

    struct GuidedStaticStage: Codable {
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
