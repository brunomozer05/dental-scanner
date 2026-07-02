import AVFoundation
import CoreMedia
import CoreVideo
import simd

struct CameraFrameQualityConfiguration: Equatable {
    var lensPositionChangeThreshold: Float
    var focusSettleTimeSeconds: Double
    var minimumAllowedSharpness: Double
    var minimumPreferredSharpness: Double

    static let scannerDefault = CameraFrameQualityConfiguration(
        lensPositionChangeThreshold: 0.015,
        focusSettleTimeSeconds: 0.5,
        minimumAllowedSharpness: 25.0,
        minimumPreferredSharpness: 80.0
    )
}

struct CameraFrameQuality: Equatable {
    let isAdjustingFocus: Bool
    let isAdjustingExposure: Bool
    let isAdjustingWhiteBalance: Bool
    let isFocusSettling: Bool
    let isFocusStable: Bool
    let lensPosition: Float?
    let lastLensPositionChangeAgeSeconds: Double?
    let sharpness: Double?
    let isSharpnessAcceptable: Bool
    let sharpnessScore: Double
    let iso: Float?
    let exposureDurationSeconds: Double?
    let cameraStabilityScore: Double
    let rotationStabilityScore: Double

    var isUnstable: Bool {
        cameraStabilityScore < 0.999 ||
            isAdjustingFocus ||
            isFocusSettling ||
            !isSharpnessAcceptable ||
            isAdjustingExposure ||
            isAdjustingWhiteBalance
    }

    var scanRejectionReason: String? {
        if isAdjustingFocus {
            return "Frame rejeitado: foco ajustando"
        }

        if isFocusSettling {
            return "Frame rejeitado: foco estabilizando"
        }

        if !isSharpnessAcceptable {
            return "Frame rejeitado: imagem fora de foco"
        }

        return nil
    }

    static let neutral = CameraFrameQuality(
        isAdjustingFocus: false,
        isAdjustingExposure: false,
        isAdjustingWhiteBalance: false,
        isFocusSettling: false,
        isFocusStable: true,
        lensPosition: nil,
        lastLensPositionChangeAgeSeconds: nil,
        sharpness: nil,
        isSharpnessAcceptable: true,
        sharpnessScore: 1.0,
        iso: nil,
        exposureDurationSeconds: nil,
        cameraStabilityScore: 1.0,
        rotationStabilityScore: 1.0
    )
}

struct CameraDebugSnapshot: Equatable {
    let deviceName: String?
    let deviceType: String?
    let uniqueID: String?
    let activeFormatDescription: String?
    let resolutionText: String?
    let fpsText: String?
    let hasIntrinsics: Bool
    let fx: Double?
    let fy: Double?
    let cx: Double?
    let cy: Double?
    let lensPosition: Float?
    let lastLensPositionChangeAgeSeconds: Double?
    let isFocusStable: Bool?
    let isFocusSettling: Bool?
    let sharpness: Double?
    let averageSharpness: Double?
    let minimumAllowedSharpness: Double?
    let minimumPreferredSharpness: Double?
    let isAdjustingFocus: Bool?
    let isAdjustingExposure: Bool?
    let isAdjustingWhiteBalance: Bool?
    let focusMode: String?
    let exposureMode: String?
    let iso: Float?
    let exposureDurationSeconds: Double?
    let cameraStabilityScore: Double?
    let rotationStabilityScore: Double?
    let isCameraLocked: Bool
    let automaticLockEnabled: Bool
    let videoZoomFactor: Double?
    let minimumAvailableVideoZoomFactor: Double?
    let maximumAvailableVideoZoomFactor: Double?
    let highResolutionFormatSelectionEnabled: Bool
    let highResolutionFormatAvailable: Bool
    let highResolutionRequestedDimensions: String?
    let highResolutionAppliedDimensions: String?
    let highResolutionFallbackReason: String?
    let availableFormatCount: Int?
    let availableMaxResolutionWidth: Int?
    let availableMaxResolutionHeight: Int?
    let manualFocusEnabled: Bool
    let manualLensPosition: Float?
    let isManualFocusSupported: Bool?
    let lockError: String?

    static let unavailable = CameraDebugSnapshot(
        deviceName: nil,
        deviceType: nil,
        uniqueID: nil,
        activeFormatDescription: nil,
        resolutionText: nil,
        fpsText: nil,
        hasIntrinsics: false,
        fx: nil,
        fy: nil,
        cx: nil,
        cy: nil,
        lensPosition: nil,
        lastLensPositionChangeAgeSeconds: nil,
        isFocusStable: nil,
        isFocusSettling: nil,
        sharpness: nil,
        averageSharpness: nil,
        minimumAllowedSharpness: nil,
        minimumPreferredSharpness: nil,
        isAdjustingFocus: nil,
        isAdjustingExposure: nil,
        isAdjustingWhiteBalance: nil,
        focusMode: nil,
        exposureMode: nil,
        iso: nil,
        exposureDurationSeconds: nil,
        cameraStabilityScore: nil,
        rotationStabilityScore: nil,
        isCameraLocked: false,
        automaticLockEnabled: false,
        videoZoomFactor: nil,
        minimumAvailableVideoZoomFactor: nil,
        maximumAvailableVideoZoomFactor: nil,
        highResolutionFormatSelectionEnabled: false,
        highResolutionFormatAvailable: false,
        highResolutionRequestedDimensions: nil,
        highResolutionAppliedDimensions: nil,
        highResolutionFallbackReason: nil,
        availableFormatCount: nil,
        availableMaxResolutionWidth: nil,
        availableMaxResolutionHeight: nil,
        manualFocusEnabled: false,
        manualLensPosition: nil,
        isManualFocusSupported: nil,
        lockError: nil
    )
}

struct CameraFrame {
    struct Metadata {
        let dimensions: CMVideoDimensions
        let pixelFormat: OSType
        let cameraPosition: AVCaptureDevice.Position
        let isMirrored: Bool
        let lensPosition: Float?
        let lensAperture: Float?
        let exposureDuration: CMTime?
        let iso: Float?
        let intrinsicMatrix: simd_double3x3?
    }

    let pixelBuffer: CVPixelBuffer
    let timestamp: CMTime
    let orientation: AVCaptureVideoOrientation
    let metadata: Metadata
    let cameraQuality: CameraFrameQuality
    let cameraDebugSnapshot: CameraDebugSnapshot

    var width: Int {
        CVPixelBufferGetWidth(pixelBuffer)
    }

    var height: Int {
        CVPixelBufferGetHeight(pixelBuffer)
    }

    var timestampSeconds: Double {
        CMTimeGetSeconds(timestamp)
    }
}
