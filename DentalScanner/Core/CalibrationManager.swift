import Foundation

public struct CalibrationPolicy: Equatable {
    public var recommendedSampleRange: ClosedRange<Int>
    public var maximumReprojectionErrorPixels: Double
    public var checkerboardColumns: Int
    public var checkerboardRows: Int

    public init(
        recommendedSampleRange: ClosedRange<Int> = 30...50,
        maximumReprojectionErrorPixels: Double = 0.3,
        checkerboardColumns: Int = 10,
        checkerboardRows: Int = 7
    ) {
        self.recommendedSampleRange = recommendedSampleRange
        self.maximumReprojectionErrorPixels = maximumReprojectionErrorPixels
        self.checkerboardColumns = checkerboardColumns
        self.checkerboardRows = checkerboardRows
    }
}

public struct CalibrationEvaluation: Equatable {
    public var isAcceptable: Bool
    public var recommendations: [String]
    public var sampleCount: Int
    public var averageReprojectionErrorPixels: Double

    public init(
        isAcceptable: Bool,
        recommendations: [String],
        sampleCount: Int,
        averageReprojectionErrorPixels: Double
    ) {
        self.isAcceptable = isAcceptable
        self.recommendations = recommendations
        self.sampleCount = sampleCount
        self.averageReprojectionErrorPixels = averageReprojectionErrorPixels
    }
}

public final class CalibrationManager {
    public let policy: CalibrationPolicy
    private let storageURL: URL

    public init(storageURL: URL? = nil, policy: CalibrationPolicy = CalibrationPolicy()) {
        self.policy = policy

        if let storageURL {
            self.storageURL = storageURL
        } else {
            let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            self.storageURL = directory.appendingPathComponent("camera-calibration.json")
        }
    }

    public func evaluate(samples: [CalibrationSample], intrinsics: CameraIntrinsics) -> CalibrationEvaluation {
        let averageError = samples.isEmpty
            ? intrinsics.reprojectionErrorPixels
            : samples.map(\.reprojectionErrorPixels).reduce(0, +) / Double(samples.count)

        var recommendations: [String] = []

        if !policy.recommendedSampleRange.contains(samples.count) {
            recommendations.append("Colete entre \(policy.recommendedSampleRange.lowerBound) e \(policy.recommendedSampleRange.upperBound) imagens de calibracao.")
        }

        if averageError > policy.maximumReprojectionErrorPixels {
            recommendations.append("Reduza o erro de reprojecao para menos de \(policy.maximumReprojectionErrorPixels) px antes de capturas clinicas.")
        }

        if samples.contains(where: { $0.detectedCorners < policy.checkerboardColumns * policy.checkerboardRows }) {
            recommendations.append("Garanta deteccao completa do tabuleiro \(policy.checkerboardColumns)x\(policy.checkerboardRows) em todos os frames.")
        }

        return CalibrationEvaluation(
            isAcceptable: recommendations.isEmpty,
            recommendations: recommendations,
            sampleCount: samples.count,
            averageReprojectionErrorPixels: averageError
        )
    }

    public func persist(_ intrinsics: CameraIntrinsics) throws {
        let parentDirectory = storageURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDirectory, withIntermediateDirectories: true, attributes: nil)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(intrinsics)
        try data.write(to: storageURL, options: .atomic)
    }

    public func loadPersistedCalibration() throws -> CameraIntrinsics? {
        guard FileManager.default.fileExists(atPath: storageURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: storageURL)
        return try JSONDecoder().decode(CameraIntrinsics.self, from: data)
    }

    public func makeChecklist() -> [String] {
        [
            "Imprimir padrao xadrez \(policy.checkerboardColumns)x\(policy.checkerboardRows) com escala verificada.",
            "Coletar \(policy.recommendedSampleRange.lowerBound)-\(policy.recommendedSampleRange.upperBound) imagens em angulos variados.",
            "Validar erro medio de reprojecao abaixo de \(policy.maximumReprojectionErrorPixels) px.",
            "Persistir a calibracao e associar ao dispositivo utilizado."
        ]
    }
}
