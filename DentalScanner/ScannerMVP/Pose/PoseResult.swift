import Foundation
import simd

struct PoseResult: Equatable {
    let markerId: Int
    let rotationVector: SIMD3<Double>
    let translationVector: SIMD3<Double>
    let distanceMm: Double
    let reprojectionError: Double
}
