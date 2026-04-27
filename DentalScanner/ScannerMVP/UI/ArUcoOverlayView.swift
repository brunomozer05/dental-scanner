import Foundation
import SwiftUI

struct ArUcoOverlayView: View {
    let detections: [ArUcoDetectionResult]
    let frameResolution: ScannerViewModel.FrameResolution?
    let orientation: CameraPreviewOrientation
    let tagCoverages: [Int: ScannerViewModel.ScanTagCoverage]

    var body: some View {
        GeometryReader { proxy in
            let markers = projectedMarkers(in: proxy.size)

            ZStack {
                ForEach(Array(markers.enumerated()), id: \.offset) { item in
                    markerOverlay(marker: item.element, previewSize: proxy.size)
                }

                ForEach(Array(markers.enumerated()), id: \.offset) { item in
                    let marker = item.element
                    let progress = tagCoverages[marker.markerId]?.progress ?? 0

                    TagProgressBubble(progress: progress)
                        .position(bubblePosition(for: marker, in: proxy.size))
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

    private func bubblePosition(for marker: ProjectedMarker, in previewSize: CGSize) -> CGPoint {
        let center = markerCenter(for: marker.corners)
        let bubbleRadius: CGFloat = 23
        let verticalOffset: CGFloat = 44
        let x = min(max(center.x, bubbleRadius), max(previewSize.width - bubbleRadius, bubbleRadius))
        let y = min(max(center.y - verticalOffset, bubbleRadius), max(previewSize.height - bubbleRadius, bubbleRadius))

        return CGPoint(x: x, y: y)
    }

    private func markerCenter(for corners: [CGPoint]) -> CGPoint {
        guard !corners.isEmpty else {
            return .zero
        }

        let sum = corners.reduce(CGPoint.zero) { partialResult, corner in
            CGPoint(
                x: partialResult.x + corner.x,
                y: partialResult.y + corner.y
            )
        }

        return CGPoint(
            x: sum.x / CGFloat(corners.count),
            y: sum.y / CGFloat(corners.count)
        )
    }

    private struct ProjectedMarker {
        let markerId: Int
        let corners: [CGPoint]
    }
}

private struct TagProgressBubble: View {
    let progress: Double

    var body: some View {
        Text(String(format: "%.0f%%", clampedProgress))
            .font(.caption.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(.black)
            .frame(width: 46, height: 46)
            .background(progressColor.opacity(0.92))
            .clipShape(Circle())
            .overlay {
                Circle()
                    .stroke(.black.opacity(0.7), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2)
    }

    private var clampedProgress: Double {
        min(max(progress, 0), 100)
    }

    private var progressColor: Color {
        switch clampedProgress {
        case 80...:
            return .green
        case 40..<80:
            return .yellow
        default:
            return .red
        }
    }
}
