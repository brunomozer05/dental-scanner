import AVFoundation
import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
import simd

final class CameraFrameService: NSObject {
    struct Configuration {
        var sessionPreset: AVCaptureSession.Preset = .high
        var preferredFrameRate: Int32 = 30
        var videoOrientation: AVCaptureVideoOrientation = .portrait
        var alwaysDiscardsLateFrames: Bool = true
        var pixelFormatType: OSType = kCVPixelFormatType_32BGRA
        var deviceControls: DeviceControls = .default
    }

    struct DeviceControls {
        var focusMode: AVCaptureDevice.FocusMode = .continuousAutoFocus
        var exposureMode: AVCaptureDevice.ExposureMode = .continuousAutoExposure
        var whiteBalanceMode: AVCaptureDevice.WhiteBalanceMode = .continuousAutoWhiteBalance

        static let `default` = DeviceControls()
    }

    enum ServiceError: Error {
        case cameraPermissionDenied
        case restrictedAuthorization
        case cameraUnavailable
        case torchUnavailable
        case unableToCreateInput(Error)
        case unableToAddInput
        case unableToAddOutput
        case deviceConfigurationFailed(Error)
        case sessionNotPrepared
        case missingPixelBuffer
    }

    struct TorchState {
        let isAvailable: Bool
        let isEnabled: Bool
    }

    private let configuration: Configuration
    private let sessionQueue = DispatchQueue(label: "ScannerMVP.CameraFrameService.SessionQueue", qos: .userInitiated)
    private let outputQueue = DispatchQueue(label: "ScannerMVP.CameraFrameService.OutputQueue", qos: .userInitiated)
    private let callbackQueue: DispatchQueue?
    private let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()

    private var isPrepared = false
    private var currentVideoOrientation: AVCaptureVideoOrientation
    private var activeDevice: AVCaptureDevice?

    var onFrame: ((CameraFrame) -> Void)?
    var onError: ((Error) -> Void)?

    var captureSession: AVCaptureSession {
        session
    }

    init(
        configuration: Configuration = Configuration(),
        callbackQueue: DispatchQueue? = nil
    ) {
        self.configuration = configuration
        self.callbackQueue = callbackQueue
        self.currentVideoOrientation = configuration.videoOrientation
        super.init()
    }

    func prepare() async throws {
        try await requestVideoAccessIfNeeded()
        try await configureSessionIfNeeded()
    }

    func startRunning() {
        sessionQueue.async { [weak self] in
            guard let self else { return }

            guard self.isPrepared else {
                self.deliver(error: ServiceError.sessionNotPrepared)
                return
            }

            guard !self.session.isRunning else {
                return
            }

            self.session.startRunning()
            self.applyStartupVideoZoom(to: self.activeDevice)
        }
    }

    func stopRunning() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    func setVideoOrientation(_ orientation: AVCaptureVideoOrientation) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.currentVideoOrientation = orientation

            guard let connection = self.videoOutput.connection(with: .video) else {
                return
            }

            guard connection.isVideoOrientationSupported else {
                return
            }

            connection.videoOrientation = orientation
        }
    }

    func updateDeviceControls(_ controls: DeviceControls) async throws {
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(returning: ())
                    return
                }

                guard let device = self.activeDevice else {
                    continuation.resume(throwing: ServiceError.cameraUnavailable)
                    return
                }

                do {
                    try self.applyDeviceControls(controls, to: device)
                    continuation.resume(returning: ())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func fetchTorchState() async -> TorchState {
        await withCheckedContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let self, let device = self.activeDevice else {
                    continuation.resume(returning: TorchState(isAvailable: false, isEnabled: false))
                    return
                }

                let isAvailable = self.isTorchSupported(on: device)
                let isEnabled = isAvailable && device.torchMode == .on
                continuation.resume(returning: TorchState(isAvailable: isAvailable, isEnabled: isEnabled))
            }
        }
    }

    func setTorchEnabled(_ isEnabled: Bool) async throws -> TorchState {
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(returning: TorchState(isAvailable: false, isEnabled: false))
                    return
                }

                guard let device = self.activeDevice else {
                    continuation.resume(throwing: ServiceError.cameraUnavailable)
                    return
                }

                guard self.isTorchSupported(on: device) else {
                    continuation.resume(returning: TorchState(isAvailable: false, isEnabled: false))
                    return
                }

                do {
                    try device.lockForConfiguration()
                    defer { device.unlockForConfiguration() }

                    device.torchMode = isEnabled ? .on : .off

                    continuation.resume(
                        returning: TorchState(
                            isAvailable: true,
                            isEnabled: device.torchMode == .on
                        )
                    )
                } catch {
                    continuation.resume(throwing: ServiceError.deviceConfigurationFailed(error))
                }
            }
        }
    }

    private func requestVideoAccessIfNeeded() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return
        case .notDetermined:
            let granted = await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .video) { allowed in
                    continuation.resume(returning: allowed)
                }
            }

            guard granted else {
                throw ServiceError.cameraPermissionDenied
            }
        case .denied:
            throw ServiceError.cameraPermissionDenied
        case .restricted:
            throw ServiceError.restrictedAuthorization
        @unknown default:
            throw ServiceError.cameraPermissionDenied
        }
    }

    private func configureSessionIfNeeded() async throws {
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(returning: ())
                    return
                }

                if self.isPrepared {
                    continuation.resume(returning: ())
                    return
                }

                do {
                    try self.configureSession()
                    self.isPrepared = true
                    continuation.resume(returning: ())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func configureSession() throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = configuration.sessionPreset

        let device = try makeBackCameraDevice()
        let input: AVCaptureDeviceInput

        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            throw ServiceError.unableToCreateInput(error)
        }

        guard session.canAddInput(input) else {
            throw ServiceError.unableToAddInput
        }

        session.addInput(input)
        activeDevice = device

        try applyDeviceControls(configuration.deviceControls, to: device)
        try applyPreferredFrameRate(configuration.preferredFrameRate, to: device)

        videoOutput.alwaysDiscardsLateVideoFrames = configuration.alwaysDiscardsLateFrames
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: configuration.pixelFormatType
        ]
        videoOutput.setSampleBufferDelegate(self, queue: outputQueue)

        guard session.canAddOutput(videoOutput) else {
            throw ServiceError.unableToAddOutput
        }

        session.addOutput(videoOutput)

        if let connection = videoOutput.connection(with: .video) {
            if connection.isVideoOrientationSupported {
                connection.videoOrientation = currentVideoOrientation
            }

            if connection.isVideoMirroringSupported {
                connection.isVideoMirrored = false
            }

            if connection.isCameraIntrinsicMatrixDeliverySupported {
                connection.isCameraIntrinsicMatrixDeliveryEnabled = true
            }
        }
    }

    private func makeBackCameraDevice() throws -> AVCaptureDevice {
        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
            return device
        }

        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera],
            mediaType: .video,
            position: .back
        )

        if let device = discoverySession.devices.first {
            return device
        }

        throw ServiceError.cameraUnavailable
    }

    private func applyDeviceControls(_ controls: DeviceControls, to device: AVCaptureDevice) throws {
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }

            if device.isFocusModeSupported(controls.focusMode) {
                device.focusMode = controls.focusMode
            }

            if device.isExposureModeSupported(controls.exposureMode) {
                device.exposureMode = controls.exposureMode
            }

            if device.isWhiteBalanceModeSupported(controls.whiteBalanceMode) {
                device.whiteBalanceMode = controls.whiteBalanceMode
            }
        } catch {
            throw ServiceError.deviceConfigurationFailed(error)
        }
    }

    private func applyPreferredFrameRate(_ frameRate: Int32, to device: AVCaptureDevice) throws {
        let targetFrameRate = Double(frameRate)
        let supportsTargetFrameRate = device.activeFormat.videoSupportedFrameRateRanges.contains { range in
            range.minFrameRate <= targetFrameRate && targetFrameRate <= range.maxFrameRate
        }

        guard supportsTargetFrameRate else {
            return
        }

        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }

            let frameDuration = CMTime(value: 1, timescale: frameRate)
            device.activeVideoMinFrameDuration = frameDuration
            device.activeVideoMaxFrameDuration = frameDuration
        } catch {
            throw ServiceError.deviceConfigurationFailed(error)
        }
    }

    private func isTorchSupported(on device: AVCaptureDevice) -> Bool {
        device.hasTorch && device.isTorchModeSupported(.on) && device.isTorchModeSupported(.off)
    }

    private func applyStartupVideoZoom(to device: AVCaptureDevice?) {
        guard let device else { return }

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }

                let desiredZoom: CGFloat = 1.2
                let maxZoom = device.activeFormat.videoMaxZoomFactor

                device.videoZoomFactor = min(desiredZoom, maxZoom)
            } catch {
                print("Erro ao aplicar zoom: \(error)")
            }
        }
    }

    private func buildFrame(from sampleBuffer: CMSampleBuffer, connection: AVCaptureConnection) -> CameraFrame? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            deliver(error: ServiceError.missingPixelBuffer)
            return nil
        }

        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer)
        let dimensions = formatDescription.map { CMVideoFormatDescriptionGetDimensions($0) }
            ?? CMVideoDimensions(
                width: Int32(CVPixelBufferGetWidth(pixelBuffer)),
                height: Int32(CVPixelBufferGetHeight(pixelBuffer))
            )

        let metadata = CameraFrame.Metadata(
            dimensions: dimensions,
            pixelFormat: CVPixelBufferGetPixelFormatType(pixelBuffer),
            cameraPosition: activeDevice?.position ?? .unspecified,
            isMirrored: connection.isVideoMirrored,
            lensPosition: activeDevice?.lensPosition,
            lensAperture: activeDevice?.lensAperture,
            exposureDuration: activeDevice?.exposureDuration,
            iso: activeDevice?.iso,
            intrinsicMatrix: extractIntrinsicMatrix(from: sampleBuffer)
        )

        return CameraFrame(
            pixelBuffer: pixelBuffer,
            timestamp: timestamp,
            orientation: connection.videoOrientation,
            metadata: metadata
        )
    }

    private func extractIntrinsicMatrix(from sampleBuffer: CMSampleBuffer) -> simd_float3x3? {
        guard let data = CMGetAttachment(
            sampleBuffer,
            key: kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix,
            attachmentModeOut: nil
        ) as? Data else {
            return nil
        }

        guard data.count >= MemoryLayout<simd_float3x3>.stride else {
            return nil
        }

        var matrix = simd_float3x3()
        _ = withUnsafeMutableBytes(of: &matrix) { destination in
            data.copyBytes(to: destination)
        }

        return matrix
    }

    private func deliver(error: Error) {
        if let callbackQueue {
            callbackQueue.async { [weak self] in
                self?.onError?(error)
            }
        } else {
            onError?(error)
        }
    }
}

extension CameraFrameService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let frame = buildFrame(from: sampleBuffer, connection: connection) else {
            return
        }

        if let callbackQueue = callbackQueue {
            callbackQueue.async { [weak self] in
                self?.onFrame?(frame)
            }
        } else {
            onFrame?(frame)
        }
    }
}
