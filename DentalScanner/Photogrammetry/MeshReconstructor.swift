import Foundation
import simd

public final class MeshReconstructor {
    public init() {}

    public func reconstruct(from reconstruction: ReconstructionState) -> Mesh3D {
        let points = reconstruction.densePoints.isEmpty
            ? reconstruction.sparsePoints.map { DensePoint(position: $0.position, normal: SIMD3<Float>(0, 0, 1), confidence: $0.confidence) }
            : reconstruction.densePoints

        let vertices = points.map(\.position)
        guard vertices.count >= 3 else {
            return Mesh3D(vertices: vertices, faces: [])
        }

        var faces: [SIMD3<Int>] = []
        for index in 1..<(vertices.count - 1) {
            faces.append(SIMD3<Int>(0, index, index + 1))
        }

        return Mesh3D(vertices: vertices, faces: faces)
    }
}

