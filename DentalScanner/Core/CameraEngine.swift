import AVFoundation
import CoreMedia
import CoreVideo
import Foundation

public struct ManualCaptureSettings: Equatable {
    public var captureFrameRate: Int32
    public var lensPosition: Float?
    public var exposureDurationSeconds: Double?
    public var iso: Float?

    public init(
        captureFrameRate: Int32 = 3,
        lensPosition: Float? = nil,
        exposureDurationSeconds: Double? = nil,
        iso: Float? = nil
    ) {
        self.captureFrameRate = captureFrameRate
        self.lensPosition = lensPosition
        self.exposureDurationSeconds = exposureDurationSeconds
        self.iso = iso
    }
}

public enum CameraEngineError: Error {
    case cameraUnavailable
    case cannotAddInput
    case cannotAddOutput
}

public final class CameraEngine: NSObject {
    public let session = AVCaptureSession()
    public let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "com.dentalscanner.camera.session")

    public override init() {
        super.init()
    }

    public func configureForHighPrecisionCapture(
        delegate: AVCaptureVideoDataOutputSampleBufferDelegate? = nil,
        queue: DispatchQueue? = nil,
        settings: ManualCaptureSettings = ManualCaptureSettings()
    ) throws {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw CameraEngineError.cameraUnavailable
        }

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = bestPreset(for: session)

        if session.inputs.isEmpty {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else {
                throw CameraEngineError.cannotAddInput
            }
            session.addInput(input)
        }

        if videoOutput.connections.isEmpty {
            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
            ]
            videoOutput.alwaysDiscardsLateVideoFrames = true

            if let delegate, let queue {
                videoOutput.setSampleBufferDelegate(delegate, queue: queue)
            }

            guard session.canAddOutput(videoOutput) else {
                throw CameraEngineError.cannotAddOutput
            }
            session.addOutput(videoOutput)
        }

        try applyManualSettings(settings, to: device)
    }

    public func startRunning() {
        sessionQueue.async {
            guard !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    public func stopRunning() {
        sessionQueue.async {
            guard self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    public func applyManualSettings(_ settings: ManualCaptureSettings) throws {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw CameraEngineError.cameraUnavailable
        }

        try applyManualSettings(settings, to: device)
    }

    private func applyManualSettings(_ settings: ManualCaptureSettings, to device: AVCaptureDevice) throws {
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }

        let frameDuration = CMTime(value: 1, timescale: max(1, settings.captureFrameRate))
        device.activeVideoMinFrameDuration = frameDuration
        device.activeVideoMaxFrameDuration = frameDuration

        if let lensPosition = settings.lensPosition, device.isLockingFocusWithCustomLensPositionSupported {
            device.setFocusModeLocked(lensPosition: min(max(lensPosition, 0), 1), completionHandler: nil)
        } else if device.isFocusModeSupported(.locked) {
            device.focusMode = .locked
        }

        if let exposureDurationSeconds = settings.exposureDurationSeconds, let iso = settings.iso {
            let clampedISO = min(max(iso, device.activeFormat.minISO), device.activeFormat.maxISO)
            let duration = CMTime(seconds: exposureDurationSeconds, preferredTimescale: 1_000_000_000)
            device.setExposureModeCustom(duration: duration, iso: clampedISO, completionHandler: nil)
        } else if device.isExposureModeSupported(.locked) {
            device.exposureMode = .locked
        }

        if device.isLockingWhiteBalanceWithCustomDeviceGainsSupported {
            let gains = clampedGains(device.deviceWhiteBalanceGains, for: device)
            device.setWhiteBalanceModeLocked(with: gains, completionHandler: nil)
        }
    }

    private func bestPreset(for session: AVCaptureSession) -> AVCaptureSession.Preset {
        if session.canSetSessionPreset(.hd4K3840x2160) {
            return .hd4K3840x2160
        }

        if session.canSetSessionPreset(.high) {
            return .high
        }

        return .photo
    }

    private func clampedGains(
        _ gains: AVCaptureDevice.WhiteBalanceGains,
        for device: AVCaptureDevice
    ) -> AVCaptureDevice.WhiteBalanceGains {
        AVCaptureDevice.WhiteBalanceGains(
            redGain: min(max(1.0, gains.redGain), device.maxWhiteBalanceGain),
            greenGain: min(max(1.0, gains.greenGain), device.maxWhiteBalanceGain),
            blueGain: min(max(1.0, gains.blueGain), device.maxWhiteBalanceGain)
        )
    }
}

