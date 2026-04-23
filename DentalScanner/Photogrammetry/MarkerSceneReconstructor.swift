import Foundation
import simd

public final class MarkerSceneReconstructor {
    public init() {}

    public func reconstruct(from frames: [CaptureFrame]) -> ReconstructionState {
        let observationsByID = Dictionary(
            grouping: frames.flatMap(\.markers).filter { $0.pose != nil },
            by: \.id
        )

        let fusedMarkers = observationsByID.keys.sorted().compactMap { markerID in
            fuseObservations(observationsByID[markerID] ?? [])
        }

        let sparsePoints = fusedMarkers.compactMap { marker -> SparsePoint? in
            guard let pose = marker.pose else {
                return nil
            }

            return SparsePoint(position: pose.translation, confidence: marker.confidence)
        }

        return ReconstructionState(
            sparsePoints: sparsePoints,
            densePoints: [],
            anchorMarkers: fusedMarkers,
            scaleMillimetersPerUnit: 1.0,
            processedFrameCount: frames.count,
            scaleAnchored: !fusedMarkers.isEmpty
        )
    }

    private func fuseObservations(_ observations: [DetectedMarker]) -> DetectedMarker? {
        let validObservations = observations.filter { $0.pose != nil }
        guard !validObservations.isEmpty else {
            return nil
        }

        let translationSum = validObservations.reduce(SIMD3<Float>.zero) { partialResult, marker in
            partialResult + (marker.pose?.translation ?? .zero)
        }

        let rotationSum = validObservations.reduce(SIMD3<Float>.zero) { partialResult, marker in
            partialResult + (marker.pose?.rotationEuler ?? .zero)
        }

        let confidenceSum = validObservations.reduce(0 as Float) { $0 + $1.confidence }
        let count = Float(validObservations.count)
        let reference = validObservations.max { $0.confidence < $1.confidence } ?? validObservations[0]

        return DetectedMarker(
            id: reference.id,
            dictionary: reference.dictionary,
            physicalSizeMillimeters: validObservations.map(\.physicalSizeMillimeters).reduce(0, +) / Double(validObservations.count),
            corners: reference.corners,
            pose: PoseTransform(
                rotationEuler: rotationSum / count,
                translation: translationSum / count
            ),
            confidence: confidenceSum / count
        )
    }
}

