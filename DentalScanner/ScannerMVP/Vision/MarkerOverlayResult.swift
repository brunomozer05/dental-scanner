import CoreGraphics

struct MarkerOverlayResult: Equatable, Identifiable {
    let markerId: Int
    let corners: [CGPoint]
    let markerProfile: MarkerProfile
    let poseSource: MarkerPoseSource?
    let topTagRecentlySeen: Bool
    let bottomTagRecentlySeen: Bool

    init(
        markerId: Int,
        corners: [CGPoint],
        markerProfile: MarkerProfile,
        poseSource: MarkerPoseSource?,
        topTagRecentlySeen: Bool = false,
        bottomTagRecentlySeen: Bool = false
    ) {
        self.markerId = markerId
        self.corners = corners
        self.markerProfile = markerProfile
        self.poseSource = poseSource
        self.topTagRecentlySeen = topTagRecentlySeen
        self.bottomTagRecentlySeen = bottomTagRecentlySeen
    }

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

        guard let poseSource else {
            return bottomTagRecentlySeen ? "bottom recente" : nil
        }

        switch poseSource {
        case let .singleFallback(_, role) where role == .top && bottomTagRecentlySeen:
            return "\(poseSource.overlayTitle) + bottom recente"
        default:
            return poseSource.overlayTitle
        }
    }
}
