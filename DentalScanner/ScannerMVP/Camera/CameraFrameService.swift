import AVFoundation
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

    private func makeCameraFrameQuality(for device: AVCaptureDevice?) -> CameraFrameQuality {
        guard let device else {
            return .neutral
        }

        let exposureDurationSeconds = finiteSeconds(from: device.exposureDuration)
        let focusScore = device.isAdjustingFocus ? 0.35 : 1.0
        let exposureScore = device.isAdjustingExposure ? 0.50 : 1.0
        let whiteBalanceScore = device.isAdjustingWhiteBalance ? 0.75 : 1.0
        let cameraScore = min(focusScore, min(exposureScore, whiteBalanceScore))
        let rotationScore = min(
            device.isAdjustingFocus ? 0.25 : 1.0,
            min(
                device.isAdjustingExposure ? 0.40 : 1.0,
                device.isAdjustingWhiteBalance ? 0.65 : 1.0
            )
        )

        return CameraFrameQuality(
            isAdjustingFocus: device.isAdjustingFocus,
            isAdjustingExposure: device.isAdjustingExposure,
            isAdjustingWhiteBalance: device.isAdjustingWhiteBalance,
            lensPosition: device.lensPosition.isFinite ? device.lensPosition : nil,
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
                isAdjustingFocus: nil,
                isAdjustingExposure: nil,
                isAdjustingWhiteBalance: nil,
                iso: nil,
                exposureDurationSeconds: nil,
                cameraStabilityScore: cameraQuality?.cameraStabilityScore,
                rotationStabilityScore: cameraQuality?.rotationStabilityScore,
                isCameraLocked: state.cameraControlsLocked,
                automaticLockEnabled: state.automaticLockEnabled,
                lockError: state.lockError
            )
        }

        let quality = cameraQuality ?? makeCameraFrameQuality(for: device)
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
            isAdjustingFocus: quality.isAdjustingFocus,
            isAdjustingExposure: quality.isAdjustingExposure,
            isAdjustingWhiteBalance: quality.isAdjustingWhiteBalance,
            iso: quality.iso,
            exposureDurationSeconds: quality.exposureDurationSeconds,
            cameraStabilityScore: quality.cameraStabilityScore,
            rotationStabilityScore: quality.rotationStabilityScore,
            isCameraLocked: state.cameraControlsLocked,
            automaticLockEnabled: state.automaticLockEnabled,
            lockError: state.lockError
        )
    }

    private func cameraControlState() -> (
        automaticLockEnabled: Bool,
        cameraControlsLocked: Bool,
        isAutomaticLockInFlight: Bool,
        lockError: String?
    ) {
        cameraControlStateLock.lock()
        defer { cameraControlStateLock.unlock() }

        return (
            automaticFocusExposureLockEnabled,
            cameraControlsLocked,
            isAutomaticLockInFlight,
            lastCameraLockError
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

    private func setAutomaticLockInFlight(_ isInFlight: Bool) {
        cameraControlStateLock.lock()
        isAutomaticLockInFlight = isInFlight
        cameraControlStateLock.unlock()
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
        let cameraQuality = makeCameraFrameQuality(for: activeDevice)
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
