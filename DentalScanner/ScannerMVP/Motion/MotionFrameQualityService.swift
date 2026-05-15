import CoreMotion
import Foundation

struct MotionFrameQuality: Equatable {
    let timestamp: TimeInterval?
    let angularVelocityRadPerSec: Double
    let accelerationMagnitude: Double
    let isStable: Bool
    let stabilityScore: Double
    let rotationStabilityScore: Double
    let isRecent: Bool

    static let neutral = MotionFrameQuality(
        timestamp: nil,
        angularVelocityRadPerSec: 0.0,
        accelerationMagnitude: 0.0,
        isStable: true,
        stabilityScore: 1.0,
        rotationStabilityScore: 1.0,
        isRecent: false
    )
}

final class MotionFrameQualityService {
    struct Configuration {
        let updateIntervalSeconds: TimeInterval
        let maximumMotionSampleAgeSeconds: TimeInterval
        let maximumPreferredAngularVelocity: Double
        let maximumAllowedAngularVelocity: Double
        let maximumPreferredAcceleration: Double
        let maximumAllowedAcceleration: Double

        static let scannerDefault = Configuration(
            updateIntervalSeconds: 1.0 / 60.0,
            maximumMotionSampleAgeSeconds: 0.25,
            maximumPreferredAngularVelocity: 0.15,
            maximumAllowedAngularVelocity: 0.45,
            maximumPreferredAcceleration: 0.03,
            maximumAllowedAcceleration: 0.12
        )
    }

    private let manager: CMMotionManager
    private let configuration: Configuration
    private let queue = OperationQueue()
    private let lock = NSLock()
    private var latestQuality: MotionFrameQuality = .neutral

    init(
        manager: CMMotionManager = CMMotionManager(),
        configuration: Configuration = .scannerDefault
    ) {
        self.manager = manager
        self.configuration = configuration
        queue.name = "DentalScanner.MotionFrameQuality"
        queue.qualityOfService = .userInteractive
    }

    func start() {
        guard !manager.isDeviceMotionActive else {
            return
        }

        guard manager.isDeviceMotionAvailable else {
            setLatestQuality(.neutral)
            return
        }

        manager.deviceMotionUpdateInterval = configuration.updateIntervalSeconds
        manager.startDeviceMotionUpdates(to: queue) { [weak self] motion, _ in
            guard let self, let motion else {
                return
            }

            self.setLatestQuality(self.quality(from: motion))
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        setLatestQuality(.neutral)
    }

    func quality(near timestamp: TimeInterval) -> MotionFrameQuality {
        let quality = currentQuality()
        guard let motionTimestamp = quality.timestamp,
              timestamp.isFinite,
              motionTimestamp.isFinite,
              abs(motionTimestamp - timestamp) <= configuration.maximumMotionSampleAgeSeconds
        else {
            return .neutral
        }

        return MotionFrameQuality(
            timestamp: motionTimestamp,
            angularVelocityRadPerSec: quality.angularVelocityRadPerSec,
            accelerationMagnitude: quality.accelerationMagnitude,
            isStable: quality.isStable,
            stabilityScore: quality.stabilityScore,
            rotationStabilityScore: quality.rotationStabilityScore,
            isRecent: true
        )
    }

    private func quality(from motion: CMDeviceMotion) -> MotionFrameQuality {
        let angularVelocity = magnitude(
            x: motion.rotationRate.x,
            y: motion.rotationRate.y,
            z: motion.rotationRate.z
        )
        let acceleration = magnitude(
            x: motion.userAcceleration.x,
            y: motion.userAcceleration.y,
            z: motion.userAcceleration.z
        )
        let angularScore = score(
            value: angularVelocity,
            preferred: configuration.maximumPreferredAngularVelocity,
            allowed: configuration.maximumAllowedAngularVelocity
        )
        let accelerationScore = score(
            value: acceleration,
            preferred: configuration.maximumPreferredAcceleration,
            allowed: configuration.maximumAllowedAcceleration
        )
        let stabilityScore = min(angularScore, accelerationScore)
        let rotationStabilityScore = angularScore * angularScore

        return MotionFrameQuality(
            timestamp: motion.timestamp,
            angularVelocityRadPerSec: angularVelocity,
            accelerationMagnitude: acceleration,
            isStable: angularVelocity <= configuration.maximumPreferredAngularVelocity &&
                acceleration <= configuration.maximumPreferredAcceleration,
            stabilityScore: stabilityScore,
            rotationStabilityScore: min(max(rotationStabilityScore, 0.0), 1.0),
            isRecent: true
        )
    }

    private func score(value: Double, preferred: Double, allowed: Double) -> Double {
        guard value.isFinite, preferred.isFinite, allowed.isFinite, allowed > preferred else {
            return 1.0
        }

        if value <= preferred {
            return 1.0
        }

        if value >= allowed {
            return 0.05
        }

        let progress = (value - preferred) / (allowed - preferred)
        return min(max(1.0 - progress * 0.95, 0.05), 1.0)
    }

    private func magnitude(x: Double, y: Double, z: Double) -> Double {
        let value = sqrt(x * x + y * y + z * z)
        return value.isFinite ? value : 0.0
    }

    private func currentQuality() -> MotionFrameQuality {
        lock.lock()
        defer { lock.unlock() }
        return latestQuality
    }

    private func setLatestQuality(_ quality: MotionFrameQuality) {
        lock.lock()
        latestQuality = quality
        lock.unlock()
    }
}
