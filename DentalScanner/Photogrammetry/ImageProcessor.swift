import Foundation

public struct ImageProcessorConfiguration: Equatable {
    public var minimumSharpnessScore: Double
    public var maximumLightingDeviationRatio: Double
    public var maximumMotionBlurScore: Double

    public init(
        minimumSharpnessScore: Double = 180,
        maximumLightingDeviationRatio: Double = 0.15,
        maximumMotionBlurScore: Double = 0.35
    ) {
        self.minimumSharpnessScore = minimumSharpnessScore
        self.maximumLightingDeviationRatio = maximumLightingDeviationRatio
        self.maximumMotionBlurScore = maximumMotionBlurScore
    }
}

public struct PreprocessingDecision: Equatable {
    public var applyCLAHE: Bool
    public var normalizeLighting: Bool
    public var rejectFrame: Bool
    public var reasons: [String]

    public init(
        applyCLAHE: Bool,
        normalizeLighting: Bool,
        rejectFrame: Bool,
        reasons: [String]
    ) {
        self.applyCLAHE = applyCLAHE
        self.normalizeLighting = normalizeLighting
        self.rejectFrame = rejectFrame
        self.reasons = reasons
    }
}

public final class ImageProcessor {
    public let configuration: ImageProcessorConfiguration

    public init(configuration: ImageProcessorConfiguration = ImageProcessorConfiguration()) {
        self.configuration = configuration
    }

    public func makeDecision(for metrics: FrameQualityMetrics) -> PreprocessingDecision {
        var reasons: [String] = []

        if metrics.sharpnessScore < configuration.minimumSharpnessScore {
            reasons.append("Nitidez insuficiente para triangulacao confiavel.")
        }

        if metrics.motionBlurScore > configuration.maximumMotionBlurScore {
            reasons.append("Motion blur acima do limite permitido.")
        }

        let lightingThreshold = max(1, metrics.lightingMean * configuration.maximumLightingDeviationRatio)
        if metrics.lightingDeviation > lightingThreshold {
            reasons.append("Iluminacao heterogenea; recomenda-se normalizacao adicional.")
        }

        return PreprocessingDecision(
            applyCLAHE: metrics.lightingDeviation > lightingThreshold,
            normalizeLighting: metrics.lightingDeviation > lightingThreshold,
            rejectFrame: metrics.sharpnessScore < configuration.minimumSharpnessScore || metrics.motionBlurScore > configuration.maximumMotionBlurScore,
            reasons: reasons
        )
    }

    public func normalizedQualityScore(for metrics: FrameQualityMetrics) -> Double {
        let sharpness = min(metrics.sharpnessScore / max(configuration.minimumSharpnessScore, 1), 1.0)
        let lighting = max(0, 1 - metrics.lightingDeviation / max(metrics.lightingMean * configuration.maximumLightingDeviationRatio, 1))
        let blur = max(0, 1 - metrics.motionBlurScore / max(configuration.maximumMotionBlurScore, 0.01))

        return ((sharpness + lighting + blur) / 3.0) * 100
    }
}

