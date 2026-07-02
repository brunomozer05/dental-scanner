import Foundation

struct MarkerFrameMaskDiagnostics: Codable, Equatable {
    let markerId: Int

    let markerFrameCenterX: Double?
    let markerFrameCenterY: Double?
    let markerFrameNormalizedCenterX: Double?
    let markerFrameNormalizedCenterY: Double?
    let markerFrameMinX: Double?
    let markerFrameMinY: Double?
    let markerFrameMaxX: Double?
    let markerFrameMaxY: Double?

    let markerInsideFrameMask: Bool?
    let markerFrameMaskViolation: String?
    let markerDistanceToFrameMaskEdgePx: Double?
    let markerDistanceToFrameMaskEdgeNormalized: Double?
    let markerNearFrameEdgeWarning: Bool?
}

struct FrameMaskDiagnostics: Codable, Equatable {
    let frameMaskVerticalBorderPercent: Double?
    let frameMaskHorizontalBorderPercent: Double?
    let frameMaskSafeRectMinX: Double?
    let frameMaskSafeRectMinY: Double?
    let frameMaskSafeRectMaxX: Double?
    let frameMaskSafeRectMaxY: Double?

    let visibleMarkersInsideFrameMaskCount: Int
    let visibleMarkersViolatingFrameMaskCount: Int
    let anyMarkerNearFrameEdge: Bool
    let frameMaskQualityState: String
    let frameMaskQualityMessage: String
    let markerDiagnosticsByMarkerId: [Int: MarkerFrameMaskDiagnostics]

    static let empty = FrameMaskDiagnostics(
        frameMaskVerticalBorderPercent: nil,
        frameMaskHorizontalBorderPercent: nil,
        frameMaskSafeRectMinX: nil,
        frameMaskSafeRectMinY: nil,
        frameMaskSafeRectMaxX: nil,
        frameMaskSafeRectMaxY: nil,
        visibleMarkersInsideFrameMaskCount: 0,
        visibleMarkersViolatingFrameMaskCount: 0,
        anyMarkerNearFrameEdge: false,
        frameMaskQualityState: "unknown",
        frameMaskQualityMessage: "Centralize os markers",
        markerDiagnosticsByMarkerId: [:]
    )
}
