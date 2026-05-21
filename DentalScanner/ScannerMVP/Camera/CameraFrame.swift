import AVFoundation
import CoreMedia
import CoreVideo
import simd

struct CameraFrameQuality: Equatable {
    let isAdjustingFocus: Bool
    let isAdjustingExposure: Bool
    let isAdjustingWhiteBalance: Bool
    let lensPosition: Float?
    let iso: Float?
    let exposureDurationSeconds: Double?
    let cameraStabilityScore: Double
    let rotationStabilityScore: Double

    var isUnstable: Bool {
        cameraStabilityScore < 0.999 ||
            isAdjustingFocus ||
            isAdjustingExposure ||
            isAdjustingWhiteBalance
    }

    static let neutral = CameraFrameQuality(
        isAdjustingFocus: false,
        isAdjustingExposure: false,
        isAdjustingWhiteBalance: false,
        lensPosition: nil,
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
    let isAdjustingFocus: Bool?
    let isAdjustingExposure: Bool?
    let isAdjustingWhiteBalance: Bool?
    let iso: Float?
    let exposureDurationSeconds: Double?
    let cameraStabilityScore: Double?
    let rotationStabilityScore: Double?
    let isCameraLocked: Bool
    let automaticLockEnabled: Bool
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
        isAdjustingFocus: nil,
        isAdjustingExposure: nil,
        isAdjustingWhiteBalance: nil,
        iso: nil,
        exposureDurationSeconds: nil,
        cameraStabilityScore: nil,
        rotationStabilityScore: nil,
        isCameraLocked: false,
        automaticLockEnabled: false,
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
