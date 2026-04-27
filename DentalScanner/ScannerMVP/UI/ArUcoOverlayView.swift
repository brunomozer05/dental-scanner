import Foundation
import SwiftUI

struct ArUcoOverlayView: View {
    let detections: [ArUcoDetectionResult]
    let frameResolution: ScannerViewModel.FrameResolution?
    let orientation: CameraPreviewOrientation
    let tagCoverages: [Int: ScannerViewModel.ScanTagCoverage]

    @State private var trackedMarkers: [Int: TrackedMarker] = [:]

    private let markerPersistenceDuration: TimeInterval = 0.12
    private let markerFadeAnimation = Animation.easeInOut(duration: 0.14)
    private let markerSlowMotionCurrentWeight: CGFloat = 0.35
    private let markerFastMotionCurrentWeight: CGFloat = 0.93
    private let markerFastMotionDistanceThreshold: CGFloat = 6
    private let markerMotionResponseScale: CGFloat = 20
    private let markerPredictionFactor: CGFloat = 0.6

    var body: some View {
        GeometryReader { proxy in
            let markers = projectedMarkers(in: proxy.size)
            let stableMarkers = trackedMarkers.values.sorted { $0.markerId < $1.markerId }

            ZStack {
                ForEach(stableMarkers) { trackedMarker in
                    let marker = trackedMarker.projectedMarker
                    let progress = tagCoverages[trackedMarker.markerId]?.progress ?? trackedMarker.progress

                    ZStack {
                        markerOverlay(marker: marker, previewSize: proxy.size)

                        TagProgressBubble(progress: progress)
                            .position(bubblePosition(for: marker, in: proxy.size))
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .transition(.opacity)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .onAppear {
                updateTrackedMarkers(with: markers)
            }
            .onChange(of: markers) { _, newMarkers in
                updateTrackedMarkers(with: newMarkers)
            }
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

    private func updateTrackedMarkers(with markers: [ProjectedMarker], timestamp: Date = Date()) {
        var nextMarkers = trackedMarkers.filter { _, marker in
            timestamp.timeIntervalSince(marker.lastSeen) <= markerPersistenceDuration
        }

        for marker in markers {
            let progress = tagCoverages[marker.markerId]?.progress ??
                nextMarkers[marker.markerId]?.progress ??
                0

            if let previousMarker = nextMarkers[marker.markerId] {
                let currentCenter = markerCenter(for: marker.corners)
                let previousCenter = previousMarker.previousCenter ?? currentCenter
                let velocity = CGPoint(
                    x: currentCenter.x - previousCenter.x,
                    y: currentCenter.y - previousCenter.y
                )
                let predictedCenter = CGPoint(
                    x: currentCenter.x + velocity.x * markerPredictionFactor,
                    y: currentCenter.y + velocity.y * markerPredictionFactor
                )

                nextMarkers[marker.markerId] = TrackedMarker(
                    markerId: marker.markerId,
                    corners: smoothedCorners(
                        previous: previousMarker.corners,
                        current: marker.corners,
                        targetCenter: predictedCenter
                    ),
                    lastSeen: timestamp,
                    previousCenter: currentCenter,
                    progress: progress
                )
            } else {
                nextMarkers[marker.markerId] = TrackedMarker(
                    markerId: marker.markerId,
                    corners: marker.corners,
                    lastSeen: timestamp,
                    previousCenter: markerCenter(for: marker.corners),
                    progress: progress
                )
            }
        }

        withAnimation(markerFadeAnimation) {
            trackedMarkers = nextMarkers
        }

        scheduleExpiredMarkerPrune()
    }

    private func scheduleExpiredMarkerPrune() {
        guard !trackedMarkers.isEmpty else {
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + markerPersistenceDuration) {
            self.pruneExpiredMarkers(at: Date())
        }
    }

    private func pruneExpiredMarkers(at timestamp: Date) {
        let nextMarkers = trackedMarkers.filter { _, marker in
            timestamp.timeIntervalSince(marker.lastSeen) <= markerPersistenceDuration
        }

        guard nextMarkers.count != trackedMarkers.count else {
            return
        }

        withAnimation(markerFadeAnimation) {
            trackedMarkers = nextMarkers
        }
    }

    private func smoothedCorners(
        previous: [CGPoint],
        current: [CGPoint],
        targetCenter: CGPoint
    ) -> [CGPoint] {
        guard previous.count == current.count else {
            return current
        }

        let previousCenter = markerCenter(for: previous)
        let currentCenter = markerCenter(for: current)
        let centerDeltaX = targetCenter.x - previousCenter.x
        let centerDeltaY = targetCenter.y - previousCenter.y
        let centerDistance = (centerDeltaX * centerDeltaX + centerDeltaY * centerDeltaY).squareRoot()
        let responseDistance = max(centerDistance - markerFastMotionDistanceThreshold, 0)
        let t = min(responseDistance / markerMotionResponseScale, 1.0)
        let currentWeight = markerSlowMotionCurrentWeight * (1.0 - t) +
            markerFastMotionCurrentWeight * t

        let smoothedCenter = CGPoint(
            x: previousCenter.x + centerDeltaX * currentWeight,
            y: previousCenter.y + centerDeltaY * currentWeight
        )
        let offsetX = smoothedCenter.x - currentCenter.x
        let offsetY = smoothedCenter.y - currentCenter.y

        return current.map { corner in
            CGPoint(
                x: corner.x + offsetX,
                y: corner.y + offsetY
            )
        }
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

    private struct ProjectedMarker: Equatable {
        let markerId: Int
        let corners: [CGPoint]
    }

    private struct TrackedMarker: Equatable, Identifiable {
        let markerId: Int
        let corners: [CGPoint]
        let lastSeen: Date
        let previousCenter: CGPoint?
        let progress: Double

        var id: Int {
            markerId
        }

        var projectedMarker: ProjectedMarker {
            ProjectedMarker(markerId: markerId, corners: corners)
        }
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
