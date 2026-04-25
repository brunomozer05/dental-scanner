import CoreGraphics
import CoreVideo
import Foundation

final class ArUcoDetector {
    static let dictionaryName = "DICT_4X4_50"
    static let preprocessingDescription = "BGRA -> grayscale"

    enum DetectorError: LocalizedError {
        case invalidCornerCount(markerId: Int, count: Int)

        var errorDescription: String? {
            switch self {
            case let .invalidCornerCount(markerId, count):
                return "ArUco marker \(markerId) returned \(count) corners instead of 4."
            }
        }
    }

    private let bridge: OpenCVArucoPoseBridge

    private(set) var hasReceivedFrame = false
    private(set) var detectionCallCount = 0
    private(set) var lastFrameWidth: Int?
    private(set) var lastFrameHeight: Int?
    private(set) var lastBytesPerRow: Int?
    private(set) var lastPixelFormat: OSType?
    private(set) var lastInputChannelCount: Int?
    private(set) var lastConvertedToGrayscale = false
    private(set) var lastGrayscaleChannelCount: Int?
    private(set) var lastDetectedMarkerCount = 0
    private(set) var lastRejectedCandidateCount: Int?
    private(set) var lastErrorMessage: String?

    init(bridge: OpenCVArucoPoseBridge = OpenCVArucoPoseBridge()) {
        self.bridge = bridge
    }

    var isOpenCVAvailable: Bool {
        bridge.isOpenCVAvailable
    }

    func detectMarkers(in frame: CameraFrame) throws -> [ArUcoDetectionResult] {
        hasReceivedFrame = true
        detectionCallCount += 1
        recordFrameDiagnostics(frame)

        guard bridge.isOpenCVAvailable else {
            lastDetectedMarkerCount = 0
            lastRejectedCandidateCount = nil
            lastErrorMessage = "OpenCV is unavailable."
            return []
        }

        let detections: [OpenCVArucoMarkerDetection]
        do {
            detections = try bridge.detectAruco4x4Markers(in: frame.pixelBuffer)
            recordBridgeDiagnostics(fallbackFrame: frame)
            lastErrorMessage = nil
        } catch {
            recordBridgeDiagnostics(fallbackFrame: frame)
            lastDetectedMarkerCount = 0
            lastErrorMessage = error.localizedDescription
            throw error
        }

        do {
            let results = try detections.map { detection in
                let corners = detection.corners.map { corner in
                    CGPoint(x: corner.x, y: corner.y)
                }

                guard corners.count == 4 else {
                    throw DetectorError.invalidCornerCount(markerId: detection.markerId, count: corners.count)
                }

                return ArUcoDetectionResult(markerId: detection.markerId, corners: corners)
            }

            lastDetectedMarkerCount = results.count
            return results
        } catch {
            lastErrorMessage = error.localizedDescription
            throw error
        }
    }

    private func recordFrameDiagnostics(_ frame: CameraFrame) {
        lastFrameWidth = frame.width
        lastFrameHeight = frame.height
        lastPixelFormat = frame.metadata.pixelFormat
        lastBytesPerRow = CVPixelBufferGetBytesPerRow(frame.pixelBuffer)
        lastInputChannelCount = nil
        lastConvertedToGrayscale = false
        lastGrayscaleChannelCount = nil
        lastRejectedCandidateCount = nil
    }

    private func recordBridgeDiagnostics(fallbackFrame frame: CameraFrame) {
        guard let diagnostics = bridge.lastDiagnostics else {
            recordFrameDiagnostics(frame)
            return
        }

        lastFrameWidth = diagnostics.frameWidth
        lastFrameHeight = diagnostics.frameHeight
        lastBytesPerRow = diagnostics.bytesPerRow
        lastPixelFormat = diagnostics.pixelFormat
        lastInputChannelCount = diagnostics.inputChannelCount
        lastConvertedToGrayscale = diagnostics.convertedToGrayscale
        lastGrayscaleChannelCount = diagnostics.grayscaleChannelCount
        lastDetectedMarkerCount = diagnostics.detectedMarkerCount
        lastRejectedCandidateCount = diagnostics.rejectedCandidateCount
    }
}
