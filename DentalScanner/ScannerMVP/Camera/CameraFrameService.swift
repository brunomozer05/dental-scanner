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
    private let cameraControlStateLock = NSLock()

    private var isPrepared = false
    private var currentVideoOrientation: AVCaptureVideoOrientation
    private var activeDevice: AVCaptureDevice?
    private var automaticFocusExposureLockEnabled = false
    private var cameraControlsLocked = false
    private var isAutomaticLockInFlight = false
    private var lastCameraLockError: String?
    private var cameraQualityConfiguration: CameraFrameQualityConfiguration = .scannerDefault
    private var previousLensPosition: Float?
    private var lastLensPositionChangeTimestamp: Double?
    private var forceFocusSettleOnNextFrame = false
    private var recentSharpnessValues: [Double] = []
    private var focusRequestGeneration = 0
    private var desiredVideoZoomFactor: CGFloat = 1.0
    private var manualFocusEnabled = false
    private var manualLensPosition: Float = 0.5

    var onFrame: ((CameraFrame) -> Void)?
    var onError: ((Error) -> Void)?
    var onSessionDidBecomeActive: (() -> Void)?

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
        registerSessionNotifications()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
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

    func setAutomaticFocusExposureLockEnabled(_ isEnabled: Bool) async -> CameraDebugSnapshot {
        await withCheckedContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(returning: .unavailable)
                    return
                }

                self.setAutomaticLockEnabled(isEnabled)

                if isEnabled {
                    self.setCameraControlsLocked(false, error: nil)
                } else {
                    self.applyContinuousCameraControlsToActiveDevice()
                }

                continuation.resume(returning: self.makeCameraDebugSnapshot())
            }
        }
    }

    func lockFocusExposureWhiteBalanceNow() async -> CameraDebugSnapshot {
        await withCheckedContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(returning: .unavailable)
                    return
                }

                self.setAutomaticLockEnabled(true)
                self.applyLockedCameraControlsToActiveDevice()
                continuation.resume(returning: self.makeCameraDebugSnapshot())
            }
        }
    }

    func unlockContinuousCameraControls() async -> CameraDebugSnapshot {
        await withCheckedContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(returning: .unavailable)
                    return
                }

                self.setAutomaticLockEnabled(false)
                self.applyContinuousCameraControlsToActiveDevice()
                continuation.resume(returning: self.makeCameraDebugSnapshot())
            }
        }
    }

    func currentCameraDebugSnapshot() async -> CameraDebugSnapshot {
        await withCheckedContinuation { continuation in
            sessionQueue.async { [weak self] in
                continuation.resume(returning: self?.makeCameraDebugSnapshot() ?? .unavailable)
            }
        }
    }

    func updateCameraFrameQualityConfiguration(
        _ configuration: CameraFrameQualityConfiguration
    ) async -> CameraDebugSnapshot {
        await withCheckedContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(returning: .unavailable)
                    return
                }

                self.setCameraQualityConfiguration(configuration)
                continuation.resume(returning: self.makeCameraDebugSnapshot())
            }
        }
    }

    func setVideoZoomFactor(_ zoomFactor: CGFloat) async -> CameraDebugSnapshot {
        await withCheckedContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(returning: .unavailable)
                    return
                }

                let requestedZoom = zoomFactor.isFinite ? max(zoomFactor, 1.0) : 1.0
                self.setDesiredVideoZoomFactor(requestedZoom)

                if let device = self.activeDevice {
                    self.applyVideoZoomFactor(requestedZoom, to: device)
                }

                continuation.resume(returning: self.makeCameraDebugSnapshot())
            }
        }
    }

    func setManualFocus(
        enabled: Bool,
        lensPosition: Float
    ) async -> CameraDebugSnapshot {
        await withCheckedContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(returning: .unavailable)
                    return
                }

                let sanitizedLensPosition = min(max(lensPosition, 0.0), 1.0)
                self.setManualFocusState(
                    isEnabled: enabled,
                    lensPosition: sanitizedLensPosition
                )

                if enabled {
                    self.applyManualFocusToActiveDevice(lensPosition: sanitizedLensPosition)
                } else {
                    self.applyContinuousFocusToActiveDevice()
                }

                continuation.resume(returning: self.makeCameraDebugSnapshot())
            }
        }
    }

    func calibrateFocusNow() async -> CameraDebugSnapshot {
        await withCheckedContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(returning: .unavailable)
                    return
                }

                self.setAutomaticLockEnabled(true)
                self.applyLockedCameraControlsToActiveDevice()
                self.resetFocusStabilityReference(forceSettle: true)
                continuation.resume(returning: self.makeCameraDebugSnapshot())
            }
        }
    }

    func focusAndExpose(
        at normalizedPoint: CGPoint,
        lockAfterFocus: Bool,
        settleTimeSeconds: Double
    ) async -> CameraDebugSnapshot {
        await withCheckedContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(returning: .unavailable)
                    return
                }

                self.focusRequestGeneration += 1
                let generation = self.focusRequestGeneration
                self.applyFocusAndExposurePoint(
                    normalizedPoint,
                    lockAfterFocus: lockAfterFocus,
                    settleTimeSeconds: settleTimeSeconds,
                    generation: generation
                )
                continuation.resume(returning: self.makeCameraDebugSnapshot())
            }
        }
    }

    func recoverContinuousFocus(
        at normalizedPoint: CGPoint,
        settleTimeSeconds: Double
    ) async -> CameraDebugSnapshot {
        await withCheckedContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(returning: .unavailable)
                    return
                }

                self.focusRequestGeneration += 1
                self.applyContinuousFocusRecoveryPoint(
                    normalizedPoint,
                    settleTimeSeconds: settleTimeSeconds
                )
                continuation.resume(returning: self.makeCameraDebugSnapshot())
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

    func setTorchEnabled(
        _ isEnabled: Bool,
        requiresRunningSession: Bool = false
    ) async throws -> TorchState {
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(returning: TorchState(isAvailable: false, isEnabled: false))
                    return
                }

                if requiresRunningSession {
                    guard self.isPrepared, self.session.isRunning else {
                        continuation.resume(throwing: ServiceError.sessionNotPrepared)
                        return
                    }
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
        applyVideoZoomFactor(currentDesiredVideoZoomFactor(), to: device)
        applyManualFocusConfigurationIfNeeded(to: device)

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

        let fallbackDiscoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [
                .builtInTripleCamera,
                .builtInDualWideCamera,
                .builtInDualCamera,
                .builtInUltraWideCamera,
                .builtInTelephotoCamera
            ],
            mediaType: .video,
            position: .back
        )

        if let device = fallbackDiscoverySession.devices.first {
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

    private func applyVideoZoomFactor(
        _ requestedZoomFactor: CGFloat,
        to device: AVCaptureDevice
    ) {
        let minimumZoomFactor = max(device.minAvailableVideoZoomFactor, 1.0)
        let maximumZoomFactor = max(device.maxAvailableVideoZoomFactor, minimumZoomFactor)
        let clampedZoomFactor = min(
            max(requestedZoomFactor, minimumZoomFactor),
            maximumZoomFactor
        )

        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }

            device.videoZoomFactor = clampedZoomFactor
            setDesiredVideoZoomFactor(clampedZoomFactor)
            setCameraControlError(nil)
        } catch {
            setCameraControlError("Zoom falhou: \(error.localizedDescription)")
        }
    }

    private func applyManualFocusConfigurationIfNeeded(to device: AVCaptureDevice) {
        let state = cameraControlState()
        guard state.manualFocusEnabled else {
            return
        }

        applyManualFocus(to: device, lensPosition: state.manualLensPosition)
    }

    private func applyManualFocusToActiveDevice(lensPosition: Float) {
        guard let device = activeDevice else {
            setCameraControlError("Camera indisponivel")
            return
        }

        applyManualFocus(to: device, lensPosition: lensPosition)
    }

    private func applyManualFocus(
        to device: AVCaptureDevice,
        lensPosition: Float
    ) {
        guard device.isLockingFocusWithCustomLensPositionSupported else {
            setManualFocusState(
                isEnabled: false,
                lensPosition: lensPosition
            )
            setCameraControlError("Foco manual nao suportado")
            return
        }

        let sanitizedLensPosition = min(max(lensPosition, 0.0), 1.0)

        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }

            device.setFocusModeLocked(lensPosition: sanitizedLensPosition) { _ in }
            setManualFocusState(
                isEnabled: true,
                lensPosition: sanitizedLensPosition
            )
            setCameraControlError(nil)
            resetFocusStabilityReference(forceSettle: true)
        } catch {
            setManualFocusState(
                isEnabled: false,
                lensPosition: sanitizedLensPosition
            )
            setCameraControlError("Foco manual falhou: \(error.localizedDescription)")
        }
    }

    private func applyContinuousFocusToActiveDevice() {
        guard let device = activeDevice else {
            setCameraControlError("Camera indisponivel")
            return
        }

        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }

            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            } else if device.isFocusModeSupported(.autoFocus) {
                device.focusMode = .autoFocus
            } else {
                setCameraControlError("Foco automatico nao suportado")
                return
            }

            setManualFocusState(
                isEnabled: false,
                lensPosition: device.lensPosition
            )
            setCameraControlError(nil)
            resetFocusStabilityReference(forceSettle: true)
        } catch {
            setCameraControlError("Foco automatico falhou: \(error.localizedDescription)")
        }
    }

    private func applyLockedCameraControlsToActiveDevice() {
        guard let device = activeDevice else {
            setCameraControlsLocked(false, error: "Camera indisponivel")
            return
        }

        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }

            var lockedControlCount = 0
            var unsupportedControls: [String] = []

            if device.isFocusModeSupported(.locked) {
                device.focusMode = .locked
                lockedControlCount += 1
            } else {
                unsupportedControls.append("foco")
            }

            if device.isExposureModeSupported(.locked) {
                device.exposureMode = .locked
                lockedControlCount += 1
            } else {
                unsupportedControls.append("exposicao")
            }

            if device.isWhiteBalanceModeSupported(.locked) {
                device.whiteBalanceMode = .locked
                lockedControlCount += 1
            } else {
                unsupportedControls.append("white balance")
            }

            let error = unsupportedControls.isEmpty
                ? nil
                : "Lock nao suportado: \(unsupportedControls.joined(separator: ", "))"
            setCameraControlsLocked(lockedControlCount > 0, error: error)
        } catch {
            setCameraControlsLocked(false, error: error.localizedDescription)
        }
    }

    private func applyContinuousCameraControlsToActiveDevice() {
        guard let device = activeDevice else {
            setCameraControlsLocked(false, error: "Camera indisponivel")
            return
        }

        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }

            var unsupportedControls: [String] = []

            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            } else if device.isFocusModeSupported(.autoFocus) {
                device.focusMode = .autoFocus
            } else {
                unsupportedControls.append("foco continuo")
            }
            setManualFocusState(
                isEnabled: false,
                lensPosition: device.lensPosition
            )

            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            } else if device.isExposureModeSupported(.autoExpose) {
                device.exposureMode = .autoExpose
            } else {
                unsupportedControls.append("exposicao continua")
            }

            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                device.whiteBalanceMode = .continuousAutoWhiteBalance
            } else if device.isWhiteBalanceModeSupported(.autoWhiteBalance) {
                device.whiteBalanceMode = .autoWhiteBalance
            } else {
                unsupportedControls.append("white balance continuo")
            }

            let error = unsupportedControls.isEmpty
                ? nil
                : "Auto nao suportado: \(unsupportedControls.joined(separator: ", "))"
            setCameraControlsLocked(false, error: error)
        } catch {
            setCameraControlsLocked(false, error: error.localizedDescription)
        }
    }

    private func applyContinuousFocusRecoveryPoint(
        _ normalizedPoint: CGPoint,
        settleTimeSeconds: Double
    ) {
        guard normalizedPoint.x.isFinite,
              normalizedPoint.y.isFinite,
              normalizedPoint.x >= 0,
              normalizedPoint.x <= 1,
              normalizedPoint.y >= 0,
              normalizedPoint.y <= 1
        else {
            setCameraControlsLocked(false, error: "Ponto de recuperacao invalido")
            return
        }

        guard let device = activeDevice else {
            setCameraControlsLocked(false, error: "Camera indisponivel")
            return
        }

        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }

            var appliedFocus = false
            var warnings: [String] = []
            setAutomaticLockEnabled(false)
            setCameraControlsLocked(false, error: nil)
            setManualFocusState(
                isEnabled: false,
                lensPosition: device.lensPosition
            )

            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = normalizedPoint
            } else {
                warnings.append("ponto foco")
            }

            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
                appliedFocus = true
            } else if device.isFocusModeSupported(.autoFocus) {
                device.focusMode = .autoFocus
                appliedFocus = true
            } else {
                warnings.append("foco continuo")
            }

            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = normalizedPoint
            } else {
                warnings.append("ponto exposicao")
            }

            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            } else if device.isExposureModeSupported(.autoExpose) {
                device.exposureMode = .autoExpose
            } else {
                warnings.append("exposicao continua")
            }

            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                device.whiteBalanceMode = .continuousAutoWhiteBalance
            } else if device.isWhiteBalanceModeSupported(.autoWhiteBalance) {
                device.whiteBalanceMode = .autoWhiteBalance
            } else {
                warnings.append("white balance continuo")
            }

            let message: String?
            if appliedFocus {
                message = warnings.isEmpty
                    ? nil
                    : "Recuperacao foco parcial: \(warnings.joined(separator: ", "))"
            } else {
                message = "Recuperacao foco indisponivel: \(warnings.joined(separator: ", "))"
            }

            setCameraControlsLocked(false, error: message)
            resetFocusStabilityReference(forceSettle: settleTimeSeconds > 0.0)
        } catch {
            setCameraControlsLocked(false, error: error.localizedDescription)
        }
    }

    private func applyFocusAndExposurePoint(
        _ normalizedPoint: CGPoint,
        lockAfterFocus: Bool,
        settleTimeSeconds: Double,
        generation: Int
    ) {
        guard normalizedPoint.x.isFinite,
              normalizedPoint.y.isFinite,
              normalizedPoint.x >= 0,
              normalizedPoint.x <= 1,
              normalizedPoint.y >= 0,
              normalizedPoint.y <= 1
        else {
            setCameraControlsLocked(false, error: "Ponto de foco invalido")
            return
        }

        guard let device = activeDevice else {
            setCameraControlsLocked(false, error: "Camera indisponivel")
            return
        }

        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }

            var appliedFocus = false
            var appliedExposure = false
            var warnings: [String] = []
            setManualFocusState(
                isEnabled: false,
                lensPosition: device.lensPosition
            )

            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = normalizedPoint
                if device.isFocusModeSupported(.autoFocus) {
                    device.focusMode = .autoFocus
                    appliedFocus = true
                } else if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                    appliedFocus = true
                } else {
                    warnings.append("modo foco")
                }
            } else {
                warnings.append("ponto foco")
            }

            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = normalizedPoint
                if device.isExposureModeSupported(.autoExpose) {
                    device.exposureMode = .autoExpose
                    appliedExposure = true
                } else if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                    appliedExposure = true
                } else {
                    warnings.append("modo exposicao")
                }
            } else {
                warnings.append("ponto exposicao")
            }

            let message: String?
            if appliedFocus {
                message = warnings.isEmpty
                    ? nil
                    : "Foco parcial: \(warnings.joined(separator: ", "))"
            } else {
                message = "Foco ArUco nao suportado: \(warnings.joined(separator: ", "))"
            }

            setCameraControlsLocked(false, error: message)
            resetFocusStabilityReference(forceSettle: true)

            guard lockAfterFocus, appliedFocus else {
                return
            }

            let delay = max(settleTimeSeconds, 0.0)
            sessionQueue.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self,
                      self.focusRequestGeneration == generation
                else {
                    return
                }

                self.applyLockedCameraControlsToActiveDevice()
            }
        } catch {
            setCameraControlsLocked(false, error: error.localizedDescription)
        }
    }

    private func scheduleAutomaticCameraLockIfNeeded(quality: CameraFrameQuality) {
        let state = cameraControlState()
        guard state.automaticLockEnabled,
              !state.cameraControlsLocked,
              !state.isAutomaticLockInFlight,
              !quality.isUnstable
        else {
            return
        }

        setAutomaticLockInFlight(true)
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.applyLockedCameraControlsToActiveDevice()
            self.setAutomaticLockInFlight(false)
        }
    }

    private func makeCameraFrameQuality(
        for device: AVCaptureDevice?,
        pixelBuffer: CVPixelBuffer,
        timestampSeconds: Double
    ) -> CameraFrameQuality {
        guard let device else {
            return .neutral
        }

        let configuration = currentCameraQualityConfiguration()
        let exposureDurationSeconds = finiteSeconds(from: device.exposureDuration)
        let lensPosition = device.lensPosition.isFinite ? device.lensPosition : nil
        let focusState = updateFocusStabilityState(
            lensPosition: lensPosition,
            timestampSeconds: timestampSeconds,
            configuration: configuration
        )
        let sharpness = FrameSharpnessAnalyzer.varianceOfLaplacian(in: pixelBuffer)
        recordSharpness(sharpness)
        let sharpnessScore = qualityScoreForSharpness(
            sharpness,
            configuration: configuration
        )
        let isSharpnessAcceptable = sharpness.map {
            $0.isFinite && $0 >= configuration.minimumAllowedSharpness
        } ?? true
        let isFocusStable = !device.isAdjustingFocus && !focusState.isSettling
        let focusScore = isFocusStable ? 1.0 : 0.0
        let exposureScore = device.isAdjustingExposure ? 0.50 : 1.0
        let whiteBalanceScore = device.isAdjustingWhiteBalance ? 0.75 : 1.0
        let cameraScore = min(focusScore, min(exposureScore, min(whiteBalanceScore, sharpnessScore)))
        let rotationScore = min(
            isFocusStable ? 1.0 : 0.0,
            min(
                device.isAdjustingExposure ? 0.40 : 1.0,
                min(device.isAdjustingWhiteBalance ? 0.65 : 1.0, sharpnessScore)
            )
        )

        return CameraFrameQuality(
            isAdjustingFocus: device.isAdjustingFocus,
            isAdjustingExposure: device.isAdjustingExposure,
            isAdjustingWhiteBalance: device.isAdjustingWhiteBalance,
            isFocusSettling: focusState.isSettling,
            isFocusStable: isFocusStable,
            lensPosition: lensPosition,
            lastLensPositionChangeAgeSeconds: focusState.lastChangeAgeSeconds,
            sharpness: sharpness,
            isSharpnessAcceptable: isSharpnessAcceptable,
            sharpnessScore: sharpnessScore,
            iso: device.iso.isFinite ? device.iso : nil,
            exposureDurationSeconds: exposureDurationSeconds,
            cameraStabilityScore: cameraScore,
            rotationStabilityScore: rotationScore
        )
    }

    private func makeCameraDebugSnapshot(
        sampleBufferDimensions: CMVideoDimensions? = nil,
        intrinsicMatrix: simd_double3x3? = nil,
        cameraQuality: CameraFrameQuality? = nil
    ) -> CameraDebugSnapshot {
        let state = cameraControlState()

        guard let device = activeDevice else {
            return CameraDebugSnapshot(
                deviceName: nil,
                deviceType: nil,
                uniqueID: nil,
                activeFormatDescription: nil,
                resolutionText: nil,
                fpsText: nil,
                hasIntrinsics: intrinsicMatrix != nil,
                fx: fx(from: intrinsicMatrix),
                fy: fy(from: intrinsicMatrix),
                cx: cx(from: intrinsicMatrix),
                cy: cy(from: intrinsicMatrix),
                lensPosition: nil,
                lastLensPositionChangeAgeSeconds: nil,
                isFocusStable: nil,
                isFocusSettling: nil,
                sharpness: nil,
                averageSharpness: averageSharpness(),
                minimumAllowedSharpness: currentCameraQualityConfiguration().minimumAllowedSharpness,
                minimumPreferredSharpness: currentCameraQualityConfiguration().minimumPreferredSharpness,
                isAdjustingFocus: nil,
                isAdjustingExposure: nil,
                isAdjustingWhiteBalance: nil,
                focusMode: nil,
                exposureMode: nil,
                iso: nil,
                exposureDurationSeconds: nil,
                cameraStabilityScore: cameraQuality?.cameraStabilityScore,
                rotationStabilityScore: cameraQuality?.rotationStabilityScore,
                isCameraLocked: state.cameraControlsLocked,
                automaticLockEnabled: state.automaticLockEnabled,
                videoZoomFactor: nil,
                minimumAvailableVideoZoomFactor: nil,
                maximumAvailableVideoZoomFactor: nil,
                manualFocusEnabled: state.manualFocusEnabled,
                manualLensPosition: state.manualLensPosition,
                isManualFocusSupported: nil,
                lockError: state.lockError
            )
        }

        let quality = cameraQuality ?? .neutral
        let configuration = currentCameraQualityConfiguration()
        let formatDimensions = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        let dimensions = sampleBufferDimensions ?? formatDimensions

        return CameraDebugSnapshot(
            deviceName: device.localizedName,
            deviceType: device.deviceType.rawValue,
            uniqueID: device.uniqueID,
            activeFormatDescription: activeFormatDescription(for: device),
            resolutionText: resolutionText(for: dimensions),
            fpsText: fpsText(for: device),
            hasIntrinsics: intrinsicMatrix != nil,
            fx: fx(from: intrinsicMatrix),
            fy: fy(from: intrinsicMatrix),
            cx: cx(from: intrinsicMatrix),
            cy: cy(from: intrinsicMatrix),
            lensPosition: quality.lensPosition,
            lastLensPositionChangeAgeSeconds: quality.lastLensPositionChangeAgeSeconds,
            isFocusStable: quality.isFocusStable,
            isFocusSettling: quality.isFocusSettling,
            sharpness: quality.sharpness,
            averageSharpness: averageSharpness(),
            minimumAllowedSharpness: configuration.minimumAllowedSharpness,
            minimumPreferredSharpness: configuration.minimumPreferredSharpness,
            isAdjustingFocus: quality.isAdjustingFocus,
            isAdjustingExposure: quality.isAdjustingExposure,
            isAdjustingWhiteBalance: quality.isAdjustingWhiteBalance,
            focusMode: focusModeText(device.focusMode),
            exposureMode: exposureModeText(device.exposureMode),
            iso: quality.iso,
            exposureDurationSeconds: quality.exposureDurationSeconds,
            cameraStabilityScore: quality.cameraStabilityScore,
            rotationStabilityScore: quality.rotationStabilityScore,
            isCameraLocked: state.cameraControlsLocked,
            automaticLockEnabled: state.automaticLockEnabled,
            videoZoomFactor: Double(device.videoZoomFactor),
            minimumAvailableVideoZoomFactor: Double(device.minAvailableVideoZoomFactor),
            maximumAvailableVideoZoomFactor: Double(device.maxAvailableVideoZoomFactor),
            manualFocusEnabled: state.manualFocusEnabled,
            manualLensPosition: state.manualLensPosition,
            isManualFocusSupported: device.isLockingFocusWithCustomLensPositionSupported,
            lockError: state.lockError
        )
    }

    private func cameraControlState() -> (
        automaticLockEnabled: Bool,
        cameraControlsLocked: Bool,
        isAutomaticLockInFlight: Bool,
        lockError: String?,
        manualFocusEnabled: Bool,
        manualLensPosition: Float,
        desiredVideoZoomFactor: CGFloat
    ) {
        cameraControlStateLock.lock()
        defer { cameraControlStateLock.unlock() }

        return (
            automaticFocusExposureLockEnabled,
            cameraControlsLocked,
            isAutomaticLockInFlight,
            lastCameraLockError,
            manualFocusEnabled,
            manualLensPosition,
            desiredVideoZoomFactor
        )
    }

    private func setAutomaticLockEnabled(_ isEnabled: Bool) {
        cameraControlStateLock.lock()
        automaticFocusExposureLockEnabled = isEnabled
        if !isEnabled {
            cameraControlsLocked = false
        }
        cameraControlStateLock.unlock()
    }

    private func setCameraControlsLocked(_ isLocked: Bool, error: String?) {
        cameraControlStateLock.lock()
        cameraControlsLocked = isLocked
        lastCameraLockError = error
        cameraControlStateLock.unlock()
    }

    private func setCameraControlError(_ error: String?) {
        cameraControlStateLock.lock()
        lastCameraLockError = error
        cameraControlStateLock.unlock()
    }

    private func setDesiredVideoZoomFactor(_ zoomFactor: CGFloat) {
        cameraControlStateLock.lock()
        desiredVideoZoomFactor = zoomFactor.isFinite ? max(zoomFactor, 1.0) : 1.0
        cameraControlStateLock.unlock()
    }

    private func currentDesiredVideoZoomFactor() -> CGFloat {
        cameraControlStateLock.lock()
        defer { cameraControlStateLock.unlock() }
        return desiredVideoZoomFactor
    }

    private func setManualFocusState(
        isEnabled: Bool,
        lensPosition: Float
    ) {
        cameraControlStateLock.lock()
        manualFocusEnabled = isEnabled
        manualLensPosition = lensPosition.isFinite
            ? min(max(lensPosition, 0.0), 1.0)
            : manualLensPosition
        cameraControlStateLock.unlock()
    }

    private func setAutomaticLockInFlight(_ isInFlight: Bool) {
        cameraControlStateLock.lock()
        isAutomaticLockInFlight = isInFlight
        cameraControlStateLock.unlock()
    }

    private func setCameraQualityConfiguration(_ configuration: CameraFrameQualityConfiguration) {
        let sanitized = CameraFrameQualityConfiguration(
            lensPositionChangeThreshold: min(
                max(configuration.lensPositionChangeThreshold, 0.001),
                0.10
            ),
            focusSettleTimeSeconds: min(
                max(configuration.focusSettleTimeSeconds, 0.0),
                2.0
            ),
            minimumAllowedSharpness: min(
                max(configuration.minimumAllowedSharpness, 0.0),
                2_000.0
            ),
            minimumPreferredSharpness: min(
                max(configuration.minimumPreferredSharpness, configuration.minimumAllowedSharpness),
                4_000.0
            )
        )

        cameraControlStateLock.lock()
        cameraQualityConfiguration = sanitized
        cameraControlStateLock.unlock()
    }

    private func currentCameraQualityConfiguration() -> CameraFrameQualityConfiguration {
        cameraControlStateLock.lock()
        defer { cameraControlStateLock.unlock() }
        return cameraQualityConfiguration
    }

    private func resetFocusStabilityReference(forceSettle: Bool) {
        cameraControlStateLock.lock()
        previousLensPosition = activeDevice?.lensPosition
        lastLensPositionChangeTimestamp = nil
        forceFocusSettleOnNextFrame = forceSettle
        cameraControlStateLock.unlock()
    }

    private func updateFocusStabilityState(
        lensPosition: Float?,
        timestampSeconds: Double,
        configuration: CameraFrameQualityConfiguration
    ) -> (isSettling: Bool, lastChangeAgeSeconds: Double?) {
        guard timestampSeconds.isFinite else {
            return (false, nil)
        }

        cameraControlStateLock.lock()
        defer { cameraControlStateLock.unlock() }

        if forceFocusSettleOnNextFrame {
            lastLensPositionChangeTimestamp = timestampSeconds
            previousLensPosition = lensPosition
            forceFocusSettleOnNextFrame = false
        } else if let lensPosition, lensPosition.isFinite {
            if let previousLensPosition,
               abs(lensPosition - previousLensPosition) >= configuration.lensPositionChangeThreshold {
                lastLensPositionChangeTimestamp = timestampSeconds
            }

            previousLensPosition = lensPosition
        }

        guard let lastLensPositionChangeTimestamp,
              lastLensPositionChangeTimestamp.isFinite
        else {
            return (false, nil)
        }

        let age = max(timestampSeconds - lastLensPositionChangeTimestamp, 0)
        return (
            age < configuration.focusSettleTimeSeconds,
            age.isFinite ? age : nil
        )
    }

    private func recordSharpness(_ sharpness: Double?) {
        guard let sharpness, sharpness.isFinite else {
            return
        }

        cameraControlStateLock.lock()
        recentSharpnessValues.append(sharpness)
        if recentSharpnessValues.count > 60 {
            recentSharpnessValues.removeFirst(recentSharpnessValues.count - 60)
        }
        cameraControlStateLock.unlock()
    }

    private func averageSharpness() -> Double? {
        cameraControlStateLock.lock()
        defer { cameraControlStateLock.unlock() }

        guard !recentSharpnessValues.isEmpty else {
            return nil
        }

        let sum = recentSharpnessValues.reduce(0, +)
        let average = sum / Double(recentSharpnessValues.count)
        return average.isFinite ? average : nil
    }

    private func qualityScoreForSharpness(
        _ sharpness: Double?,
        configuration: CameraFrameQualityConfiguration
    ) -> Double {
        guard let sharpness, sharpness.isFinite else {
            return 1.0
        }

        if sharpness < configuration.minimumAllowedSharpness {
            return 0.0
        }

        if sharpness >= configuration.minimumPreferredSharpness {
            return 1.0
        }

        let range = max(
            configuration.minimumPreferredSharpness - configuration.minimumAllowedSharpness,
            1.0
        )
        let progress = (sharpness - configuration.minimumAllowedSharpness) / range
        return min(max(0.35 + progress * 0.65, 0.35), 1.0)
    }

    private func finiteSeconds(from time: CMTime) -> Double? {
        let seconds = CMTimeGetSeconds(time)
        return seconds.isFinite && seconds >= 0 ? seconds : nil
    }

    private func resolutionText(for dimensions: CMVideoDimensions) -> String? {
        guard dimensions.width > 0, dimensions.height > 0 else {
            return nil
        }

        return "\(dimensions.width)x\(dimensions.height)"
    }

    private func focusModeText(_ mode: AVCaptureDevice.FocusMode) -> String {
        switch mode {
        case .locked:
            return "locked"
        case .autoFocus:
            return "autoFocus"
        case .continuousAutoFocus:
            return "continuousAutoFocus"
        @unknown default:
            return "unknown"
        }
    }

    private func exposureModeText(_ mode: AVCaptureDevice.ExposureMode) -> String {
        switch mode {
        case .locked:
            return "locked"
        case .autoExpose:
            return "autoExpose"
        case .continuousAutoExposure:
            return "continuousAutoExposure"
        case .custom:
            return "custom"
        @unknown default:
            return "unknown"
        }
    }

    private func fpsText(for device: AVCaptureDevice) -> String? {
        let activeDuration = finiteSeconds(from: device.activeVideoMinFrameDuration)
        if let activeDuration, activeDuration > 0 {
            let fps = 1.0 / activeDuration
            if fps.isFinite {
                return String(format: "%.1f fps", fps)
            }
        }

        guard let range = device.activeFormat.videoSupportedFrameRateRanges.first else {
            return nil
        }

        if range.minFrameRate == range.maxFrameRate {
            return String(format: "%.1f fps", range.maxFrameRate)
        }

        return String(format: "%.1f-%.1f fps", range.minFrameRate, range.maxFrameRate)
    }

    private func activeFormatDescription(for device: AVCaptureDevice) -> String {
        let formatDescription = device.activeFormat.formatDescription
        let dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription)
        let mediaSubType = CMFormatDescriptionGetMediaSubType(formatDescription)

        return "\(dimensions.width)x\(dimensions.height) \(fourCCString(mediaSubType))"
    }

    private func fourCCString(_ value: OSType) -> String {
        let characters: [UnicodeScalar] = [
            UnicodeScalar((value >> 24) & 0xff),
            UnicodeScalar((value >> 16) & 0xff),
            UnicodeScalar((value >> 8) & 0xff),
            UnicodeScalar(value & 0xff)
        ].compactMap { $0 }

        guard characters.count == 4 else {
            return "\(value)"
        }

        return String(characters.map { Character($0) })
    }

    private func fx(from matrix: simd_double3x3?) -> Double? {
        guard let matrix else { return nil }
        let value = matrix.columns.0.x
        return value.isFinite ? value : nil
    }

    private func fy(from matrix: simd_double3x3?) -> Double? {
        guard let matrix else { return nil }
        let value = matrix.columns.1.y
        return value.isFinite ? value : nil
    }

    private func cx(from matrix: simd_double3x3?) -> Double? {
        guard let matrix else { return nil }
        let value = matrix.columns.2.x
        return value.isFinite ? value : nil
    }

    private func cy(from matrix: simd_double3x3?) -> Double? {
        guard let matrix else { return nil }
        let value = matrix.columns.2.y
        return value.isFinite ? value : nil
    }

    private func isTorchSupported(on device: AVCaptureDevice) -> Bool {
        device.hasTorch && device.isTorchModeSupported(.on) && device.isTorchModeSupported(.off)
    }

    private func registerSessionNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSessionDidStartRunning(_:)),
            name: AVCaptureSession.didStartRunningNotification,
            object: session
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSessionInterruptionEnded(_:)),
            name: AVCaptureSession.interruptionEndedNotification,
            object: session
        )
    }

    @objc private func handleSessionDidStartRunning(_ notification: Notification) {
        deliverSessionDidBecomeActive()
    }

    @objc private func handleSessionInterruptionEnded(_ notification: Notification) {
        guard session.isRunning else {
            return
        }

        deliverSessionDidBecomeActive()
    }

    private func deliverSessionDidBecomeActive() {
        if let callbackQueue {
            callbackQueue.async { [weak self] in
                self?.onSessionDidBecomeActive?()
            }
        } else {
            onSessionDidBecomeActive?()
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

        let intrinsicMatrix = extractIntrinsicMatrix(from: sampleBuffer)
        let cameraQuality = makeCameraFrameQuality(
            for: activeDevice,
            pixelBuffer: pixelBuffer,
            timestampSeconds: CMTimeGetSeconds(timestamp)
        )
        let cameraDebugSnapshot = makeCameraDebugSnapshot(
            sampleBufferDimensions: dimensions,
            intrinsicMatrix: intrinsicMatrix,
            cameraQuality: cameraQuality
        )
        scheduleAutomaticCameraLockIfNeeded(quality: cameraQuality)

        let metadata = CameraFrame.Metadata(
            dimensions: dimensions,
            pixelFormat: CVPixelBufferGetPixelFormatType(pixelBuffer),
            cameraPosition: activeDevice?.position ?? .unspecified,
            isMirrored: connection.isVideoMirrored,
            lensPosition: activeDevice?.lensPosition,
            lensAperture: activeDevice?.lensAperture,
            exposureDuration: activeDevice?.exposureDuration,
            iso: activeDevice?.iso,
            intrinsicMatrix: intrinsicMatrix
        )

        return CameraFrame(
            pixelBuffer: pixelBuffer,
            timestamp: timestamp,
            orientation: connection.videoOrientation,
            metadata: metadata,
            cameraQuality: cameraQuality,
            cameraDebugSnapshot: cameraDebugSnapshot
        )
    }

    private func extractIntrinsicMatrix(from sampleBuffer: CMSampleBuffer) -> simd_double3x3? {
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

        return simd_double3x3(columns: (
            SIMD3(
                Double(matrix.columns.0.x),
                Double(matrix.columns.0.y),
                Double(matrix.columns.0.z)
            ),
            SIMD3(
                Double(matrix.columns.1.x),
                Double(matrix.columns.1.y),
                Double(matrix.columns.1.z)
            ),
            SIMD3(
                Double(matrix.columns.2.x),
                Double(matrix.columns.2.y),
                Double(matrix.columns.2.z)
            )
        ))
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
