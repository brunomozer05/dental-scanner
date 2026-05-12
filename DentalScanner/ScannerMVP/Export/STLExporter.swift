import Foundation
import simd

struct STLExporter {
    enum ReferenceMarkerModel {
        case markerV1
        case markerV2

        var fileName: String {
            switch self {
            case .markerV1:
                return "marker_reference"
            case .markerV2:
                return "marker_reference_2"
            }
        }
    }

    struct Configuration {
        let referenceModel: ReferenceMarkerModel
        let referenceModelScale: Double
        let referenceModelTopTagCenterInModelMillimeters: SIMD3<Double>
        let referenceModelBottomTagCenterInModelMillimeters: SIMD3<Double>?
        let bottomTagSizeMillimeters: Double?
        let bottomTagCenterInMarkerMillimeters: SIMD3<Double>?
        let referenceModelFlipZ: Bool
        let referenceModelLocalRotation: simd_quatd

        var referenceModelFileName: String {
            referenceModel.fileName
        }

        static func referenceMarker(for markerProfile: MarkerProfile) -> Configuration {
            switch markerProfile {
            case .singleArucoV1:
                return .markerReferenceV1
            case .dualArucoV2:
                return .markerReferenceV2
            }
        }

        static let markerReferenceV1 = Configuration(
            referenceModel: .markerV1,
            referenceModelScale: 1.0,
            referenceModelTopTagCenterInModelMillimeters: SIMD3<Double>(4.0, -1.45, 13.55),
            referenceModelBottomTagCenterInModelMillimeters: nil,
            bottomTagSizeMillimeters: nil,
            bottomTagCenterInMarkerMillimeters: nil,
            referenceModelFlipZ: false,
            referenceModelLocalRotation: simd_quatd(
                angle: 0.0,
                axis: SIMD3<Double>(0.0, 0.0, 1.0)
            )
        )

        // marker_reference_2.stl places the tag boxes on the X = -17 plane.
        // Y is horizontal, Z is vertical, so these centers map to (0, 0, 0)
        // for the top 8 mm tag and (0, -7.75, 0) for the bottom 6.5 mm tag.
        static let markerReferenceV2 = Configuration(
            referenceModel: .markerV2,
            referenceModelScale: 1.0,
            referenceModelTopTagCenterInModelMillimeters: SIMD3<Double>(-17.0, 17.0, 15.0),
            referenceModelBottomTagCenterInModelMillimeters: SIMD3<Double>(-17.0, 17.0, 7.25),
            bottomTagSizeMillimeters: 6.5,
            bottomTagCenterInMarkerMillimeters: SIMD3<Double>(0.0, -7.75, 0.0),
            referenceModelFlipZ: false,
            referenceModelLocalRotation: simd_quatd(
                angle: 0.0,
                axis: SIMD3<Double>(0.0, 0.0, 1.0)
            )
        )

        static let markerReference = markerReferenceV1
    }

    enum ExportError: LocalizedError {
        case emptyImplantList
        case emptyTagPoseList
        case invalidConfiguration
        case missingReferenceModel(fileName: String)
        case emptyReferenceModel
        case invalidReferenceModel
        case unableToEncodeSTL

        var errorDescription: String? {
            switch self {
            case .emptyImplantList:
                return "Nenhum implante detectado para exportar."
            case .emptyTagPoseList:
                return "Nenhuma pose de tag detectada para exportar."
            case .invalidConfiguration:
                return "Configuracao do modelo STL invalida."
            case let .missingReferenceModel(fileName):
                return "Nao foi possivel encontrar \(fileName).stl no bundle."
            case .emptyReferenceModel:
                return "O STL de referencia nao contem triangulos."
            case .invalidReferenceModel:
                return "O STL de referencia nao esta em um formato suportado."
            case .unableToEncodeSTL:
                return "Nao foi possivel codificar o STL ASCII."
            }
        }
    }

    private let configuration: Configuration
    private static let referenceModelCacheLock = NSLock()
    private static var cachedReferenceModelTrianglesByFileName: [String: [Triangle]] = [:]

    init(configuration: Configuration = .markerReference) {
        self.configuration = configuration
    }

    func reconfigured(with configuration: Configuration) -> STLExporter {
        STLExporter(configuration: configuration)
    }

    var referenceModelFileName: String {
        "\(configuration.referenceModelFileName).stl"
    }

    var bottomTagSizeMillimeters: Double? {
        configuration.bottomTagSizeMillimeters
    }

    var bottomTagCenterYMillimeters: Double? {
        configuration.bottomTagCenterInMarkerMillimeters?.y
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

        try validateConfiguration()

        let referenceTriangles = try loadReferenceModelTriangles()
        var triangles: [Triangle] = []
        triangles.reserveCapacity(referenceTriangles.count * implantPoses.count)

        for implantPose in implantPoses.sorted(by: { $0.markerId < $1.markerId }) {
            triangles.append(contentsOf: transformedReferenceTriangles(
                referenceTriangles,
                using: implantPose
            ))
        }

        return makeASCIISTL(from: triangles, solidName: solidName)
    }

    func exportReferenceMarkersAsSTL(
        tagPoses: [PoseResult],
        solidName: String = "dental_reference_markers"
    ) throws -> String {
        guard !tagPoses.isEmpty else {
            throw ExportError.emptyTagPoseList
        }

        try validateConfiguration()

        let referenceTriangles = try loadReferenceModelTriangles()
        var triangles: [Triangle] = []
        triangles.reserveCapacity(referenceTriangles.count * tagPoses.count)

        for tagPose in tagPoses.sorted(by: { $0.markerId < $1.markerId }) {
            triangles.append(contentsOf: transformedReferenceTriangles(
                referenceTriangles,
                using: tagPose
            ))
        }

        return makeASCIISTL(from: triangles, solidName: solidName)
    }

    private func makeASCIISTL(from triangles: [Triangle], solidName: String) -> String {
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

    private func transformedReferenceTriangles(
        _ referenceTriangles: [Triangle],
        using implantPose: ImplantPose
    ) -> [Triangle] {
        var triangles: [Triangle] = []
        triangles.reserveCapacity(referenceTriangles.count)

        for referenceTriangle in referenceTriangles {
            triangles.append(Triangle(
                worldPoint(referenceTriangle.a, using: implantPose),
                worldPoint(referenceTriangle.b, using: implantPose),
                worldPoint(referenceTriangle.c, using: implantPose)
            ))
        }

        return triangles
    }

    private func transformedReferenceTriangles(
        _ referenceTriangles: [Triangle],
        using tagPose: PoseResult
    ) -> [Triangle] {
        var triangles: [Triangle] = []
        triangles.reserveCapacity(referenceTriangles.count)

        for referenceTriangle in referenceTriangles {
            triangles.append(Triangle(
                worldPoint(referenceTriangle.a, using: tagPose),
                worldPoint(referenceTriangle.b, using: tagPose),
                worldPoint(referenceTriangle.c, using: tagPose)
            ))
        }

        return triangles
    }

    private func worldPoint(_ localPoint: SIMD3<Double>, using tagPose: PoseResult) -> SIMD3<Double> {
        tagPose.translationVector + tagPose.rotationMatrix * tagLocalPoint(from: localPoint)
    }

    private func worldPoint(_ localPoint: SIMD3<Double>, using implantPose: ImplantPose) -> SIMD3<Double> {
        implantPose.translationVector + implantPose.rotationMatrix * tagLocalPoint(from: localPoint)
    }

    private func tagLocalPoint(from localPoint: SIMD3<Double>) -> SIMD3<Double> {
        let scaledPoint = localPoint * configuration.referenceModelScale
        let relative = scaledPoint - configuration.referenceModelTopTagCenterInModelMillimeters
        // Existing STL model axes: model Y -> marker -X, model Z -> marker Y, model X -> marker Z.
        var tagLocalPoint = SIMD3<Double>(
            -relative.y,
            relative.z,
            relative.x
        )

        if configuration.referenceModelFlipZ {
            tagLocalPoint.z *= -1
        }

        return simd_double3x3(configuration.referenceModelLocalRotation) * tagLocalPoint
    }

    private func loadReferenceModelTriangles() throws -> [Triangle] {
        if let cachedTriangles = cachedReferenceModelTriangles() {
            return cachedTriangles
        }

        let triangles = try loadReferenceModelTrianglesFromBundle()

        Self.referenceModelCacheLock.lock()
        if let cachedTriangles = Self.cachedReferenceModelTrianglesByFileName[configuration.referenceModelFileName] {
            Self.referenceModelCacheLock.unlock()
            return cachedTriangles
        }

        Self.cachedReferenceModelTrianglesByFileName[configuration.referenceModelFileName] = triangles
        Self.referenceModelCacheLock.unlock()

        return triangles
    }

    private func cachedReferenceModelTriangles() -> [Triangle]? {
        Self.referenceModelCacheLock.lock()
        let triangles = Self.cachedReferenceModelTrianglesByFileName[configuration.referenceModelFileName]
        Self.referenceModelCacheLock.unlock()
        return triangles
    }

    private func loadReferenceModelTrianglesFromBundle() throws -> [Triangle] {
        let url = try referenceModelURL()
        let data = try Data(contentsOf: url)

        if let binaryTriangles = try parseBinarySTL(data) {
            return binaryTriangles
        }

        guard let contents = String(data: data, encoding: .utf8) else {
            throw ExportError.invalidReferenceModel
        }

        return try parseASCIISTL(contents)
    }

    private func referenceModelURL() throws -> URL {
        let fileName = configuration.referenceModelFileName

        if let url = Bundle.main.url(forResource: fileName, withExtension: "stl") {
            return url
        }

        if let url = Bundle.main.url(
            forResource: fileName,
            withExtension: "stl",
            subdirectory: "Models"
        ) {
            return url
        }

        throw ExportError.missingReferenceModel(fileName: fileName)
    }

    private func validateConfiguration() throws {
        guard configuration.referenceModelScale.isFinite,
              configuration.referenceModelScale > 0,
              isFinite(configuration.referenceModelTopTagCenterInModelMillimeters),
              configuration.referenceModelBottomTagCenterInModelMillimeters.map({ isFinite($0) }) ?? true,
              configuration.bottomTagSizeMillimeters.map({ $0.isFinite && $0 > 0 }) ?? true,
              configuration.bottomTagCenterInMarkerMillimeters.map({ isFinite($0) }) ?? true
        else {
            throw ExportError.invalidConfiguration
        }
    }

    private func parseBinarySTL(_ data: Data) throws -> [Triangle]? {
        guard data.count >= 84 else {
            return nil
        }

        let triangleCount = Int(readUInt32LittleEndian(data, at: 80))
        guard triangleCount > 0,
              triangleCount <= (Int.max - 84) / 50,
              84 + triangleCount * 50 == data.count
        else {
            return nil
        }

        var triangles: [Triangle] = []
        triangles.reserveCapacity(triangleCount)

        var offset = 84
        for _ in 0..<triangleCount {
            offset += 12
            let a = readVector(data, at: offset)
            offset += 12
            let b = readVector(data, at: offset)
            offset += 12
            let c = readVector(data, at: offset)
            offset += 12
            offset += 2

            triangles.append(Triangle(a, b, c))
        }

        guard !triangles.isEmpty else {
            throw ExportError.emptyReferenceModel
        }

        return triangles
    }

    private func parseASCIISTL(_ contents: String) throws -> [Triangle] {
        var pendingTriangleVertices: [SIMD3<Double>] = []
        var triangles: [Triangle] = []

        for line in contents.components(separatedBy: .newlines) {
            let parts = line.split(whereSeparator: \.isWhitespace)
            guard parts.count >= 4,
                  parts[0].lowercased() == "vertex",
                  let x = Double(String(parts[1])),
                  let y = Double(String(parts[2])),
                  let z = Double(String(parts[3]))
            else {
                continue
            }

            pendingTriangleVertices.append(SIMD3(x, y, z))

            guard pendingTriangleVertices.count == 3 else {
                continue
            }

            triangles.append(Triangle(
                pendingTriangleVertices[0],
                pendingTriangleVertices[1],
                pendingTriangleVertices[2]
            ))
            pendingTriangleVertices.removeAll(keepingCapacity: true)
        }

        guard !triangles.isEmpty else {
            throw ExportError.emptyReferenceModel
        }

        return triangles
    }

    private func readVector(_ data: Data, at offset: Int) -> SIMD3<Double> {
        SIMD3(
            Double(readFloat32LittleEndian(data, at: offset)),
            Double(readFloat32LittleEndian(data, at: offset + 4)),
            Double(readFloat32LittleEndian(data, at: offset + 8))
        )
    }

    private func readFloat32LittleEndian(_ data: Data, at offset: Int) -> Float {
        Float(bitPattern: readUInt32LittleEndian(data, at: offset))
    }

    private func readUInt32LittleEndian(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset]) |
            UInt32(data[offset + 1]) << 8 |
            UInt32(data[offset + 2]) << 16 |
            UInt32(data[offset + 3]) << 24
    }

    private func isFinite(_ vector: SIMD3<Double>) -> Bool {
        vector.x.isFinite && vector.y.isFinite && vector.z.isFinite
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
