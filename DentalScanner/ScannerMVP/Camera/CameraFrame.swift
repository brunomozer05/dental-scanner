import AVFoundation
import CoreMedia
import CoreVideo
import simd

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
        let intrinsicMatrix: simd_float3x3?
    }

    let pixelBuffer: CVPixelBuffer
    let timestamp: CMTime
    let orientation: AVCaptureVideoOrientation
    let metadata: Metadata

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
