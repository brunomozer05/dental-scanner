import CoreGraphics

struct ArUcoDetectionResult: Equatable {
    let markerId: Int
    let corners: [CGPoint]

    var markerAreaPixels: Double {
        guard corners.count >= 3 else {
            return 0.0
        }

        var signedArea = 0.0
        for index in corners.indices {
            let nextIndex = (index + 1) % corners.count
            let corner = corners[index]
            let nextCorner = corners[nextIndex]
            signedArea += Double(corner.x) * Double(nextCorner.y)
            signedArea -= Double(nextCorner.x) * Double(corner.y)
        }

        let area = abs(signedArea) * 0.5
        return area.isFinite ? area : 0.0
    }
}
