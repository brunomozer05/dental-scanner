import Foundation

struct ARKitFrameQuality: Equatable {
    let timestamp: TimeInterval?
    let trackingStateText: String
    let isTrackingReliable: Bool
    let hasCameraTransform: Bool
    let hasIntrinsics: Bool
    let cameraMotionSinceLastFrame: Double?
    let intrinsicsChanged: Bool
    let lightEstimateText: String?
    let stabilityScore: Double
    let rotationStabilityScore: Double
    let isRecent: Bool
    let isEnabled: Bool
    let isAvailable: Bool

    static let disabled = ARKitFrameQuality(
        timestamp: nil,
        trackingStateText: "Desligado",
        isTrackingReliable: true,
        hasCameraTransform: false,
        hasIntrinsics: false,
        cameraMotionSinceLastFrame: nil,
        intrinsicsChanged: false,
        lightEstimateText: nil,
        stabilityScore: 1.0,
        rotationStabilityScore: 1.0,
        isRecent: false,
        isEnabled: false,
        isAvailable: true
    )

    static let unavailable = ARKitFrameQuality(
        timestamp: nil,
        trackingStateText: "ARKit indisponivel",
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
        isAvailable: false
    )

    static let waitingForData = ARKitFrameQuality(
        timestamp: nil,
        trackingStateText: "Aguardando ARKit",
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
        isAvailable: true
    )
}
