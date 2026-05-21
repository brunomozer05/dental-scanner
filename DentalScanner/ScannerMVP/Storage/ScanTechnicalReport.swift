import Foundation

struct ScanTechnicalReport: Codable {
    var createdAt: String
    var markerProfile: String
    var stlFileName: String?
    var device: Device
    var cameraQuality: CameraQuality
    var markers: [Marker]
    var scanQuality: ScanQuality

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
}
