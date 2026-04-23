import Foundation
import simd

public struct SfMConfiguration: Equatable {
    public var minimumFrames: Int

    public init(minimumFrames: Int = 12) {
        self.minimumFrames = minimumFrames
    }
}

public struct ReconstructionProgress: Equatable {
    public var stageDescription: String
    public var completion: Double
    public var processedFrames: Int
    public var sparsePointCount: Int
    public var densePointCount: Int

    public init(
        stageDescription: String,
        completion: Double,
        processedFrames: Int,
        sparsePointCount: Int,
        densePointCount: Int
    ) {
        self.stageDescription = stageDescription
        self.completion = completion
        self.processedFrames = processedFrames
        self.sparsePointCount = sparsePointCount
        self.densePointCount = densePointCount
    }
}

public final class SfMEngine {
    public let configuration: SfMConfiguration

    public init(configuration: SfMConfiguration = SfMConfiguration()) {
        self.configuration = configuration
    }

    public func bootstrap(with frames: [CaptureFrame], intrinsics: CameraIntrinsics) -> ReconstructionState {
        let sparsePoints = frames.flatMap { frame in
            frame.markers.compactMap { marker -> SparsePoint? in
                guard let pose = marker.pose else {
                    return nil
                }

                return SparsePoint(position: pose.translation, confidence: marker.confidence)
            }
        }

        let anchorMarkers = frames
            .flatMap(\.markers)
            .reduce(into: [Int: DetectedMarker]()) { partialResult, marker in
                partialResult[marker.id] = marker
            }
            .values
            .sorted { $0.id < $1.id }

        return ReconstructionState(
            sparsePoints: sparsePoints,
            densePoints: [],
            anchorMarkers: anchorMarkers,
            scaleMillimetersPerUnit: 1.0,
            processedFrameCount: frames.count,
            scaleAnchored: !anchorMarkers.isEmpty
        )
    }

    public func densify(_ reconstruction: ReconstructionState) -> ReconstructionState {
        guard reconstruction.densePoints.isEmpty else {
            return reconstruction
        }

        var copy = reconstruction
        copy.densePoints = reconstruction.sparsePoints.enumerated().map { index, point in
            DensePoint(
                position: point.position + SIMD3<Float>(Float(index % 3) * 0.05, Float(index % 2) * 0.03, Float(index % 5) * 0.02),
                normal: SIMD3<Float>(0, 0, 1),
                confidence: min(point.confidence + 0.05, 1.0)
            )
        }
        return copy
    }

    public func progress(for reconstruction: ReconstructionState, totalFrames: Int) -> ReconstructionProgress {
        let completion = totalFrames == 0 ? 0 : Double(reconstruction.processedFrameCount) / Double(totalFrames)

        return ReconstructionProgress(
            stageDescription: reconstruction.densePoints.isEmpty ? "Reconstrucao esparsa" : "Reconstrucao densa",
            completion: completion,
            processedFrames: reconstruction.processedFrameCount,
            sparsePointCount: reconstruction.sparsePoints.count,
            densePointCount: reconstruction.densePoints.count
        )
    }
}

