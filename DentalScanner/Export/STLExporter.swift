import Foundation
import simd

public final class STLExporter {
    public init() {}

    public func exportASCII(mesh: Mesh3D, name: String = "DentalScannerMesh") -> String {
        var lines = ["solid \(name)"]

        for face in mesh.faces {
            let normal = faceNormal(face, vertices: mesh.vertices)
            let a = mesh.vertices[face.x]
            let b = mesh.vertices[face.y]
            let c = mesh.vertices[face.z]

            lines.append("  facet normal \(normal.x) \(normal.y) \(normal.z)")
            lines.append("    outer loop")
            lines.append("      vertex \(a.x) \(a.y) \(a.z)")
            lines.append("      vertex \(b.x) \(b.y) \(b.z)")
            lines.append("      vertex \(c.x) \(c.y) \(c.z)")
            lines.append("    endloop")
            lines.append("  endfacet")
        }

        lines.append("endsolid \(name)")
        return lines.joined(separator: "\n")
    }

    public func writeASCII(mesh: Mesh3D, name: String = "DentalScannerMesh", to url: URL) throws {
        let contents = exportASCII(mesh: mesh, name: name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private func faceNormal(_ face: SIMD3<Int>, vertices: [SIMD3<Float>]) -> SIMD3<Float> {
        let a = vertices[face.x]
        let b = vertices[face.y]
        let c = vertices[face.z]
        let normal = simd_cross(b - a, c - a)
        let length = simd_length(normal)
        return length > 0 ? normal / length : SIMD3<Float>(0, 0, 1)
    }
}

