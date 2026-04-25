import CoreGraphics

struct ArUcoDetectionResult: Equatable {
    let markerId: Int
    let corners: [CGPoint]
}
