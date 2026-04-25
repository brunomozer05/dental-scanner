import AVFoundation
import Combine
import Foundation

final class ScannerViewModel: ObservableObject {
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
    @Published private(set) var arucoErrorMessage: String?
    @Published private(set) var errorMessage: String?

    private let cameraService: CameraFrameService
    private let arUcoDetector: ArUcoDetector
    private var shouldRunCamera = false
    private var totalFramesCounter: Int = 0
    private var recentFrameTimestamps: [Double] = []

    var captureSession: AVCaptureSession {
        cameraService.captureSession
    }

    init(
        cameraService: CameraFrameService = CameraFrameService(),
        arUcoDetector: ArUcoDetector = ArUcoDetector()
    ) {
        self.cameraService = cameraService
        self.arUcoDetector = arUcoDetector
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
            await MainActor.run {
                cameraState = .ready
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
            self.arucoErrorMessage = arucoMetrics.errorMessage
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

    private func detectArucoMarkers(in frame: CameraFrame) -> ArucoMetrics {
        let isOpenCVAvailable = arUcoDetector.isOpenCVAvailable
        guard isOpenCVAvailable else {
            return ArucoMetrics(
                isOpenCVAvailable: false,
                detectedMarkerCount: 0,
                detectedMarkerIds: [],
                errorMessage: nil
            )
        }

        do {
            let detections = try arUcoDetector.detectMarkers(in: frame)
            let markerIds = detections.map(\.markerId).sorted()

            return ArucoMetrics(
                isOpenCVAvailable: true,
                detectedMarkerCount: detections.count,
                detectedMarkerIds: markerIds,
                errorMessage: nil
            )
        } catch {
            return ArucoMetrics(
                isOpenCVAvailable: true,
                detectedMarkerCount: 0,
                detectedMarkerIds: [],
                errorMessage: error.localizedDescription
            )
        }
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
