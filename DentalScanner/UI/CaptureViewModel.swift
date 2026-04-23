import DentalScannerKit
import Foundation
import SwiftUI
import simd

@MainActor
final class CaptureViewModel: ObservableObject {
    @Published var stage: ScanStage = .idle
    @Published var guidance: CaptureGuidance = .empty()
    @Published var latestMetrics = FrameQualityMetrics(
        sharpnessScore: 0,
        lightingMean: 0,
        lightingDeviation: 0,
        motionBlurScore: 0,
        overlapEstimate: 0,
        detectedTagCount: 0,
        tagsStable: false
    )
    @Published var mesh: Mesh3D?
    @Published var reportText = "Nenhum relatorio gerado."

    private let sessionManager = SessionManager()
    private let sfmEngine = SfMEngine()
    private let bundleAdjustment = BundleAdjustment()
    private let meshReconstructor = MeshReconstructor()
    private let reportGenerator = MeasurementReportGenerator()
    private var frameCounter = 0

    init() {
        let defaultCalibration = CameraIntrinsics(
            fx: 3020,
            fy: 3020,
            cx: 2016,
            cy: 1512,
            distortionCoefficients: [0.01, -0.04, 0.001, 0.0008, 0.0],
            reprojectionErrorPixels: 0.24
        )

        sessionManager.setCalibration(defaultCalibration)
        sessionManager.beginCaptureSession()
        syncState()
    }

    var coverageFraction: Double {
        let covered = guidance.coverageMap.filter { $0 }.count
        return Double(covered) / Double(max(guidance.coverageMap.count, 1))
    }

    var visibleMarkerCount: Int {
        guidance.tagVisibility.values.filter { $0 }.count
    }

    var visibleMarkerIDs: [Int] {
        guidance.tagVisibility.keys.sorted()
    }

    var canReconstruct: Bool {
        !sessionManager.state.frames.isEmpty
    }

    func startNewSession() {
        frameCounter = 0
        mesh = nil
        reportText = "Nenhum relatorio gerado."
        sessionManager.beginCaptureSession()
        syncState()
    }

    func addDemoFrame() {
        if stage != .capturing {
            sessionManager.beginCaptureSession()
        }

        frameCounter += 1
        let bucket = min(frameCounter - 1, sessionManager.configuration.coverageBucketCount - 1)
        let markers = syntheticMarkers(frameIndex: frameCounter)
        let metrics = FrameQualityMetrics(
            sharpnessScore: 210 + Double((frameCounter % 4) * 18),
            lightingMean: 100,
            lightingDeviation: 9 + Double(frameCounter % 3),
            motionBlurScore: 0.12,
            overlapEstimate: 0.76,
            detectedTagCount: markers.count,
            tagsStable: true
        )

        latestMetrics = metrics

        let frame = CaptureFrame(
            index: frameCounter,
            bucket: bucket,
            metrics: metrics,
            markers: markers,
            relativePose: PoseTransform(
                rotationEuler: SIMD3<Float>(0.02 * Float(frameCounter), 0.04 * Float(frameCounter), 0.01),
                translation: SIMD3<Float>(Float(bucket), Float(bucket) * 0.5, 42)
            )
        )

        _ = sessionManager.acceptFrame(frame)
        syncState()
    }

    func reconstruct() {
        guard let calibration = sessionManager.state.calibration else {
            return
        }

        sessionManager.markProcessingStarted()
        var reconstruction = sfmEngine.bootstrap(with: sessionManager.state.frames, intrinsics: calibration)
        reconstruction = sfmEngine.densify(reconstruction)
        reconstruction = bundleAdjustment.refine(reconstruction, anchors: sessionManager.state.frames.flatMap(\.markers))
        let mesh = meshReconstructor.reconstruct(from: reconstruction)

        sessionManager.completeReconstruction(reconstruction, mesh: mesh)
        self.mesh = mesh
        reportText = reportGenerator.makeMarkdown(session: sessionManager.state, accuracy: nil)
        syncState()
    }

    private func syncState() {
        let state = sessionManager.state
        stage = state.stage
        guidance = state.guidance
        mesh = state.mesh
    }

    private func syntheticMarkers(frameIndex: Int) -> [DetectedMarker] {
        let baseCorners = [
            CGPoint(x: 90, y: 90),
            CGPoint(x: 130, y: 90),
            CGPoint(x: 130, y: 130),
            CGPoint(x: 90, y: 130)
        ]

        return (0..<4).map { offset in
            let shift = CGFloat(offset * 50 + frameIndex * 2)
            let corners = baseCorners.map { CGPoint(x: $0.x + shift, y: $0.y + CGFloat(offset * 12)) }

            return DetectedMarker(
                id: offset + 1,
                dictionary: .fourByFour50,
                physicalSizeMillimeters: 8,
                corners: corners,
                pose: PoseTransform(
                    rotationEuler: SIMD3<Float>(0.01 * Float(frameIndex), 0.02 * Float(offset), 0),
                    translation: SIMD3<Float>(Float(offset * 6), Float(frameIndex), 35 + Float(offset))
                ),
                confidence: 0.95
            )
        }
    }
}

