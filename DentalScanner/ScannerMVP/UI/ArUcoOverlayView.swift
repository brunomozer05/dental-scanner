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

                    TagAROverlayView(
                        markerId: trackedMarker.markerId,
                        corners: marker.corners,
                        progress: progress
                    )
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
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
        let movementThreshold: CGFloat = 4.0
        let movementDeltaX = currentCenter.x - previousCenter.x
        let movementDeltaY = currentCenter.y - previousCenter.y
        let movementDistance = hypot(movementDeltaX, movementDeltaY)

        guard movementDistance >= movementThreshold else {
            return previous
        }

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

private struct TagAROverlayView: View {
    let markerId: Int
    let corners: [CGPoint]
    let progress: Double

    private let accentColor = Color(red: 0.23, green: 0.51, blue: 0.96)
    private let depthOffset = CGSize(width: 10, height: -10)
    private let nodeSize: CGFloat = 4.5

    var body: some View {
        ZStack {
            boxPath(frontCorners: corners, backCorners: backCorners)
                .stroke(accentColor.opacity(0.18), lineWidth: 6)
                .blur(radius: 5.5)

            polygonPath(corners: corners)
                .stroke(
                    accentColor.opacity(0.25),
                    style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round)
                )
                .blur(radius: 2.2)

            polygonPath(corners: backCorners)
                .stroke(
                    accentColor.opacity(0.22),
                    style: StrokeStyle(lineWidth: 1.0, lineCap: .round, lineJoin: .round)
                )

            connectorPath(frontCorners: corners, backCorners: backCorners)
                .stroke(
                    accentColor.opacity(0.34),
                    style: StrokeStyle(lineWidth: 0.9, lineCap: .round, lineJoin: .round)
                )

            polygonPath(corners: corners)
                .stroke(
                    accentColor.opacity(0.96),
                    style: StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round)
                )

            topProgressPath(corners: corners, progress: clampedProgress / 100.0)
                .stroke(
                    progressColor,
                    style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round)
                )
                .shadow(color: accentColor.opacity(0.58), radius: 4, x: 0, y: 0)

            ForEach(Array(corners.enumerated()), id: \.offset) { item in
                cornerNode(size: nodeSize)
                    .position(item.element)
            }

            ForEach(Array(backCorners.enumerated()), id: \.offset) { item in
                cornerNode(size: nodeSize * 0.72)
                    .opacity(0.55)
                    .position(item.element)
            }

            indicatorConnectorPath(from: indicatorPosition, to: tagAnchorPosition)
                .stroke(
                    accentColor.opacity(0.42),
                    style: StrokeStyle(lineWidth: 0.9, lineCap: .round)
                )

            TagARProgressIndicator(
                markerId: markerId,
                progress: clampedProgress,
                accentColor: accentColor
            )
            .position(indicatorPosition)
        }
    }

    private var clampedProgress: Double {
        min(max(progress, 0), 100)
    }

    private var progressRatio: Double {
        clampedProgress / 100.0
    }

    private var progressColor: Color {
        accentColor.opacity(0.46 + 0.52 * progressRatio)
    }

    private var backCorners: [CGPoint] {
        corners.map { corner in
            CGPoint(
                x: corner.x + depthOffset.width,
                y: corner.y + depthOffset.height
            )
        }
    }

    private var tagAnchorPosition: CGPoint {
        guard corners.count >= 2 else {
            return .zero
        }

        return midpoint(corners[0], corners[1])
    }

    private var indicatorPosition: CGPoint {
        CGPoint(x: tagAnchorPosition.x + 8, y: tagAnchorPosition.y - 38)
    }

    private func cornerNode(size: CGFloat) -> some View {
        Circle()
            .fill(accentColor.opacity(0.20))
            .frame(width: size, height: size)
            .overlay {
                Circle()
                    .stroke(accentColor.opacity(0.90), lineWidth: 1)
            }
            .shadow(color: accentColor.opacity(0.58), radius: 3, x: 0, y: 0)
    }

    private func polygonPath(corners: [CGPoint]) -> Path {
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

    private func connectorPath(frontCorners: [CGPoint], backCorners: [CGPoint]) -> Path {
        var path = Path()
        guard frontCorners.count == backCorners.count else {
            return path
        }

        for index in frontCorners.indices {
            path.move(to: frontCorners[index])
            path.addLine(to: backCorners[index])
        }

        return path
    }

    private func boxPath(frontCorners: [CGPoint], backCorners: [CGPoint]) -> Path {
        var path = polygonPath(corners: frontCorners)
        path.addPath(polygonPath(corners: backCorners))
        path.addPath(connectorPath(frontCorners: frontCorners, backCorners: backCorners))
        return path
    }

    private func topProgressPath(corners: [CGPoint], progress: Double) -> Path {
        var path = Path()
        guard corners.count >= 2 else {
            return path
        }

        let start = corners[0]
        let end = corners[1]
        let progressEnd = CGPoint(
            x: start.x + (end.x - start.x) * CGFloat(progress),
            y: start.y + (end.y - start.y) * CGFloat(progress)
        )

        path.move(to: start)
        path.addLine(to: progressEnd)
        return path
    }

    private func indicatorConnectorPath(from indicatorPosition: CGPoint, to anchorPosition: CGPoint) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: indicatorPosition.x, y: indicatorPosition.y + 18))
        path.addLine(to: anchorPosition)
        return path
    }

    private func midpoint(_ first: CGPoint, _ second: CGPoint) -> CGPoint {
        CGPoint(
            x: (first.x + second.x) / 2,
            y: (first.y + second.y) / 2
        )
    }
}

private struct TagARProgressIndicator: View {
    let markerId: Int
    let progress: Double
    let accentColor: Color

    private var progressRatio: Double {
        min(max(progress / 100.0, 0), 1)
    }

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Circle()
                            .fill(Color.black.opacity(0.52))
                    }

                Circle()
                    .stroke(Color.white.opacity(0.14), lineWidth: 2)

                Circle()
                    .trim(from: 0, to: progressRatio)
                    .stroke(
                        accentColor.opacity(0.52 + 0.44 * progressRatio),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: accentColor.opacity(0.40), radius: 3, x: 0, y: 0)

                Text(String(format: "%.0f%%", progress))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white.opacity(0.92))
                    .monospacedDigit()
            }
            .frame(width: 38, height: 38)

            Text("ID \(markerId)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.58))
        }
        .shadow(color: Color.black.opacity(0.32), radius: 8, x: 0, y: 3)
    }
}
