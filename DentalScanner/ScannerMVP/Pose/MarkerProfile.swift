import Foundation
import simd

enum MarkerProfile: String, CaseIterable, Hashable, Identifiable {
    case singleArucoV1
    case dualArucoV2

    var id: String {
        rawValue
    }

    var debugTitle: String {
        switch self {
        case .singleArucoV1:
            return "single ArUco v1"
        case .dualArucoV2:
            return "dual ArUco v2"
        }
    }
}

enum DualArucoTagRole: Equatable {
    case top
    case bottom

    var debugTitle: String {
        switch self {
        case .top:
            return "top"
        case .bottom:
            return "bottom"
        }
    }
}

enum MarkerPoseSource: Equatable {
    case singleArucoV1
    case dualTag
    case singleFallback(tagId: Int, role: DualArucoTagRole)

    var debugTitle: String {
        switch self {
        case .singleArucoV1:
            return "single-tag"
        case .dualTag:
            return "dual-tag"
        case let .singleFallback(_, role):
            return "\(role.debugTitle) fallback"
        }
    }

    var overlayTitle: String {
        switch self {
        case .singleArucoV1:
            return "single"
        case .dualTag:
            return "dual"
        case let .singleFallback(_, role):
            return "\(role.debugTitle) fallback"
        }
    }

    var qualityWeight: Double {
        switch self {
        case let .singleFallback(_, role):
            switch role {
            case .top:
                return 0.35
            case .bottom:
                return 0.15
            }
        case .singleArucoV1, .dualTag:
            return 1.0
        }
    }
}

struct DualArucoMarkerDefinition: Equatable, Identifiable {
    let physicalMarkerId: Int
    let topTagId: Int
    let bottomTagId: Int
    let topTagSizeMm: Double
    let bottomTagSizeMm: Double
    let verticalGapMm: Double

    var id: Int {
        physicalMarkerId
    }

    var topTagCenterInMarkerCoordinates: SIMD3<Double> {
        SIMD3<Double>(0.0, 0.0, 0.0)
    }

    var bottomTagCenterInMarkerCoordinates: SIMD3<Double> {
        SIMD3<Double>(
            0.0,
            -(topTagSizeMm / 2.0 + verticalGapMm + bottomTagSizeMm / 2.0),
            0.0
        )
    }

    var topObjectPoints: [SIMD3<Double>] {
        Self.squareObjectPoints(
            center: topTagCenterInMarkerCoordinates,
            sizeMillimeters: topTagSizeMm
        )
    }

    var bottomObjectPoints: [SIMD3<Double>] {
        Self.squareObjectPoints(
            center: bottomTagCenterInMarkerCoordinates,
            sizeMillimeters: bottomTagSizeMm
        )
    }

    var dualObjectPoints: [SIMD3<Double>] {
        topObjectPoints + bottomObjectPoints
    }

    func tagRole(for tagId: Int) -> DualArucoTagRole? {
        if tagId == topTagId {
            return .top
        }

        if tagId == bottomTagId {
            return .bottom
        }

        return nil
    }

    func tagId(for role: DualArucoTagRole) -> Int {
        switch role {
        case .top:
            return topTagId
        case .bottom:
            return bottomTagId
        }
    }

    func tagSizeMillimeters(for role: DualArucoTagRole) -> Double {
        switch role {
        case .top:
            return topTagSizeMm
        case .bottom:
            return bottomTagSizeMm
        }
    }

    func tagCenterInMarkerCoordinates(for role: DualArucoTagRole) -> SIMD3<Double> {
        switch role {
        case .top:
            return topTagCenterInMarkerCoordinates
        case .bottom:
            return bottomTagCenterInMarkerCoordinates
        }
    }

    func objectPoints(for role: DualArucoTagRole) -> [SIMD3<Double>] {
        switch role {
        case .top:
            return topObjectPoints
        case .bottom:
            return bottomObjectPoints
        }
    }

    private static func squareObjectPoints(
        center: SIMD3<Double>,
        sizeMillimeters: Double
    ) -> [SIMD3<Double>] {
        let halfSize = sizeMillimeters / 2.0

        return [
            center + SIMD3<Double>(-halfSize, halfSize, 0.0),
            center + SIMD3<Double>(halfSize, halfSize, 0.0),
            center + SIMD3<Double>(halfSize, -halfSize, 0.0),
            center + SIMD3<Double>(-halfSize, -halfSize, 0.0)
        ]
    }
}

enum MarkerConfiguration {
    static let defaultProfile: MarkerProfile = .dualArucoV2

    static let dualMarkers: [DualArucoMarkerDefinition] = [
        DualArucoMarkerDefinition(
            physicalMarkerId: 1,
            topTagId: 0,
            bottomTagId: 1,
            topTagSizeMm: 8.0,
            bottomTagSizeMm: 6.5,
            verticalGapMm: 0.5
        ),
        DualArucoMarkerDefinition(
            physicalMarkerId: 2,
            topTagId: 2,
            bottomTagId: 3,
            topTagSizeMm: 8.0,
            bottomTagSizeMm: 6.5,
            verticalGapMm: 0.5
        ),
        DualArucoMarkerDefinition(
            physicalMarkerId: 3,
            topTagId: 4,
            bottomTagId: 5,
            topTagSizeMm: 8.0,
            bottomTagSizeMm: 6.5,
            verticalGapMm: 0.5
        ),
        DualArucoMarkerDefinition(
            physicalMarkerId: 4,
            topTagId: 6,
            bottomTagId: 7,
            topTagSizeMm: 8.0,
            bottomTagSizeMm: 6.5,
            verticalGapMm: 0.5
        )
    ]
}

struct DualArucoMarkerDebugState: Equatable, Identifiable {
    let physicalMarkerId: Int
    let topTagId: Int
    let bottomTagId: Int
    let topTagRawDetected: Bool
    let bottomTagRawDetected: Bool
    let topTagDetected: Bool
    let bottomTagDetected: Bool
    let topTagRecentlySeen: Bool
    let bottomTagRecentlySeen: Bool
    let topDetectionCount: Int
    let bottomDetectionCount: Int
    let topAcceptedDetectionCount: Int
    let bottomAcceptedDetectionCount: Int
    let topRecentDetectionCount: Int
    let bottomRecentDetectionCount: Int
    let topRecentAcceptedDetectionCount: Int
    let bottomRecentAcceptedDetectionCount: Int
    let topAreaPixels: Double?
    let bottomAreaPixels: Double?
    let topAreaBelowMinimum: Bool
    let bottomAreaBelowMinimum: Bool
    let detectionWarning: String?
    let poseSource: MarkerPoseSource?
    let reprojectionError: Double?
    let usedPointCount: Int?
    let visualMarkerActive: Bool
    let visualModeTitle: String?
    let visualLastSeenAgeSeconds: Double?
    let visualLastDualSeenAgeSeconds: Double?
    let scanDualTagFrameCount: Int
    let scanTopFallbackFrameCount: Int
    let scanBottomFallbackFrameCount: Int
    let scanDualTagPosePercent: Double
    let scanDominantPoseSource: MarkerPoseSource?
    let scanConsistencyWarning: String?
    let scanDualAngularCoveragePercent: Double
    let scanDualTagRejectedFrameCount: Int
    let scanDualTagRejectionReason: String?
    let finalPlanarDistanceMm: Double?
    let finalRefinementObservationCountBeforeFilter: Int
    let finalRefinementUsedObservationCount: Int
    let finalRefinementDiscardedObservationCount: Int
    let finalRefinementOutlierRemovedCount: Int
    let finalRefinementAverageReprojectionError: Double?
    let finalRefinementConfidence: FinalPoseMarkerConfidence
    let finalRefinementConfidenceReason: String?
    let finalRefinementDiscardReason: String?

    var id: Int {
        physicalMarkerId
    }
}
