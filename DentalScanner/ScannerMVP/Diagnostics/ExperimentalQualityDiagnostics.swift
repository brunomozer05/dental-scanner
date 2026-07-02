import Foundation

enum ExperimentalObservationRejectionReason: String, Codable {
    case frameMask
    case tooClose
    case tooFar
    case focusRisk
    case invalidPose
    case notFinite
    case unknownFrame
    case unknownDistance
    case unknownMarker
}

struct ExperimentalMarkerQualityDiagnostics: Codable, Equatable, Identifiable {
    let markerId: Int
    var rawObservationCount: Int
    var acceptedObservationCount: Int
    var rejectedObservationCount: Int
    var rejectedByFrameMaskCount: Int
    var rejectedByTooCloseCount: Int
    var rejectedByTooFarCount: Int
    var rejectedByFocusRiskCount: Int
    var rejectedByInvalidPoseCount: Int
    var rejectedByNotFiniteCount: Int
    var rejectedByUnknownCount: Int
    var usefulProgress: Double
    var usefulReady: Bool

    var id: Int {
        markerId
    }

    static func empty(markerId: Int) -> ExperimentalMarkerQualityDiagnostics {
        ExperimentalMarkerQualityDiagnostics(
            markerId: markerId,
            rawObservationCount: 0,
            acceptedObservationCount: 0,
            rejectedObservationCount: 0,
            rejectedByFrameMaskCount: 0,
            rejectedByTooCloseCount: 0,
            rejectedByTooFarCount: 0,
            rejectedByFocusRiskCount: 0,
            rejectedByInvalidPoseCount: 0,
            rejectedByNotFiniteCount: 0,
            rejectedByUnknownCount: 0,
            usefulProgress: 0,
            usefulReady: false
        )
    }
}

struct ExperimentalQualityDiagnostics: Codable, Equatable {
    var experimentalQualityModeEnabled: Bool
    var experimentalObservationGateEnabled: Bool
    var experimentalMinValidFramesPerMarker: Int?
    var experimentalTargetOptimizationFrames: Int?
    var experimentalRawObservationCount: Int
    var experimentalAcceptedObservationCount: Int
    var experimentalRejectedObservationCount: Int
    var experimentalRejectedByFrameMaskCount: Int
    var experimentalRejectedByTooCloseCount: Int
    var experimentalRejectedByTooFarCount: Int
    var experimentalRejectedByFocusRiskCount: Int
    var experimentalRejectedByInvalidPoseCount: Int
    var experimentalRejectedByNotFiniteCount: Int
    var experimentalRejectedByUnknownCount: Int
    var experimentalUsefulMarkersReadyCount: Int
    var experimentalUsefulAllMarkersReady: Bool
    var experimentalOverallUsefulProgress: Double?

    var cameraHighResolutionProfileAvailable: Bool
    var cameraHighResolutionProfileSelected: Bool
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

    var referenceCameraMatrixDiagnosticsEnabled: Bool
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

    var markerDiagnosticsByMarkerId: [Int: ExperimentalMarkerQualityDiagnostics]

    static let empty = ExperimentalQualityDiagnostics(
        experimentalQualityModeEnabled: false,
        experimentalObservationGateEnabled: false,
        experimentalMinValidFramesPerMarker: nil,
        experimentalTargetOptimizationFrames: nil,
        experimentalRawObservationCount: 0,
        experimentalAcceptedObservationCount: 0,
        experimentalRejectedObservationCount: 0,
        experimentalRejectedByFrameMaskCount: 0,
        experimentalRejectedByTooCloseCount: 0,
        experimentalRejectedByTooFarCount: 0,
        experimentalRejectedByFocusRiskCount: 0,
        experimentalRejectedByInvalidPoseCount: 0,
        experimentalRejectedByNotFiniteCount: 0,
        experimentalRejectedByUnknownCount: 0,
        experimentalUsefulMarkersReadyCount: 0,
        experimentalUsefulAllMarkersReady: false,
        experimentalOverallUsefulProgress: nil,
        cameraHighResolutionProfileAvailable: false,
        cameraHighResolutionProfileSelected: false,
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
        referenceCameraMatrixDiagnosticsEnabled: false,
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
        markerDiagnosticsByMarkerId: [:]
    )
}
