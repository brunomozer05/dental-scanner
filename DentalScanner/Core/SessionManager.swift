import Foundation

public struct SessionConfiguration: Equatable {
    public var coverageBucketCount: Int
    public var minimumValidFrames: Int
    public var minimumSharpnessScore: Double
    public var maximumLightingDeviationRatio: Double
    public var minimumOverlap: Double
    public var requiredVisibleTags: Int
    public var maximumMotionBlurScore: Double

    public init(
        coverageBucketCount: Int = 18,
        minimumValidFrames: Int = 15,
        minimumSharpnessScore: Double = 180,
        maximumLightingDeviationRatio: Double = 0.15,
        minimumOverlap: Double = 0.70,
        requiredVisibleTags: Int = 4,
        maximumMotionBlurScore: Double = 0.35
    ) {
        self.coverageBucketCount = coverageBucketCount
        self.minimumValidFrames = minimumValidFrames
        self.minimumSharpnessScore = minimumSharpnessScore
        self.maximumLightingDeviationRatio = maximumLightingDeviationRatio
        self.minimumOverlap = minimumOverlap
        self.requiredVisibleTags = requiredVisibleTags
        self.maximumMotionBlurScore = maximumMotionBlurScore
    }
}

public final class SessionManager {
    public let configuration: SessionConfiguration
    public private(set) var state: ScanSessionState

    public init(configuration: SessionConfiguration = SessionConfiguration()) {
        self.configuration = configuration
        self.state = ScanSessionState(guidance: .empty(bucketCount: configuration.coverageBucketCount))
    }

    public func beginCalibration() {
        state.stage = .calibrating
    }

    public func setCalibration(_ intrinsics: CameraIntrinsics) {
        state.calibration = intrinsics
        state.stage = .capturing
        state.guidance = .empty(bucketCount: configuration.coverageBucketCount)
    }

    public func beginCaptureSession() {
        state.frames = []
        state.reconstruction = nil
        state.mesh = nil
        state.stage = .capturing
        state.guidance = .empty(bucketCount: configuration.coverageBucketCount)
    }

    public func guidance(for candidate: CaptureFrame) -> CaptureGuidance {
        let acceptedFrames = state.frames + (passesQualityGate(candidate.metrics) ? [candidate.normalized(to: configuration.coverageBucketCount)] : [])
        return buildGuidance(from: acceptedFrames, latestFrame: candidate)
    }

    @discardableResult
    public func acceptFrame(_ frame: CaptureFrame) -> Bool {
        let normalizedFrame = frame.normalized(to: configuration.coverageBucketCount)
        let accepted = passesQualityGate(normalizedFrame.metrics)

        if accepted {
            state.frames.append(normalizedFrame)
        }

        state.guidance = buildGuidance(from: state.frames, latestFrame: normalizedFrame)

        if shouldAdvanceToProcessing() {
            state.stage = .processing
        }

        return accepted
    }

    public func markProcessingStarted() {
        state.stage = .processing
    }

    public func completeReconstruction(_ reconstruction: ReconstructionState, mesh: Mesh3D) {
        state.reconstruction = reconstruction
        state.mesh = mesh
        state.stage = .preview
    }

    public func reset() {
        state = ScanSessionState(guidance: .empty(bucketCount: configuration.coverageBucketCount))
    }

    public func shouldAdvanceToProcessing() -> Bool {
        guard state.frames.count >= configuration.minimumValidFrames else {
            return false
        }

        let coveredBuckets = state.guidance.coverageMap.filter { $0 }.count
        return Double(coveredBuckets) / Double(configuration.coverageBucketCount) >= 0.80
    }

    private func buildGuidance(from frames: [CaptureFrame], latestFrame: CaptureFrame?) -> CaptureGuidance {
        var coverageMap = Array(repeating: false, count: configuration.coverageBucketCount)
        frames.forEach { frame in
            coverageMap[frame.bucket] = true
        }

        let latestVisibleMarkers = Dictionary(
            uniqueKeysWithValues: (latestFrame?.markers ?? []).map { ($0.id, true) }
        )

        let recentFrames = Array(frames.suffix(5))
        let qualityScore = recentFrames.isEmpty ? 0 : Float(recentFrames.map(qualityScore(for:)).reduce(0, +) / Double(recentFrames.count))

        var recommendations: [String] = []
        let coveragePercent = Double(coverageMap.filter { $0 }.count) / Double(max(1, coverageMap.count))

        if coveragePercent < 0.80 {
            recommendations.append("Continue a orbita ao redor do conjunto de tags ate cobrir pelo menos 80% dos angulos.")
        }

        if let latestFrame, latestFrame.metrics.detectedTagCount < configuration.requiredVisibleTags {
            recommendations.append("Mantenha pelo menos \(configuration.requiredVisibleTags) tags ArUco totalmente visiveis.")
        }

        if let latestFrame, latestFrame.metrics.overlapEstimate < configuration.minimumOverlap {
            recommendations.append("Aumente a sobreposicao entre frames consecutivos para 70-80%.")
        }

        if let latestFrame, latestFrame.metrics.sharpnessScore < configuration.minimumSharpnessScore {
            recommendations.append("Melhore o foco ou reduza o movimento para aumentar a nitidez.")
        }

        if let latestFrame,
           latestFrame.metrics.lightingDeviation > latestFrame.metrics.lightingMean * configuration.maximumLightingDeviationRatio {
            recommendations.append("Uniformize a iluminacao e reduza sombras duras sobre as tags e o suporte.")
        }

        if recommendations.isEmpty {
            recommendations.append("Qualidade consistente. Continue a captura incremental.")
        }

        return CaptureGuidance(
            coverageMap: coverageMap,
            qualityScore: qualityScore,
            tagVisibility: latestVisibleMarkers,
            recommendations: recommendations,
            validFrameCount: frames.count
        )
    }

    private func qualityScore(for frame: CaptureFrame) -> Double {
        let sharpness = min(frame.metrics.sharpnessScore / max(configuration.minimumSharpnessScore, 1), 1.2)
        let lighting = max(0, 1 - (frame.metrics.lightingDeviation / max(frame.metrics.lightingMean * configuration.maximumLightingDeviationRatio, 1)))
        let overlap = min(frame.metrics.overlapEstimate / max(configuration.minimumOverlap, 0.01), 1.1)
        let tags = min(Double(frame.metrics.detectedTagCount) / Double(max(configuration.requiredVisibleTags, 1)), 1.0)
        let blur = max(0, 1 - frame.metrics.motionBlurScore / max(configuration.maximumMotionBlurScore, 0.01))

        return ((sharpness + lighting + overlap + tags + blur) / 5.0) * 100
    }

    private func passesQualityGate(_ metrics: FrameQualityMetrics) -> Bool {
        let lightingThreshold = max(1, metrics.lightingMean * configuration.maximumLightingDeviationRatio)

        return metrics.sharpnessScore >= configuration.minimumSharpnessScore
            && metrics.overlapEstimate >= configuration.minimumOverlap
            && metrics.detectedTagCount >= configuration.requiredVisibleTags
            && metrics.lightingDeviation <= lightingThreshold
            && metrics.motionBlurScore <= configuration.maximumMotionBlurScore
            && metrics.tagsStable
    }
}

private extension CaptureFrame {
    func normalized(to bucketCount: Int) -> CaptureFrame {
        var copy = self
        copy.bucket = min(max(bucket, 0), max(bucketCount - 1, 0))
        return copy
    }
}
