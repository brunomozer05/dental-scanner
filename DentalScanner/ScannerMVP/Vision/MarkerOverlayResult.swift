import CoreGraphics

struct MarkerOverlayResult: Equatable, Identifiable {
    let markerId: Int
    let corners: [CGPoint]
    let markerProfile: MarkerProfile
    let poseSource: MarkerPoseSource?
    let topTagRecentlySeen: Bool
    let bottomTagRecentlySeen: Bool
    let visualModeTitle: String?
    let visualConfidence: Double
    let isVisualPersistence: Bool

    init(
        markerId: Int,
        corners: [CGPoint],
        markerProfile: MarkerProfile,
        poseSource: MarkerPoseSource?,
        topTagRecentlySeen: Bool = false,
        bottomTagRecentlySeen: Bool = false,
        visualModeTitle: String? = nil,
        visualConfidence: Double = 1.0,
        isVisualPersistence: Bool = false
    ) {
        self.markerId = markerId
        self.corners = corners
        self.markerProfile = markerProfile
        self.poseSource = poseSource
        self.topTagRecentlySeen = topTagRecentlySeen
        self.bottomTagRecentlySeen = bottomTagRecentlySeen
        self.visualModeTitle = visualModeTitle
        self.visualConfidence = visualConfidence
        self.isVisualPersistence = isVisualPersistence
    }

    var id: Int {
        markerId
    }

    var displayTitle: String {
        switch markerProfile {
        case .singleArucoV1:
            return "ID \(markerId)"
        case .dualArucoV2:
            return "M\(markerId)"
        }
    }

    var modeTitle: String? {
        guard markerProfile == .dualArucoV2 else {
            return nil
        }

        if let visualModeTitle {
            return visualModeTitle
        }

        guard let poseSource else {
            return bottomTagRecentlySeen ? "bottom recente" : nil
        }

        switch poseSource {
        case let .singleFallback(_, role) where role == .top && bottomTagRecentlySeen:
            return "Top + bottom recente"
        case .dualTag:
            return "Dual"
        case let .singleFallback(_, role):
            switch role {
            case .top:
                return "Top"
            case .bottom:
                return "Bottom"
            }
        default:
            return poseSource.overlayTitle
        }
    }

    func withVisualState(
        modeTitle: String?,
        confidence: Double,
        isPersistence: Bool
    ) -> MarkerOverlayResult {
        MarkerOverlayResult(
            markerId: markerId,
            corners: corners,
            markerProfile: markerProfile,
            poseSource: poseSource,
            topTagRecentlySeen: topTagRecentlySeen,
            bottomTagRecentlySeen: bottomTagRecentlySeen,
            visualModeTitle: modeTitle,
            visualConfidence: confidence,
            isVisualPersistence: isPersistence
        )
    }
}
