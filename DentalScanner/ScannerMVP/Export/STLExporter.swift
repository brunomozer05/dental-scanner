import Foundation
import simd

struct STLExporter {
    struct Configuration {
        let cylinderRadiusMillimeters: Double
        let cylinderHeightMillimeters: Double
        let cylinderSegmentCount: Int

        static let initialImplantMarker = Configuration(
            cylinderRadiusMillimeters: 2.0,
            cylinderHeightMillimeters: 10.0,
            cylinderSegmentCount: 24
        )
    }

    enum ExportError: LocalizedError {
        case emptyImplantList
        case invalidConfiguration
        case unableToEncodeSTL

        var errorDescription: String? {
            switch self {
            case .emptyImplantList:
                return "Nenhum implante detectado para exportar."
            case .invalidConfiguration:
                return "Configuracao de cilindro STL invalida."
            case .unableToEncodeSTL:
                return "Nao foi possivel codificar o STL ASCII."
            }
        }
    }

    private let configuration: Configuration

    init(configuration: Configuration = .initialImplantMarker) {
        self.configuration = configuration
    }

    func writeASCIISTL(
        for implantPoses: [ImplantPose],
        to fileURL: URL,
        solidName: String = "dental_implants"
    ) throws {
        let stl = try makeASCIISTL(for: implantPoses, solidName: solidName)
        guard let data = stl.data(using: .utf8) else {
            throw ExportError.unableToEncodeSTL
        }

        try data.write(to: fileURL, options: .atomic)
    }

    func makeASCIISTL(
        for implantPoses: [ImplantPose],
        solidName: String = "dental_implants"
    ) throws -> String {
        guard !implantPoses.isEmpty else {
            throw ExportError.emptyImplantList
        }

        guard configuration.cylinderRadiusMillimeters.isFinite,
              configuration.cylinderRadiusMillimeters > 0,
              configuration.cylinderHeightMillimeters.isFinite,
              configuration.cylinderHeightMillimeters > 0,
              configuration.cylinderSegmentCount >= 8
        else {
            throw ExportError.invalidConfiguration
        }

        var triangles: [Triangle] = []
        for implantPose in implantPoses.sorted(by: { $0.markerId < $1.markerId }) {
            triangles.append(contentsOf: cylinderTriangles(for: implantPose))
        }

        var lines: [String] = []
        lines.reserveCapacity(triangles.count * 7 + 2)
        lines.append("solid \(solidName)")

        for triangle in triangles {
            let normal = triangle.normal
            lines.append("  facet normal \(format(normal.x)) \(format(normal.y)) \(format(normal.z))")
            lines.append("    outer loop")
            lines.append("      vertex \(format(triangle.a.x)) \(format(triangle.a.y)) \(format(triangle.a.z))")
            lines.append("      vertex \(format(triangle.b.x)) \(format(triangle.b.y)) \(format(triangle.b.z))")
            lines.append("      vertex \(format(triangle.c.x)) \(format(triangle.c.y)) \(format(triangle.c.z))")
            lines.append("    endloop")
            lines.append("  endfacet")
        }

        lines.append("endsolid \(solidName)")
        return lines.joined(separator: "\n") + "\n"
    }

    private func cylinderTriangles(for implantPose: ImplantPose) -> [Triangle] {
        let segmentCount = configuration.cylinderSegmentCount
        let radius = configuration.cylinderRadiusMillimeters
        let halfHeight = configuration.cylinderHeightMillimeters / 2.0
        let bottomCenter = worldPoint(SIMD3(0.0, 0.0, -halfHeight), using: implantPose)
        let topCenter = worldPoint(SIMD3(0.0, 0.0, halfHeight), using: implantPose)

        var bottomRing: [SIMD3<Double>] = []
        var topRing: [SIMD3<Double>] = []
        bottomRing.reserveCapacity(segmentCount)
        topRing.reserveCapacity(segmentCount)

        for segmentIndex in 0..<segmentCount {
            let angle = Double(segmentIndex) / Double(segmentCount) * 2.0 * Double.pi
            let x = cos(angle) * radius
            let y = sin(angle) * radius
            bottomRing.append(worldPoint(SIMD3(x, y, -halfHeight), using: implantPose))
            topRing.append(worldPoint(SIMD3(x, y, halfHeight), using: implantPose))
        }

        var triangles: [Triangle] = []
        triangles.reserveCapacity(segmentCount * 4)

        for segmentIndex in 0..<segmentCount {
            let nextIndex = (segmentIndex + 1) % segmentCount
            let bottomA = bottomRing[segmentIndex]
            let bottomB = bottomRing[nextIndex]
            let topA = topRing[segmentIndex]
            let topB = topRing[nextIndex]

            triangles.append(Triangle(bottomA, bottomB, topB))
            triangles.append(Triangle(bottomA, topB, topA))
            triangles.append(Triangle(topCenter, topA, topB))
            triangles.append(Triangle(bottomCenter, bottomB, bottomA))
        }

        return triangles
    }

    private func worldPoint(_ localPoint: SIMD3<Double>, using implantPose: ImplantPose) -> SIMD3<Double> {
        implantPose.rotationMatrix * localPoint + implantPose.translationVector
    }

    private func format(_ value: Double) -> String {
        String(
            format: "%.6f",
            locale: Locale(identifier: "en_US_POSIX"),
            arguments: [value]
        )
    }

    private struct Triangle {
        let a: SIMD3<Double>
        let b: SIMD3<Double>
        let c: SIMD3<Double>

        init(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ c: SIMD3<Double>) {
            self.a = a
            self.b = b
            self.c = c
        }

        var normal: SIMD3<Double> {
            let crossProduct = simd_cross(b - a, c - a)
            let length = simd_length(crossProduct)
            guard length.isFinite, length > 1e-9 else {
                return .zero
            }

            return crossProduct / length
        }
    }
}
