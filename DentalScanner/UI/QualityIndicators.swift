import DentalScannerKit
import SwiftUI

struct QualityIndicators: View {
    let qualityScore: Float
    let validFrames: Int
    let visibleMarkerCount: Int
    let latestMetrics: FrameQualityMetrics

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                MetricCard(title: "Qualidade", value: "\(Int(qualityScore)) / 100")
                MetricCard(title: "Frames", value: "\(validFrames)")
                MetricCard(title: "Tags", value: "\(visibleMarkerCount)")
            }

            HStack(spacing: 12) {
                MetricCard(title: "Sharpness", value: String(format: "%.0f", latestMetrics.sharpnessScore))
                MetricCard(title: "Overlap", value: "\(Int(latestMetrics.overlapEstimate * 100))%")
                MetricCard(title: "Blur", value: String(format: "%.2f", latestMetrics.motionBlurScore))
            }
        }
    }
}

private struct MetricCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

