import Foundation

public struct BundleAdjustmentConfiguration: Equatable {
    public var maxIterations: Int
    public var minimumAnchorCount: Int
    public var maximumScaleInconsistency: Double

    public init(
        maxIterations: Int = 50,
        minimumAnchorCount: Int = 4,
        maximumScaleInconsistency: Double = 0.15
    ) {
        self.maxIterations = maxIterations
        self.minimumAnchorCount = minimumAnchorCount
        self.maximumScaleInconsistency = maximumScaleInconsistency
    }
}

public final class BundleAdjustment {
    public let configuration: BundleAdjustmentConfiguration
    private let poseEstimator = PoseEstimator()

    public init(configuration: BundleAdjustmentConfiguration = BundleAdjustmentConfiguration()) {
        self.configuration = configuration
    }

    public func refine(_ reconstruction: ReconstructionState, anchors: [DetectedMarker]) -> ReconstructionState {
        guard anchors.count >= configuration.minimumAnchorCount else {
            return reconstruction
        }

        let inconsistency = poseEstimator.relativeScaleConsistency(for: anchors)
        guard inconsistency <= configuration.maximumScaleInconsistency else {
            return reconstruction
        }

        var refined = reconstruction
        refined.anchorMarkers = anchors
        refined.scaleAnchored = true
        refined.scaleMillimetersPerUnit = 1.0
        refined.densePoints = refined.densePoints.map {
            DensePoint(position: $0.position, normal: $0.normal, confidence: min($0.confidence + 0.03, 1.0))
        }
        return refined
    }
}

