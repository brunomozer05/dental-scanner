import CoreGraphics

struct MarkerOverlayResult: Equatable, Identifiable {
    let markerId: Int
    let corners: [CGPoint]
    let markerProfile: MarkerProfile
    let poseSource: MarkerPoseSource?

    var id: Int {
        markerId
    }

    var displayTitle: String {
        switch markerProfile {
        case .singleArucoV1:
            return "ID \(markerId)"
        case .dualArucoV2:
            return "Marker \(markerId)"
        }
    }

    var modeTitle: String? {
        guard markerProfile == .dualArucoV2 else {
            return nil
        }

        return poseSource?.overlayTitle
    }
}
