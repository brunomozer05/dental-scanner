import CoreGraphics
import Foundation

public struct TagValidatorConfiguration: Equatable {
    public var minimumVisibleTags: Int
    public var maximumScaleDeviation: Double
    public var requirePoseEstimate: Bool

    public init(
        minimumVisibleTags: Int = 4,
        maximumScaleDeviation: Double = 0.08,
        requirePoseEstimate: Bool = true
    ) {
        self.minimumVisibleTags = minimumVisibleTags
        self.maximumScaleDeviation = maximumScaleDeviation
        self.requirePoseEstimate = requirePoseEstimate
    }
}

public final class TagValidator {
    public let configuration: TagValidatorConfiguration

    public init(configuration: TagValidatorConfiguration = TagValidatorConfiguration()) {
        self.configuration = configuration
    }

    public func validate(_ markers: [DetectedMarker]) -> TagValidationResult {
        var issues: [String] = []

        if markers.count < configuration.minimumVisibleTags {
            issues.append("Poucas tags visiveis: \(markers.count)/\(configuration.minimumVisibleTags).")
        }

        let duplicateIDs = Dictionary(grouping: markers, by: \.id).filter { $1.count > 1 }.keys.sorted()
        if !duplicateIDs.isEmpty {
            issues.append("IDs duplicados detectados: \(duplicateIDs.map(String.init).joined(separator: ", ")).")
        }

        if configuration.requirePoseEstimate, markers.contains(where: { $0.pose == nil }) {
            issues.append("Uma ou mais tags nao retornaram pose 6DoF.")
        }

        let edgeLengths = markers.flatMap(\.corners).isEmpty
            ? []
            : markers.compactMap(averageEdgeLength(for:))

        let meanEdgeLength = edgeLengths.isEmpty ? 0 : edgeLengths.reduce(0, +) / Double(edgeLengths.count)

        if edgeLengths.count > 1, meanEdgeLength > 0 {
            let maxDeviation = edgeLengths.map { abs($0 - meanEdgeLength) / meanEdgeLength }.max() ?? 0
            if maxDeviation > configuration.maximumScaleDeviation {
                issues.append("Variacao de escala entre tags acima de \(Int(configuration.maximumScaleDeviation * 100))%.")
            }
        }

        return TagValidationResult(
            isValid: issues.isEmpty,
            issues: issues,
            visibleTags: markers.count,
            meanEdgeLengthPixels: meanEdgeLength
        )
    }

    private func averageEdgeLength(for marker: DetectedMarker) -> Double? {
        guard marker.corners.count == 4 else {
            return nil
        }

        let perimeter = zip(marker.corners, marker.corners.shiftedLeft()).map { lhs, rhs in
            lhs.distance(to: rhs)
        }.reduce(0, +)

        return perimeter / 4
    }
}

private extension Array {
    func shiftedLeft() -> [Element] {
        guard let first else {
            return []
        }

        return Array(dropFirst()) + [first]
    }
}

private extension CGPoint {
    func distance(to other: CGPoint) -> Double {
        let dx = x - other.x
        let dy = y - other.y
        return sqrt(Double(dx * dx + dy * dy))
    }
}
