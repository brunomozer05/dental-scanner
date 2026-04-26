import Foundation
import simd

struct ImplantPose {
    let markerId: Int
    let rotationMatrix: simd_double3x3
    let translationVector: SIMD3<Double>
    let distanceMm: Double
    let sourceTagPose: PoseResult
}
