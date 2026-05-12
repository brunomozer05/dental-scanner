import Foundation
import simd

struct PoseResult: Equatable {
    let markerId: Int
    let markerProfile: MarkerProfile
    let poseSource: MarkerPoseSource
    let rotationVector: SIMD3<Double>
    let rotationMatrix: simd_double3x3
    let translationVector: SIMD3<Double>
    let distanceMm: Double
    let reprojectionError: Double
    let markerAreaPixels: Double
    let usedPointCount: Int
    let detectedTopTagId: Int?
    let detectedBottomTagId: Int?

    init(
        markerId: Int,
        markerProfile: MarkerProfile = .singleArucoV1,
        poseSource: MarkerPoseSource = .singleArucoV1,
        rotationVector: SIMD3<Double>,
        rotationMatrix: simd_double3x3? = nil,
        translationVector: SIMD3<Double>,
        distanceMm: Double,
        reprojectionError: Double,
        markerAreaPixels: Double = 0.0,
        usedPointCount: Int = 4,
        detectedTopTagId: Int? = nil,
        detectedBottomTagId: Int? = nil
    ) {
        self.markerId = markerId
        self.markerProfile = markerProfile
        self.poseSource = poseSource
        self.rotationVector = rotationVector
        self.rotationMatrix = rotationMatrix ?? PoseMath.rotationMatrix(fromRodrigues: rotationVector)
        self.translationVector = translationVector
        self.distanceMm = distanceMm
        self.reprojectionError = reprojectionError
        self.markerAreaPixels = markerAreaPixels
        self.usedPointCount = usedPointCount
        self.detectedTopTagId = detectedTopTagId
        self.detectedBottomTagId = detectedBottomTagId
    }

    static func == (lhs: PoseResult, rhs: PoseResult) -> Bool {
        lhs.markerId == rhs.markerId &&
            lhs.markerProfile == rhs.markerProfile &&
            lhs.poseSource == rhs.poseSource &&
            lhs.rotationVector == rhs.rotationVector &&
            matrixEquals(lhs.rotationMatrix, rhs.rotationMatrix) &&
            lhs.translationVector == rhs.translationVector &&
            lhs.distanceMm == rhs.distanceMm &&
            lhs.reprojectionError == rhs.reprojectionError &&
            lhs.markerAreaPixels == rhs.markerAreaPixels &&
            lhs.usedPointCount == rhs.usedPointCount &&
            lhs.detectedTopTagId == rhs.detectedTopTagId &&
            lhs.detectedBottomTagId == rhs.detectedBottomTagId
    }

    private static func matrixEquals(
        _ lhs: simd_double3x3,
        _ rhs: simd_double3x3
    ) -> Bool {
        lhs.columns.0 == rhs.columns.0 &&
            lhs.columns.1 == rhs.columns.1 &&
            lhs.columns.2 == rhs.columns.2
    }
}
