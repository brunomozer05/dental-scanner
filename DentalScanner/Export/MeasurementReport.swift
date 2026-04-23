import Foundation

public final class MeasurementReportGenerator {
    public init() {}

    public func makeMarkdown(session: ScanSessionState, accuracy: AccuracyReport?) -> String {
        let coveredBuckets = session.guidance.coverageMap.filter { $0 }.count
        let coveragePercent = Double(coveredBuckets) / Double(max(session.guidance.coverageMap.count, 1)) * 100
        let trackedMarkers = session.reconstruction?.anchorMarkers ?? []
        let visibleMarkerIDs = session.guidance.tagVisibility.keys.sorted()

        var lines = [
            "# ArUco Marker Report",
            "",
            "## Session Summary",
            "- Stage: \(session.stage.rawValue)",
            "- Valid frames: \(session.guidance.validFrameCount)",
            "- Angular coverage: \(String(format: "%.1f", coveragePercent))%",
            "- Visible markers: \(visibleMarkerIDs.map(String.init).joined(separator: ", "))",
            "- Tracked markers in 3D: \(trackedMarkers.count)",
            "- Mesh vertices: \(session.mesh?.vertices.count ?? 0)",
            "- Mesh faces: \(session.mesh?.faces.count ?? 0)",
            "- STL purpose: representacao geometrica das poses fusionadas das tags ArUco"
        ]

        if !trackedMarkers.isEmpty {
            lines += [
                "",
                "## Marker Poses (mm)"
            ]

            lines += trackedMarkers.compactMap { marker in
                guard let pose = marker.pose else {
                    return nil
                }

                return String(
                    format: "- ID %d: x=%.2f y=%.2f z=%.2f rx=%.3f ry=%.3f rz=%.3f conf=%.2f",
                    marker.id,
                    pose.translation.x,
                    pose.translation.y,
                    pose.translation.z,
                    pose.rotationEuler.x,
                    pose.rotationEuler.y,
                    pose.rotationEuler.z,
                    marker.confidence
                )
            }
        }

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
