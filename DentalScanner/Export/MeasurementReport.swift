import Foundation

public final class MeasurementReportGenerator {
    public init() {}

    public func makeMarkdown(session: ScanSessionState, accuracy: AccuracyReport?) -> String {
        let coveredBuckets = session.guidance.coverageMap.filter { $0 }.count
        let coveragePercent = Double(coveredBuckets) / Double(max(session.guidance.coverageMap.count, 1)) * 100
        let visibleMarkerIDs = session.guidance.tagVisibility.keys.sorted()

        var lines = [
            "# Measurement Report",
            "",
            "## Session Summary",
            "- Stage: \(session.stage.rawValue)",
            "- Valid frames: \(session.guidance.validFrameCount)",
            "- Angular coverage: \(String(format: "%.1f", coveragePercent))%",
            "- Visible markers: \(visibleMarkerIDs.map(String.init).joined(separator: ", "))",
            "- Sparse points: \(session.reconstruction?.sparsePoints.count ?? 0)",
            "- Dense points: \(session.reconstruction?.densePoints.count ?? 0)",
            "- Mesh vertices: \(session.mesh?.vertices.count ?? 0)",
            "- Mesh faces: \(session.mesh?.faces.count ?? 0)"
        ]

        if let accuracy {
            lines += [
                "",
                "## Accuracy",
                "- RMS error: \(String(format: "%.2f", accuracy.rmsErrorMicrometers)) um",
                "- Mean error: \(String(format: "%.2f", accuracy.meanErrorMicrometers)) um",
                "- Max error: \(String(format: "%.2f", accuracy.maxErrorMicrometers)) um",
                "- Points within tolerance: \(String(format: "%.1f", accuracy.pointsWithinTolerancePercent))%"
            ]
        }

        lines += [
            "",
            "## Guidance",
            session.guidance.recommendations.map { "- \($0)" }.joined(separator: "\n")
        ]

        return lines.joined(separator: "\n")
    }
}

