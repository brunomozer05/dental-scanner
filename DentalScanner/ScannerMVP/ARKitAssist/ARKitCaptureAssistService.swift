import ARKit
import Foundation
import simd

final class ARKitCaptureAssistService: NSObject {
    struct Configuration {
        let maximumSampleAgeSeconds: TimeInterval
        let preferredMotionMetersPerFrame: Double
        let allowedMotionMetersPerFrame: Double
        let intrinsicsChangeTolerancePixels: Float

        static let scannerDefault = Configuration(
            maximumSampleAgeSeconds: 0.35,
            preferredMotionMetersPerFrame: 0.003,
            allowedMotionMetersPerFrame: 0.030,
            intrinsicsChangeTolerancePixels: 1.0
        )
    }

    private let session = ARSession()
    private let delegateQueue = DispatchQueue(label: "DentalScanner.ARKitAssist")
    private let configuration: Configuration
    private let lock = NSLock()
    private var latestQuality: ARKitFrameQuality = .disabled
    private var isEnabled = false
    private var lastCameraTransform: simd_float4x4?
    private var baselineIntrinsics: simd_float3x3?

    init(configuration: Configuration = .scannerDefault) {
        self.configuration = configuration
        super.init()
        session.delegate = self
        session.delegateQueue = delegateQueue
    }

    func start() {
        guard ARWorldTrackingConfiguration.isSupported else {
            setLatestQuality(.unavailable)
            return
        }

        delegateQueue.async { [weak self] in
            guard let self else { return }

            self.lock.lock()
            let wasEnabled = self.isEnabled
            self.isEnabled = true
            self.lock.unlock()

            if wasEnabled {
                return
            }

            self.lastCameraTransform = nil
            self.baselineIntrinsics = nil
            self.setLatestQuality(.waitingForData)

            let configuration = ARWorldTrackingConfiguration()
            configuration.worldAlignment = .gravity
            configuration.isLightEstimationEnabled = true
            self.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        }
    }

    func stop() {
        delegateQueue.async { [weak self] in
            guard let self else { return }

            self.session.pause()
            self.lastCameraTransform = nil
            self.baselineIntrinsics = nil
            self.lock.lock()
            self.isEnabled = false
            self.lock.unlock()
            self.setLatestQuality(.disabled)
        }
    }

    func currentQuality() -> ARKitFrameQuality {
        lock.lock()
        defer { lock.unlock() }
        return latestQuality
    }

    func quality(near timestamp: TimeInterval) -> ARKitFrameQuality {
        let quality = currentQuality()
        guard quality.isEnabled else {
            return .disabled
        }

        guard quality.isAvailable else {
            return .unavailable
        }

        guard let arKitTimestamp = quality.timestamp,
              timestamp.isFinite,
              arKitTimestamp.isFinite,
              abs(arKitTimestamp - timestamp) <= configuration.maximumSampleAgeSeconds
        else {
            return .waitingForData
        }

        return ARKitFrameQuality(
            timestamp: arKitTimestamp,
            trackingStateText: quality.trackingStateText,
            isTrackingReliable: quality.isTrackingReliable,
            hasCameraTransform: quality.hasCameraTransform,
            hasIntrinsics: quality.hasIntrinsics,
            cameraMotionSinceLastFrame: quality.cameraMotionSinceLastFrame,
            intrinsicsChanged: quality.intrinsicsChanged,
            lightEstimateText: quality.lightEstimateText,
            stabilityScore: quality.stabilityScore,
            rotationStabilityScore: quality.rotationStabilityScore,
            isRecent: true,
            isEnabled: true,
            isAvailable: true
        )
    }

    private func quality(from frame: ARFrame) -> ARKitFrameQuality {
        let trackingState = frame.camera.trackingState
        let trackingText = trackingStateText(trackingState)
        let trackingScore = trackingStabilityScore(trackingState)
        let transform = frame.camera.transform
        let motionMeters = cameraMotionMeters(from: transform)
        let motionScore = motionStabilityScore(motionMeters)
        let intrinsics = frame.camera.intrinsics
        let intrinsicsChanged = updateAndCheckIntrinsicsChanged(intrinsics)
        let intrinsicsScore = intrinsicsChanged ? 0.80 : 1.0
        let stabilityScore = min(trackingScore, min(motionScore, intrinsicsScore))
        let rotationStabilityScore = min(trackingScore, motionScore * motionScore)

        return ARKitFrameQuality(
            timestamp: frame.timestamp,
            trackingStateText: trackingText,
            isTrackingReliable: trackingScore >= 0.999,
            hasCameraTransform: true,
            hasIntrinsics: true,
            cameraMotionSinceLastFrame: motionMeters,
            intrinsicsChanged: intrinsicsChanged,
            lightEstimateText: lightEstimateText(frame.lightEstimate),
            stabilityScore: min(max(stabilityScore, 0.05), 1.0),
            rotationStabilityScore: min(max(rotationStabilityScore, 0.05), 1.0),
            isRecent: true,
            isEnabled: true,
            isAvailable: true
        )
    }

    private func cameraMotionMeters(from transform: simd_float4x4) -> Double? {
        defer {
            lastCameraTransform = transform
        }

        guard let lastCameraTransform else {
            return nil
        }

        let currentTranslation = SIMD3<Float>(
            transform.columns.3.x,
            transform.columns.3.y,
            transform.columns.3.z
        )
        let previousTranslation = SIMD3<Float>(
            lastCameraTransform.columns.3.x,
            lastCameraTransform.columns.3.y,
            lastCameraTransform.columns.3.z
        )
        let distance = Double(simd_distance(currentTranslation, previousTranslation))
        return distance.isFinite ? distance : nil
    }

    private func updateAndCheckIntrinsicsChanged(_ intrinsics: simd_float3x3) -> Bool {
        guard let baselineIntrinsics else {
            baselineIntrinsics = intrinsics
            return false
        }

        return hasIntrinsicValueChanged(baselineIntrinsics.columns.0.x, intrinsics.columns.0.x) ||
            hasIntrinsicValueChanged(baselineIntrinsics.columns.1.y, intrinsics.columns.1.y) ||
            hasIntrinsicValueChanged(baselineIntrinsics.columns.2.x, intrinsics.columns.2.x) ||
            hasIntrinsicValueChanged(baselineIntrinsics.columns.2.y, intrinsics.columns.2.y)
    }

    private func hasIntrinsicValueChanged(_ baseline: Float, _ current: Float) -> Bool {
        baseline.isFinite &&
            current.isFinite &&
            abs(current - baseline) > configuration.intrinsicsChangeTolerancePixels
    }

    private func motionStabilityScore(_ motionMeters: Double?) -> Double {
        guard let motionMeters,
              motionMeters.isFinite
        else {
            return 1.0
        }

        if motionMeters <= configuration.preferredMotionMetersPerFrame {
            return 1.0
        }

        if motionMeters >= configuration.allowedMotionMetersPerFrame {
            return 0.25
        }

        let progress = (motionMeters - configuration.preferredMotionMetersPerFrame) /
            (configuration.allowedMotionMetersPerFrame - configuration.preferredMotionMetersPerFrame)
        return min(max(1.0 - progress * 0.75, 0.25), 1.0)
    }

    private func trackingStateText(_ trackingState: ARCamera.TrackingState) -> String {
        switch trackingState {
        case .normal:
            return "Normal"
        case let .limited(reason):
            return "Limitado: \(limitedTrackingReasonText(reason))"
        case .notAvailable:
            return "Indisponivel"
        }
    }

    private func trackingStabilityScore(_ trackingState: ARCamera.TrackingState) -> Double {
        switch trackingState {
        case .normal:
            return 1.0
        case .limited:
            return 0.55
        case .notAvailable:
            return 0.30
        }
    }

    private func limitedTrackingReasonText(_ reason: ARCamera.TrackingState.Reason) -> String {
        switch reason {
        case .initializing:
            return "inicializando"
        case .excessiveMotion:
            return "movimento"
        case .insufficientFeatures:
            return "poucos detalhes"
        case .relocalizing:
            return "relocalizando"
        @unknown default:
            return "desconhecido"
        }
    }

    private func lightEstimateText(_ lightEstimate: ARLightEstimate?) -> String? {
        guard let lightEstimate else {
            return nil
        }

        let intensity = Double(lightEstimate.ambientIntensity)
        let temperature = Double(lightEstimate.ambientColorTemperature)
        guard intensity.isFinite, temperature.isFinite else {
            return nil
        }

        return String(format: "%.0f lux / %.0fK", intensity, temperature)
    }

    private func setLatestQuality(_ quality: ARKitFrameQuality) {
        lock.lock()
        latestQuality = quality
        lock.unlock()
    }
}

extension ARKitCaptureAssistService: ARSessionDelegate {
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        setLatestQuality(quality(from: frame))
    }

    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        let current = currentQuality()
        setLatestQuality(
            ARKitFrameQuality(
                timestamp: current.timestamp,
                trackingStateText: trackingStateText(camera.trackingState),
                isTrackingReliable: trackingStabilityScore(camera.trackingState) >= 0.999,
                hasCameraTransform: current.hasCameraTransform,
                hasIntrinsics: current.hasIntrinsics,
                cameraMotionSinceLastFrame: current.cameraMotionSinceLastFrame,
                intrinsicsChanged: current.intrinsicsChanged,
                lightEstimateText: current.lightEstimateText,
                stabilityScore: min(current.stabilityScore, trackingStabilityScore(camera.trackingState)),
                rotationStabilityScore: min(
                    current.rotationStabilityScore,
                    trackingStabilityScore(camera.trackingState)
                ),
                isRecent: current.isRecent,
                isEnabled: current.isEnabled,
                isAvailable: current.isAvailable
            )
        )
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        setLatestQuality(
            ARKitFrameQuality(
                timestamp: nil,
                trackingStateText: "Erro: \(error.localizedDescription)",
                isTrackingReliable: true,
                hasCameraTransform: false,
                hasIntrinsics: false,
                cameraMotionSinceLastFrame: nil,
                intrinsicsChanged: false,
                lightEstimateText: nil,
                stabilityScore: 1.0,
                rotationStabilityScore: 1.0,
                isRecent: false,
                isEnabled: true,
                isAvailable: ARWorldTrackingConfiguration.isSupported
            )
        )
    }
}
