import AVFoundation
import Combine
import CoreVideo
import Foundation

final class ScannerViewModel: ObservableObject {
    private enum OverlayStabilization {
        static let timeout: Double = 0.2
    }

    private enum PoseConfiguration {
        static let markerSizeMillimeters: Double = 8.0
    }

    enum CameraState: Equatable {
        case idle
        case preparing
        case ready
        case running
        case failed
    }

    struct FrameResolution: Equatable {
        let width: Int
        let height: Int
    }

    @Published private(set) var cameraState: CameraState = .idle
    @Published private(set) var totalFramesReceived: Int = 0
    @Published private(set) var estimatedFPS: Double = 0
    @Published private(set) var lastFrameTimestamp: Double?
    @Published private(set) var frameResolution: FrameResolution?
    @Published private(set) var isIntrinsicMatrixAvailable: Bool = false
    @Published private(set) var isOpenCVAvailable: Bool = false
    @Published private(set) var detectedMarkerCount: Int = 0
    @Published private(set) var detectedMarkerIds: [Int] = []
    @Published private(set) var detectedMarkers: [ArUcoDetectionResult] = []
    @Published private(set) var overlayMarkers: [ArUcoDetectionResult] = []
    @Published private(set) var arucoErrorMessage: String?
    @Published private(set) var hasFrameReachedArucoDetector: Bool = false
    @Published private(set) var arucoDetectionCallCount: Int = 0
    @Published private(set) var arucoFrameResolution: FrameResolution?
    @Published private(set) var arucoFramePixelFormat: String = "-"
    @Published private(set) var arucoBytesPerRow: Int?
    @Published private(set) var arucoDictionaryName: String = ArUcoDetector.dictionaryName
    @Published private(set) var arucoPreprocessingDescription: String = ArUcoDetector.preprocessingDescription
    @Published private(set) var arucoInputChannelCount: Int?
    @Published private(set) var arucoGrayscaleChannelCount: Int?
    @Published private(set) var arucoRejectedCandidateCount: Int?
    @Published private(set) var poseMarkerId: Int?
    @Published private(set) var poseDistanceMm: Double?
    @Published private(set) var poseReprojectionError: Double?
    @Published private(set) var poseErrorMessage: String?
    @Published private(set) var poseMarkerSizeMillimeters: Double = PoseConfiguration.markerSizeMillimeters
    @Published private(set) var isTorchAvailable: Bool = false
    @Published private(set) var isTorchEnabled: Bool = false
    @Published private(set) var errorMessage: String?

    private let cameraService: CameraFrameService
    private let arUcoDetector: ArUcoDetector
    private let poseEstimator: PoseEstimator
    private var shouldRunCamera = false
    private var totalFramesCounter: Int = 0
    private var recentFrameTimestamps: [Double] = []
    private var lastValidOverlayDetections: [ArUcoDetectionResult] = []
    private var lastValidOverlayTimestamp: Double?

    var captureSession: AVCaptureSession {
        cameraService.captureSession
    }

    init(
        cameraService: CameraFrameService = CameraFrameService(),
        arUcoDetector: ArUcoDetector = ArUcoDetector(),
        poseEstimator: PoseEstimator = PoseEstimator()
    ) {
        self.cameraService = cameraService
        self.arUcoDetector = arUcoDetector
        self.poseEstimator = poseEstimator
        self.isOpenCVAvailable = arUcoDetector.isOpenCVAvailable
        bindCameraCallbacks()
    }

    func prepareCamera() async {
        let currentState = await MainActor.run { cameraState }
        guard currentState != .preparing else {
            return
        }

        await MainActor.run {
            errorMessage = nil
            cameraState = .preparing
        }

        do {
            try await cameraService.prepare()
            let torchState = await cameraService.fetchTorchState()
            await MainActor.run {
                cameraState = .ready
                isTorchAvailable = torchState.isAvailable
                isTorchEnabled = torchState.isEnabled
            }
        } catch {
            await MainActor.run {
                handleCameraError(error)
            }
        }
    }

    func startCamera() async {
        let currentState = await MainActor.run {
            shouldRunCamera = true
            return cameraState
        }
        if currentState == .idle || currentState == .failed {
            await prepareCamera()
        }

        let startContext = await MainActor.run { (cameraState, shouldRunCamera) }
        let preparedState = startContext.0
        let shouldContinueRunning = startContext.1

        guard shouldContinueRunning, !Task.isCancelled else {
            return
        }

        guard preparedState == .ready else {
            return
        }

        cameraService.startRunning()
        await MainActor.run {
            cameraState = .running
        }
    }

    @MainActor
    func stopCamera() {
        shouldRunCamera = false
        cameraService.stopRunning()
        guard cameraState != .failed else { return }
        cameraState = .ready
    }

    @MainActor
    func toggleTorch() {
        guard isTorchAvailable else { return }

        let targetState = !isTorchEnabled
        Task { [weak self] in
            guard let self else { return }

            do {
                let torchState = try await self.cameraService.setTorchEnabled(targetState)
                await MainActor.run {
                    self.isTorchAvailable = torchState.isAvailable
                    self.isTorchEnabled = torchState.isEnabled
                    self.errorMessage = nil
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = self.makeErrorMessage(from: error)
                }
            }
        }
    }

    private func bindCameraCallbacks() {
        cameraService.onFrame = { [weak self] frame in
            self?.handleFrame(frame)
        }

        cameraService.onError = { [weak self] error in
            Task { @MainActor [weak self] in
                self?.handleCameraError(error)
            }
        }
    }

    private func handleFrame(_ frame: CameraFrame) {
        let metrics = buildFrameMetrics(from: frame)
        let arucoMetrics = detectArucoMarkers(in: frame)
        let overlayMarkers = stabilizedOverlayDetections(
            from: arucoMetrics.detections,
            timestamp: metrics.lastFrameTimestamp
        )
        let poseMetrics = estimatePose(from: arucoMetrics.detections, in: frame)

        Task { @MainActor [weak self] in
            guard let self else { return }
            self.totalFramesReceived = metrics.totalFramesReceived
            self.estimatedFPS = metrics.estimatedFPS
            self.lastFrameTimestamp = metrics.lastFrameTimestamp
            self.frameResolution = metrics.frameResolution
            self.isIntrinsicMatrixAvailable = metrics.isIntrinsicMatrixAvailable
            self.isOpenCVAvailable = arucoMetrics.isOpenCVAvailable
            self.detectedMarkerCount = arucoMetrics.detectedMarkerCount
            self.detectedMarkerIds = arucoMetrics.detectedMarkerIds
            self.detectedMarkers = arucoMetrics.detections
            self.overlayMarkers = overlayMarkers
            self.arucoErrorMessage = arucoMetrics.errorMessage
            self.hasFrameReachedArucoDetector = arucoMetrics.hasFrameReachedDetector
            self.arucoDetectionCallCount = arucoMetrics.detectionCallCount
            self.arucoFrameResolution = arucoMetrics.frameResolution
            self.arucoFramePixelFormat = arucoMetrics.pixelFormat
            self.arucoBytesPerRow = arucoMetrics.bytesPerRow
            self.arucoDictionaryName = arucoMetrics.dictionaryName
            self.arucoPreprocessingDescription = arucoMetrics.preprocessingDescription
            self.arucoInputChannelCount = arucoMetrics.inputChannelCount
            self.arucoGrayscaleChannelCount = arucoMetrics.grayscaleChannelCount
            self.arucoRejectedCandidateCount = arucoMetrics.rejectedCandidateCount
            self.poseMarkerId = poseMetrics.markerId
            self.poseDistanceMm = poseMetrics.distanceMm
            self.poseReprojectionError = poseMetrics.reprojectionError
            self.poseErrorMessage = poseMetrics.errorMessage
        }
    }

    private func buildFrameMetrics(from frame: CameraFrame) -> FrameMetrics {
        totalFramesCounter += 1
        let timestamp = frame.timestampSeconds
        let estimatedFPS = updateEstimatedFPS(with: timestamp)

        return FrameMetrics(
            totalFramesReceived: totalFramesCounter,
            estimatedFPS: estimatedFPS,
            lastFrameTimestamp: timestamp,
            frameResolution: FrameResolution(width: frame.width, height: frame.height),
            isIntrinsicMatrixAvailable: frame.metadata.intrinsicMatrix != nil
        )
    }

    private func stabilizedOverlayDetections(
        from detections: [ArUcoDetectionResult],
        timestamp: Double
    ) -> [ArUcoDetectionResult] {
        guard timestamp.isFinite else {
            return detections
        }

        if !detections.isEmpty {
            lastValidOverlayDetections = detections
            lastValidOverlayTimestamp = timestamp
            return detections
        }

        guard let lastValidOverlayTimestamp else {
            lastValidOverlayDetections = []
            return []
        }

        if timestamp - lastValidOverlayTimestamp <= OverlayStabilization.timeout {
            return lastValidOverlayDetections
        }

        lastValidOverlayDetections = []
        self.lastValidOverlayTimestamp = nil
        return []
    }

    private func detectArucoMarkers(in frame: CameraFrame) -> ArucoMetrics {
        do {
            let detections = try arUcoDetector.detectMarkers(in: frame)
            let markerIds = detections.map(\.markerId).sorted()

            return ArucoMetrics(
                isOpenCVAvailable: arUcoDetector.isOpenCVAvailable,
                detectedMarkerCount: detections.count,
                detectedMarkerIds: markerIds,
                detections: detections,
                errorMessage: arUcoDetector.lastErrorMessage,
                hasFrameReachedDetector: arUcoDetector.hasReceivedFrame,
                detectionCallCount: arUcoDetector.detectionCallCount,
                frameResolution: makeArucoFrameResolution(),
                pixelFormat: formatPixelFormat(arUcoDetector.lastPixelFormat),
                bytesPerRow: arUcoDetector.lastBytesPerRow,
                dictionaryName: ArUcoDetector.dictionaryName,
                preprocessingDescription: formatArucoPreprocessing(),
                inputChannelCount: arUcoDetector.lastInputChannelCount,
                grayscaleChannelCount: arUcoDetector.lastGrayscaleChannelCount,
                rejectedCandidateCount: arUcoDetector.lastRejectedCandidateCount
            )
        } catch {
            let errorDescription = error.localizedDescription
            let detectorErrorMessage = errorDescription.isEmpty ? arUcoDetector.lastErrorMessage : errorDescription

            return ArucoMetrics(
                isOpenCVAvailable: arUcoDetector.isOpenCVAvailable,
                detectedMarkerCount: arUcoDetector.lastDetectedMarkerCount,
                detectedMarkerIds: [],
                detections: [],
                errorMessage: detectorErrorMessage,
                hasFrameReachedDetector: arUcoDetector.hasReceivedFrame,
                detectionCallCount: arUcoDetector.detectionCallCount,
                frameResolution: makeArucoFrameResolution(),
                pixelFormat: formatPixelFormat(arUcoDetector.lastPixelFormat),
                bytesPerRow: arUcoDetector.lastBytesPerRow,
                dictionaryName: ArUcoDetector.dictionaryName,
                preprocessingDescription: formatArucoPreprocessing(),
                inputChannelCount: arUcoDetector.lastInputChannelCount,
                grayscaleChannelCount: arUcoDetector.lastGrayscaleChannelCount,
                rejectedCandidateCount: arUcoDetector.lastRejectedCandidateCount
            )
        }
    }

    private func estimatePose(from detections: [ArUcoDetectionResult], in frame: CameraFrame) -> PoseMetrics {
        guard !detections.isEmpty else {
            return PoseMetrics(markerId: nil, distanceMm: nil, reprojectionError: nil, errorMessage: nil)
        }

        do {
            let poses = try poseEstimator.estimatePoses(
                for: detections,
                in: frame,
                markerSizeMillimeters: PoseConfiguration.markerSizeMillimeters
            )
            guard let pose = poses.first else {
                return PoseMetrics(markerId: nil, distanceMm: nil, reprojectionError: nil, errorMessage: nil)
            }

            return PoseMetrics(
                markerId: pose.markerId,
                distanceMm: pose.distanceMm,
                reprojectionError: pose.reprojectionError,
                errorMessage: nil
            )
        } catch {
            return PoseMetrics(
                markerId: nil,
                distanceMm: nil,
                reprojectionError: nil,
                errorMessage: error.localizedDescription
            )
        }
    }

    private func makeArucoFrameResolution() -> FrameResolution? {
        guard let width = arUcoDetector.lastFrameWidth,
              let height = arUcoDetector.lastFrameHeight
        else {
            return nil
        }

        return FrameResolution(width: width, height: height)
    }

    private func formatPixelFormat(_ pixelFormat: OSType?) -> String {
        guard let pixelFormat else {
            return "-"
        }

        switch pixelFormat {
        case kCVPixelFormatType_32BGRA:
            return "32BGRA"
        default:
            return "\(pixelFormat)"
        }
    }

    private func formatArucoPreprocessing() -> String {
        guard arUcoDetector.lastConvertedToGrayscale else {
            return "Nao aplicada"
        }

        guard let inputChannelCount = arUcoDetector.lastInputChannelCount,
              let grayscaleChannelCount = arUcoDetector.lastGrayscaleChannelCount
        else {
            return ArUcoDetector.preprocessingDescription
        }

        return "\(ArUcoDetector.preprocessingDescription) (\(inputChannelCount) -> \(grayscaleChannelCount) canais)"
    }

    private func updateEstimatedFPS(with timestamp: Double) -> Double {
        guard timestamp.isFinite else {
            recentFrameTimestamps.removeAll()
            return 0
        }

        recentFrameTimestamps.append(timestamp)

        let oneSecondAgo = timestamp - 1.0
        recentFrameTimestamps.removeAll { $0 < oneSecondAgo }

        guard recentFrameTimestamps.count >= 2,
              let firstTimestamp = recentFrameTimestamps.first,
              let lastTimestamp = recentFrameTimestamps.last
        else {
            return 0
        }

        let elapsed = lastTimestamp - firstTimestamp
        guard elapsed > 0 else {
            return 0
        }

        return Double(recentFrameTimestamps.count - 1) / elapsed
    }

    private func handleCameraError(_ error: Error) {
        cameraState = .failed
        errorMessage = makeErrorMessage(from: error)
    }

    private struct FrameMetrics {
        let totalFramesReceived: Int
        let estimatedFPS: Double
        let lastFrameTimestamp: Double
        let frameResolution: FrameResolution
        let isIntrinsicMatrixAvailable: Bool
    }

    private struct ArucoMetrics {
        let isOpenCVAvailable: Bool
        let detectedMarkerCount: Int
        let detectedMarkerIds: [Int]
        let detections: [ArUcoDetectionResult]
        let errorMessage: String?
        let hasFrameReachedDetector: Bool
        let detectionCallCount: Int
        let frameResolution: FrameResolution?
        let pixelFormat: String
        let bytesPerRow: Int?
        let dictionaryName: String
        let preprocessingDescription: String
        let inputChannelCount: Int?
        let grayscaleChannelCount: Int?
        let rejectedCandidateCount: Int?
    }

    private struct PoseMetrics {
        let markerId: Int?
        let distanceMm: Double?
        let reprojectionError: Double?
        let errorMessage: String?
    }

    private func makeErrorMessage(from error: Error) -> String {
        guard let serviceError = error as? CameraFrameService.ServiceError else {
            return error.localizedDescription
        }

        switch serviceError {
        case .cameraPermissionDenied:
            return "Camera access was denied."
        case .restrictedAuthorization:
            return "Camera access is restricted on this device."
        case .cameraUnavailable:
            return "Back camera is unavailable."
        case .torchUnavailable:
            return "Torch is unavailable on this device."
        case .unableToCreateInput:
            return "Unable to create camera input."
        case .unableToAddInput:
            return "Unable to add camera input to the session."
        case .unableToAddOutput:
            return "Unable to add video output to the session."
        case .deviceConfigurationFailed:
            return "Unable to configure camera device."
        case .sessionNotPrepared:
            return "Camera session is not prepared."
        case .missingPixelBuffer:
            return "Captured frame is missing its pixel buffer."
        }
    }
}
