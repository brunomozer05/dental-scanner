import Foundation

struct ScanTechnicalReport: Codable {
    var createdAt: String
    var markerProfile: String
    var stlFileName: String?
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
        var minimumAllowedSharpness: Double?
        var minimumPreferredSharpness: Double?
        var lensPositionChangeThreshold: Double?
        var focusSettleTimeSeconds: Double?
    }
}
