import Foundation
import simd

struct SmoothedPose {
    var position: SIMD3<Double>
    var rotation: simd_quatd
}

final class PoseSmoother {
    private var smoothedPosesByMarkerId: [Int: SmoothedPose] = [:]

    func reset() {
        smoothedPosesByMarkerId.removeAll()
    }

    func seed(with pose: PoseResult) {
        guard let quaternion = PoseMath.quaternion(fromRotationMatrix: pose.rotationMatrix) else {
            smoothedPosesByMarkerId.removeValue(forKey: pose.markerId)
            return
        }

        smoothedPosesByMarkerId[pose.markerId] = SmoothedPose(
            position: pose.translationVector,
            rotation: quaternion
        )
    }

    func smooth(
        previous: PoseResult,
        current: PoseResult,
        alpha: Double
    ) -> PoseResult {
        let clampedAlpha = min(max(alpha, 0.0), 1.0)
        let retained = 1.0 - clampedAlpha

        if smoothedPosesByMarkerId[current.markerId] == nil {
            seed(with: previous)
        }

        guard let previousSmoothedPose = smoothedPosesByMarkerId[current.markerId],
              let currentQuaternion = PoseMath.quaternion(fromRotationMatrix: current.rotationMatrix)
        else {
            seed(with: current)
            return current
        }

        let smoothedPosition = previousSmoothedPose.position * retained +
            current.translationVector * clampedAlpha
        let smoothedRotation = simd_slerp(
            previousSmoothedPose.rotation,
            currentQuaternion,
            clampedAlpha
        )
        let smoothedRotationMatrix = simd_double3x3(smoothedRotation)

        guard PoseMath.isFinite(smoothedPosition),
              PoseMath.isFinite(smoothedRotationMatrix),
              let smoothedRotationVector = PoseMath.rotationVector(from: smoothedRotationMatrix)
        else {
            seed(with: current)
            return current
        }

        smoothedPosesByMarkerId[current.markerId] = SmoothedPose(
            position: smoothedPosition,
            rotation: smoothedRotation
        )

        return PoseResult(
            markerId: current.markerId,
            rotationVector: smoothedRotationVector,
            rotationMatrix: smoothedRotationMatrix,
            translationVector: smoothedPosition,
            distanceMm: simd_length(smoothedPosition),
            reprojectionError: previous.reprojectionError * retained + current.reprojectionError * clampedAlpha,
            markerAreaPixels: previous.markerAreaPixels * retained + current.markerAreaPixels * clampedAlpha
        )
    }
}
