import Foundation
import simd

public final class MeshReconstructor {
    public init() {}

    public func reconstruct(from reconstruction: ReconstructionState) -> Mesh3D {
        if !reconstruction.anchorMarkers.isEmpty {
            return markerMesh(from: reconstruction.anchorMarkers)
        }

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

    private func markerMesh(from markers: [DetectedMarker], thicknessMillimeters: Float = 0.6) -> Mesh3D {
        var vertices: [SIMD3<Float>] = []
        var faces: [SIMD3<Int>] = []

        for marker in markers {
            guard let pose = marker.pose else {
                continue
            }

            let startIndex = vertices.count
            let halfSize = Float(marker.physicalSizeMillimeters) / 2
            let halfThickness = thicknessMillimeters / 2
            let rotation = rotationMatrix(for: pose.rotationEuler)

            let localVertices: [SIMD3<Float>] = [
                SIMD3<Float>(-halfSize, halfSize, halfThickness),
                SIMD3<Float>(halfSize, halfSize, halfThickness),
                SIMD3<Float>(halfSize, -halfSize, halfThickness),
                SIMD3<Float>(-halfSize, -halfSize, halfThickness),
                SIMD3<Float>(-halfSize, halfSize, -halfThickness),
                SIMD3<Float>(halfSize, halfSize, -halfThickness),
                SIMD3<Float>(halfSize, -halfSize, -halfThickness),
                SIMD3<Float>(-halfSize, -halfSize, -halfThickness)
            ]

            vertices += localVertices.map { (rotation * $0) + pose.translation }
            faces += cubeFaces(startingAt: startIndex)
        }

        return Mesh3D(vertices: vertices, faces: faces)
    }

    private func cubeFaces(startingAt startIndex: Int) -> [SIMD3<Int>] {
        [
            SIMD3<Int>(startIndex + 0, startIndex + 1, startIndex + 2),
            SIMD3<Int>(startIndex + 0, startIndex + 2, startIndex + 3),
            SIMD3<Int>(startIndex + 4, startIndex + 6, startIndex + 5),
            SIMD3<Int>(startIndex + 4, startIndex + 7, startIndex + 6),
            SIMD3<Int>(startIndex + 0, startIndex + 4, startIndex + 5),
            SIMD3<Int>(startIndex + 0, startIndex + 5, startIndex + 1),
            SIMD3<Int>(startIndex + 3, startIndex + 2, startIndex + 6),
            SIMD3<Int>(startIndex + 3, startIndex + 6, startIndex + 7),
            SIMD3<Int>(startIndex + 0, startIndex + 3, startIndex + 7),
            SIMD3<Int>(startIndex + 0, startIndex + 7, startIndex + 4),
            SIMD3<Int>(startIndex + 1, startIndex + 5, startIndex + 6),
            SIMD3<Int>(startIndex + 1, startIndex + 6, startIndex + 2)
        ]
    }

    private func rotationMatrix(for euler: SIMD3<Float>) -> simd_float3x3 {
        let cx = cos(euler.x)
        let sx = sin(euler.x)
        let cy = cos(euler.y)
        let sy = sin(euler.y)
        let cz = cos(euler.z)
        let sz = sin(euler.z)

        let rx = simd_float3x3(
            SIMD3<Float>(1, 0, 0),
            SIMD3<Float>(0, cx, sx),
            SIMD3<Float>(0, -sx, cx)
        )

        let ry = simd_float3x3(
            SIMD3<Float>(cy, 0, -sy),
            SIMD3<Float>(0, 1, 0),
            SIMD3<Float>(sy, 0, cy)
        )

        let rz = simd_float3x3(
            SIMD3<Float>(cz, sz, 0),
            SIMD3<Float>(-sz, cz, 0),
            SIMD3<Float>(0, 0, 1)
        )

        return rz * ry * rx
    }
}
