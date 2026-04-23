import Foundation
import simd

public final class PoseEstimator {
    public init() {}

    public func estimateCameraPose(from markers: [DetectedMarker]) -> PoseTransform? {
        let poses = markers.compactMap(\.pose)
        guard !poses.isEmpty else {
            return nil
        }

        let count = Float(poses.count)
        let rotation = poses.reduce(SIMD3<Float>.zero) { $0 + $1.rotationEuler } / count
        let translation = poses.reduce(SIMD3<Float>.zero) { $0 + $1.translation } / count

        return PoseTransform(rotationEuler: rotation, translation: translation)
    }

    public func poseJitterScore(from history: [PoseTransform]) -> Double {
        guard history.count > 1 else {
            return 0
        }

        let mean = history.reduce(SIMD3<Float>.zero) { $0 + $1.translation } / Float(history.count)
        let variance = history.reduce(0.0) { partialResult, pose in
            let distance = simd_length(pose.translation - mean)
            return partialResult + Double(distance * distance)
        } / Double(history.count)

        return sqrt(variance)
    }

    public func relativeScaleConsistency(for markers: [DetectedMarker]) -> Double {
        let distances = markers.compactMap { marker -> Double? in
            guard let pose = marker.pose else {
                return nil
            }

            return Double(simd_length(pose.translation))
        }

        guard distances.count > 1 else {
            return 0
        }

        let mean = distances.reduce(0, +) / Double(distances.count)
        let variance = distances.reduce(0) { $0 + pow($1 - mean, 2) } / Double(distances.count)
        return mean == 0 ? 0 : sqrt(variance) / mean
    }
}

