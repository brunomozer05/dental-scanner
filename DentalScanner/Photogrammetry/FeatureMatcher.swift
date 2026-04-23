import Foundation

public struct FeatureMatcherConfiguration: Equatable {
    public var minimumPairConfidence: Double
    public var maximumLookAhead: Int
    public var coverageBucketCount: Int
    public var minimumSharedTags: Int

    public init(
        minimumPairConfidence: Double = 0.72,
        maximumLookAhead: Int = 4,
        coverageBucketCount: Int = 18,
        minimumSharedTags: Int = 2
    ) {
        self.minimumPairConfidence = minimumPairConfidence
        self.maximumLookAhead = maximumLookAhead
        self.coverageBucketCount = coverageBucketCount
        self.minimumSharedTags = minimumSharedTags
    }
}

public struct FramePairCandidate: Equatable {
    public var sourceFrameIndex: Int
    public var targetFrameIndex: Int
    public var overlapScore: Double
    public var sharedMarkerIDs: [Int]

    public init(
        sourceFrameIndex: Int,
        targetFrameIndex: Int,
        overlapScore: Double,
        sharedMarkerIDs: [Int]
    ) {
        self.sourceFrameIndex = sourceFrameIndex
        self.targetFrameIndex = targetFrameIndex
        self.overlapScore = overlapScore
        self.sharedMarkerIDs = sharedMarkerIDs
    }
}

public final class FeatureMatcher {
    public let configuration: FeatureMatcherConfiguration

    public init(configuration: FeatureMatcherConfiguration = FeatureMatcherConfiguration()) {
        self.configuration = configuration
    }

    public func buildPairCandidates(from frames: [CaptureFrame]) -> [FramePairCandidate] {
        guard frames.count > 1 else {
            return []
        }

        var candidates: [FramePairCandidate] = []

        for sourceIndex in 0..<(frames.count - 1) {
            let source = frames[sourceIndex]
            let upperBound = min(frames.count, sourceIndex + configuration.maximumLookAhead + 1)

            for targetIndex in (sourceIndex + 1)..<upperBound {
                let target = frames[targetIndex]
                let sharedTags = Array(Set(source.markers.map(\.id)).intersection(target.markers.map(\.id))).sorted()
                let bucketDistance = abs(source.bucket - target.bucket)
                let angularOverlap = max(0, 1 - Double(bucketDistance) / Double(max(configuration.coverageBucketCount, 1)))
                let tagSupport = min(Double(sharedTags.count) / Double(max(configuration.minimumSharedTags, 1)), 1.0)
                let overlapScore = (angularOverlap * 0.6) + (tagSupport * 0.4)

                if overlapScore >= configuration.minimumPairConfidence {
                    candidates.append(
                        FramePairCandidate(
                            sourceFrameIndex: source.index,
                            targetFrameIndex: target.index,
                            overlapScore: overlapScore,
                            sharedMarkerIDs: sharedTags
                        )
                    )
                }
            }
        }

        return candidates
    }
}

