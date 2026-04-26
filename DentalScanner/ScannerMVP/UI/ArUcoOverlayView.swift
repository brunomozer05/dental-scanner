import SwiftUI

struct ArUcoOverlayView: View {
    let detections: [ArUcoDetectionResult]
    let frameResolution: ScannerViewModel.FrameResolution?
    let orientation: CameraPreviewOrientation

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(Array(projectedMarkers(in: proxy.size).enumerated()), id: \.offset) { item in
                    markerOverlay(marker: item.element, previewSize: proxy.size)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .allowsHitTesting(false)
    }

    private func projectedMarkers(in previewSize: CGSize) -> [ProjectedMarker] {
        guard let project = makeAspectFillProjection(previewSize: previewSize) else {
            return []
        }

        return detections.compactMap { detection in
            guard detection.corners.count == 4 else {
                return nil
            }

            return ProjectedMarker(
                markerId: detection.markerId,
                corners: detection.corners.map(project)
            )
        }
    }

    private func markerOverlay(marker: ProjectedMarker, previewSize: CGSize) -> some View {
        ZStack {
            markerPath(corners: marker.corners)
                .stroke(.green, style: StrokeStyle(lineWidth: 3, lineJoin: .round))

            ForEach(Array(marker.corners.enumerated()), id: \.offset) { cornerItem in
                Circle()
                    .fill(.yellow)
                    .frame(width: 8, height: 8)
                    .overlay {
                        Circle()
                            .stroke(.black.opacity(0.8), lineWidth: 1)
                    }
                    .position(cornerItem.element)
            }

            Text("ID \(marker.markerId)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.black)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.yellow.opacity(0.9))
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .position(labelPosition(for: marker.corners, in: previewSize))
        }
        .frame(width: previewSize.width, height: previewSize.height)
    }

    private func makeAspectFillProjection(previewSize: CGSize) -> ((CGPoint) -> CGPoint)? {
        guard let frameResolution,
              frameResolution.width > 0,
              frameResolution.height > 0,
              previewSize.width > 0,
              previewSize.height > 0
        else {
            return nil
        }

        let rawFrameWidth = CGFloat(frameResolution.width)
        let rawFrameHeight = CGFloat(frameResolution.height)
        let projectionFrameSize = makeProjectionFrameSize(
            rawFrameWidth: rawFrameWidth,
            rawFrameHeight: rawFrameHeight
        )
        let scale = max(
            previewSize.width / projectionFrameSize.width,
            previewSize.height / projectionFrameSize.height
        )
        let scaledWidth = projectionFrameSize.width * scale
        let scaledHeight = projectionFrameSize.height * scale
        let xOffset = (previewSize.width - scaledWidth) / 2
        let yOffset = (previewSize.height - scaledHeight) / 2

        return { point -> CGPoint in
            let projectedPoint = orientedPoint(
                point,
                rawFrameWidth: rawFrameWidth,
                rawFrameHeight: rawFrameHeight
            )

            return CGPoint(
                x: projectedPoint.x * scale + xOffset,
                y: projectedPoint.y * scale + yOffset
            )
        }
    }

    private func makeProjectionFrameSize(rawFrameWidth: CGFloat, rawFrameHeight: CGFloat) -> CGSize {
        if shouldRotateRawFrame(rawFrameWidth: rawFrameWidth, rawFrameHeight: rawFrameHeight) {
            return CGSize(width: rawFrameHeight, height: rawFrameWidth)
        }

        return CGSize(width: rawFrameWidth, height: rawFrameHeight)
    }

    private func orientedPoint(
        _ point: CGPoint,
        rawFrameWidth: CGFloat,
        rawFrameHeight: CGFloat
    ) -> CGPoint {
        guard shouldRotateRawFrame(rawFrameWidth: rawFrameWidth, rawFrameHeight: rawFrameHeight) else {
            return point
        }

        switch orientation {
        case .landscapeLeft:
            return CGPoint(x: point.y, y: rawFrameWidth - point.x)
        case .landscapeRight:
            return CGPoint(x: rawFrameHeight - point.y, y: point.x)
        case .portrait:
            return point
        case .portraitUpsideDown:
            return CGPoint(x: rawFrameWidth - point.x, y: rawFrameHeight - point.y)
        }
    }

    private func shouldRotateRawFrame(rawFrameWidth: CGFloat, rawFrameHeight: CGFloat) -> Bool {
        switch orientation {
        case .landscapeLeft, .landscapeRight:
            return rawFrameHeight > rawFrameWidth
        case .portrait, .portraitUpsideDown:
            return rawFrameWidth > rawFrameHeight
        }
    }

    private func markerPath(corners: [CGPoint]) -> Path {
        var path = Path()
        guard let firstCorner = corners.first else {
            return path
        }

        path.move(to: firstCorner)
        for corner in corners.dropFirst() {
            path.addLine(to: corner)
        }
        path.closeSubpath()

        return path
    }

    private func labelPosition(for corners: [CGPoint], in previewSize: CGSize) -> CGPoint {
        let minX = corners.map(\.x).min() ?? 0
        let minY = corners.map(\.y).min() ?? 0
        let labelX = min(max(minX, 28), max(previewSize.width - 28, 28))
        let labelY = min(max(minY - 14, 12), max(previewSize.height - 12, 12))

        return CGPoint(x: labelX, y: labelY)
    }

    private struct ProjectedMarker {
        let markerId: Int
        let corners: [CGPoint]
    }
}
