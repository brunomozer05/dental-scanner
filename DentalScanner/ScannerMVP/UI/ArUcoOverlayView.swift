import Foundation
import SwiftUI

struct ArUcoOverlayView: View {
    let detections: [MarkerOverlayResult]
    let frameResolution: ScannerViewModel.FrameResolution?
    let orientation: CameraPreviewOrientation
    let tagCoverages: [Int: ScannerViewModel.ScanTagCoverage]

    @State private var trackedMarkers: [Int: TrackedMarker] = [:]

    private let markerPersistenceDuration: TimeInterval = 0.35
    private let markerFadeAnimation = Animation.easeInOut(duration: 0.16)
    private let markerSlowMotionCurrentWeight: CGFloat = 0.45
    private let markerFastMotionCurrentWeight: CGFloat = 0.75
    private let markerFastMotionDistanceThreshold: CGFloat = 20
    private let markerMotionResponseScale: CGFloat = 36
    private let markerPredictionFactor: CGFloat = 0.15

    var body: some View {
        GeometryReader { proxy in
            let markers = projectedMarkers(in: proxy.size)
            let stableMarkers = trackedMarkers.values.sorted { $0.markerId < $1.markerId }

            ZStack {
                ForEach(stableMarkers) { trackedMarker in
                    let marker = trackedMarker.projectedMarker
                    let progress = tagCoverages[trackedMarker.markerId]?.progress ?? trackedMarker.progress

                    TagAROverlayView(
                        title: marker.displayTitle,
                        modeTitle: marker.modeTitle,
                        corners: marker.corners,
                        progress: progress,
                        displayScale: trackedMarker.displayScale,
                        displayOpacity: trackedMarker.displayOpacity
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
                displayTitle: detection.displayTitle,
                modeTitle: detection.modeTitle,
                corners: detection.corners.map(project),
                displayOpacity: min(max(detection.visualConfidence, 0.25), 1.0)
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
            let currentDisplayScale = markerDisplayScale(for: marker.corners)

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
                    displayTitle: marker.displayTitle,
                    modeTitle: marker.modeTitle,
                    corners: smoothedCorners(
                        previous: previousMarker.corners,
                        current: marker.corners,
                        targetCenter: predictedCenter
                    ),
                    lastSeen: timestamp,
                    previousCenter: currentCenter,
                    progress: progress,
                    displayScale: smoothedDisplayScale(
                        previous: previousMarker.displayScale,
                        current: currentDisplayScale
                    ),
                    displayOpacity: marker.displayOpacity
                )
            } else {
                nextMarkers[marker.markerId] = TrackedMarker(
                    markerId: marker.markerId,
                    displayTitle: marker.displayTitle,
                    modeTitle: marker.modeTitle,
                    corners: marker.corners,
                    lastSeen: timestamp,
                    previousCenter: markerCenter(for: marker.corners),
                    progress: progress,
                    displayScale: currentDisplayScale,
                    displayOpacity: marker.displayOpacity
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

        return zip(previous, current).map { previousCorner, currentCorner in
            CGPoint(
                x: previousCorner.x + (currentCorner.x - previousCorner.x) * currentWeight,
                y: previousCorner.y + (currentCorner.y - previousCorner.y) * currentWeight
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

    private func markerDisplayScale(for corners: [CGPoint]) -> CGFloat {
        guard corners.count == 4 else {
            return 1
        }

        let width = distance(corners[0], corners[1])
        let height = distance(corners[1], corners[2])
        let tagSize = (width + height) / 2
        let scale = tagSize / 120.0
        return min(max(scale, 0.5), 1.8)
    }

    private func smoothedDisplayScale(previous: CGFloat, current: CGFloat) -> CGFloat {
        previous * 0.7 + current * 0.3
    }

    private func distance(_ first: CGPoint, _ second: CGPoint) -> CGFloat {
        hypot(second.x - first.x, second.y - first.y)
    }

    private struct ProjectedMarker: Equatable {
        let markerId: Int
        let displayTitle: String
        let modeTitle: String?
        let corners: [CGPoint]
        let displayOpacity: Double
    }

    private struct TrackedMarker: Equatable, Identifiable {
        let markerId: Int
        let displayTitle: String
        let modeTitle: String?
        let corners: [CGPoint]
        let lastSeen: Date
        let previousCenter: CGPoint?
        let progress: Double
        let displayScale: CGFloat
        let displayOpacity: Double

        var id: Int {
            markerId
        }

        var projectedMarker: ProjectedMarker {
            ProjectedMarker(
                markerId: markerId,
                displayTitle: displayTitle,
                modeTitle: modeTitle,
                corners: corners,
                displayOpacity: displayOpacity
            )
        }
    }
}

private struct TagAROverlayView: View {
    let title: String
    let modeTitle: String?
    let corners: [CGPoint]
    let progress: Double
    let displayScale: CGFloat
    let displayOpacity: Double

    private let accentColor = Color(red: 0.23, green: 0.51, blue: 0.96)

    var body: some View {
        ZStack {
            ArucoTagOverlayShape(corners: corners)
                .stroke(
                    accentColor.opacity(0.36),
                    style: StrokeStyle(lineWidth: glowLineWidth, lineCap: .round, lineJoin: .round)
                )
                .blur(radius: glowRadius)

            ArucoTagOverlayShape(corners: corners)
                .stroke(
                    accentColor.opacity(0.92),
                    style: StrokeStyle(lineWidth: tagLineWidth, lineCap: .round, lineJoin: .round)
                )
                .shadow(color: accentColor.opacity(0.52), radius: glowRadius, x: 0, y: 0)

            ForEach(Array(corners.enumerated()), id: \.offset) { item in
                Circle()
                    .fill(Color.white.opacity(0.96))
                    .frame(width: cornerNodeSize, height: cornerNodeSize)
                    .overlay {
                        Circle()
                            .stroke(accentColor.opacity(0.95), lineWidth: cornerNodeStrokeWidth)
                    }
                    .shadow(color: accentColor.opacity(0.58), radius: cornerNodeGlowRadius, x: 0, y: 0)
                    .position(item.element)
            }

            MarkerProgressRingView(
                title: title,
                modeTitle: modeTitle,
                progress: progressRatio
            )
            .scaleEffect(clampedDisplayScale)
            .position(x: markerCenter.x, y: markerCenter.y - cardVerticalOffset)
        }
        .opacity(min(max(displayOpacity, 0.25), 1.0))
        .animation(.easeOut(duration: 0.16), value: clampedProgress)
        .animation(.easeOut(duration: 0.16), value: clampedDisplayScale)
    }

    private var clampedProgress: Double {
        min(max(progress, 0), 100)
    }

    private var progressRatio: Double {
        clampedProgress / 100.0
    }

    private var clampedDisplayScale: CGFloat {
        min(max(displayScale, 0.5), 1.8)
    }

    private var tagLineWidth: CGFloat {
        4 * clampedDisplayScale
    }

    private var glowLineWidth: CGFloat {
        tagLineWidth * 1.8
    }

    private var glowRadius: CGFloat {
        4 * clampedDisplayScale
    }

    private var cornerNodeSize: CGFloat {
        10 * clampedDisplayScale
    }

    private var cornerNodeStrokeWidth: CGFloat {
        2.2 * clampedDisplayScale
    }

    private var cornerNodeGlowRadius: CGFloat {
        3.5 * clampedDisplayScale
    }

    private var cardVerticalOffset: CGFloat {
        54 * clampedDisplayScale
    }

    private var markerCenter: CGPoint {
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
}

private struct MarkerProgressRingView: View {
    let title: String
    let modeTitle: String?
    let progress: Double

    private var clampedProgress: Double {
        guard progress.isFinite else {
            return 0
        }

        return min(max(progress, 0), 1)
    }

    private var progressColor: Color {
        switch clampedProgress {
        case ..<0.30:
            return Color(red: 0.95, green: 0.22, blue: 0.18)
        case ..<0.80:
            return Color(red: 1.0, green: 0.66, blue: 0.12)
        case ..<1.0:
            return Color(red: 0.38, green: 0.86, blue: 0.42)
        default:
            return Color(red: 0.10, green: 0.78, blue: 0.30)
        }
    }

    private var percentText: String {
        "\(Int(round(clampedProgress * 100)))%"
    }

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.72))

                Circle()
                    .stroke(Color.white.opacity(0.16), lineWidth: 5)

                Circle()
                    .trim(from: 0, to: clampedProgress)
                    .stroke(
                        progressColor,
                        style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: progressColor.opacity(0.45), radius: 4, x: 0, y: 0)

                VStack(spacing: 0) {
                    Text(percentText)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                        .minimumScaleFactor(0.75)

                    Text(title)
                        .font(.system(size: 8, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.78))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .padding(.horizontal, 4)
            }
            .frame(width: 50, height: 50)
            .overlay {
                Circle()
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            }

            if let modeTitle {
                Text(modeTitle)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.58))
                    .clipShape(Capsule())
            }
        }
        .shadow(color: Color.black.opacity(0.30), radius: 8, x: 0, y: 4)
    }
}

private struct ArucoTagOverlayShape: Shape {
    let corners: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard corners.count == 4 else {
            return path
        }

        path.move(to: corners[0])
        path.addLine(to: corners[1])
        path.addLine(to: corners[2])
        path.addLine(to: corners[3])
        path.closeSubpath()

        return path
    }
}
