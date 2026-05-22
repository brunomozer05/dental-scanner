import Foundation
import SwiftUI

struct ScanDistanceGuideConfiguration: Equatable {
    let minimumDistanceMm: Double
    let idealMinimumDistanceMm: Double
    let idealMaximumDistanceMm: Double
    let maximumDistanceMm: Double

    static let `default` = ScanDistanceGuideConfiguration(
        minimumDistanceMm: 80,
        idealMinimumDistanceMm: 100,
        idealMaximumDistanceMm: 140,
        maximumDistanceMm: 170
    )
}

struct ScanDistanceGuideView: View {
    let distanceMm: Double?
    let configuration: ScanDistanceGuideConfiguration
    let isSourceReliable: Bool
    let statusText: String?

    private let trackHeight: CGFloat = 170
    private let trackWidth: CGFloat = 14
    private let indicatorDiameter: CGFloat = 22
    private let closeColor = Color(red: 0.94, green: 0.20, blue: 0.18)
    private let idealColor = Color(red: 0.18, green: 0.76, blue: 0.44)
    private let farColor = Color(red: 0.94, green: 0.20, blue: 0.18)

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .trailing, spacing: 3) {
                Text(formattedDistance)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(displayDistanceMm == nil ? 0.54 : 0.92))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(statusTitle)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(indicatorColor.opacity(displayDistanceMm == nil ? 0.62 : 0.95))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(width: 70, alignment: .trailing)

            distanceTrack
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(Color.black.opacity(0.60))
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityText))
    }

    private var distanceTrack: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: trackWidth / 2, style: .continuous)
                    .fill(trackGradient)
                    .frame(width: trackWidth)
                    .overlay {
                        RoundedRectangle(cornerRadius: trackWidth / 2, style: .continuous)
                            .stroke(Color.white.opacity(0.16), lineWidth: 1)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: trackWidth / 2, style: .continuous)
                            .fill(Color.black.opacity(displayDistanceMm == nil ? 0.30 : 0.08))
                    }

                Circle()
                    .fill(indicatorColor)
                    .frame(width: indicatorDiameter, height: indicatorDiameter)
                    .overlay {
                        Circle()
                            .stroke(Color.white.opacity(0.72), lineWidth: 1.2)
                    }
                    .shadow(
                        color: indicatorColor.opacity(effectiveDistanceMm == nil ? 0.0 : 0.42),
                        radius: 6,
                        x: 0,
                        y: 0
                    )
                    .position(
                        x: geometry.size.width / 2,
                        y: indicatorCenterY(in: geometry.size.height)
                    )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: indicatorDiameter, height: trackHeight)
        .animation(.easeOut(duration: 0.18), value: displayDistanceMm ?? -1)
    }

    private var trackGradient: LinearGradient {
        let idealTop = min(
            yLocation(for: configuration.idealMaximumDistanceMm),
            yLocation(for: configuration.idealMinimumDistanceMm)
        )
        let idealBottom = max(
            yLocation(for: configuration.idealMaximumDistanceMm),
            yLocation(for: configuration.idealMinimumDistanceMm)
        )

        return LinearGradient(
            stops: [
                Gradient.Stop(color: farColor.opacity(0.72), location: 0.0),
                Gradient.Stop(color: farColor.opacity(0.58), location: idealTop),
                Gradient.Stop(color: idealColor.opacity(0.88), location: idealTop),
                Gradient.Stop(color: idealColor.opacity(0.88), location: idealBottom),
                Gradient.Stop(color: closeColor.opacity(0.58), location: idealBottom),
                Gradient.Stop(color: closeColor.opacity(0.72), location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var formattedDistance: String {
        guard let displayDistanceMm, displayDistanceMm.isFinite else {
            return "-- mm"
        }

        return String(format: "%.0f mm", displayDistanceMm)
    }

    private var distanceState: DistanceState {
        guard let distanceMm, distanceMm.isFinite else {
            return .unavailable
        }

        guard isSourceReliable else {
            return .unreliable
        }

        if distanceMm < configuration.idealMinimumDistanceMm {
            return .tooClose
        }

        if distanceMm > configuration.idealMaximumDistanceMm {
            return .tooFar
        }

        return .ideal
    }

    private var statusTitle: String {
        guard let statusText,
              !statusText.isEmpty
        else {
            return distanceState.title
        }

        return statusText
    }

    private var indicatorColor: Color {
        switch distanceState {
        case .tooClose:
            return closeColor
        case .ideal:
            return idealColor
        case .tooFar:
            return farColor
        case .unavailable:
            return .white.opacity(0.34)
        case .unreliable:
            return .white.opacity(0.34)
        }
    }

    private var accessibilityText: String {
        guard isSourceReliable else {
            return "Distancia do scan sem confianca porque o frame atual esta ruim"
        }

        guard let distanceMm, distanceMm.isFinite else {
            return "Distancia do scan indisponivel"
        }

        return String(format: "Distancia do scan %.0f milimetros, %@", distanceMm, distanceState.title)
    }

    private func indicatorCenterY(in height: CGFloat) -> CGFloat {
        let inset = indicatorDiameter / 2
        let availableHeight = max(height - indicatorDiameter, 1)

        return inset + (1 - normalizedDistance) * availableHeight
    }

    private var normalizedDistance: CGFloat {
        guard let displayDistanceMm, displayDistanceMm.isFinite else {
            return 0.5
        }

        let clampedDistance = min(max(displayDistanceMm, minimumDistance), maximumDistance)
        return CGFloat((clampedDistance - minimumDistance) / distanceRange)
    }

    private var effectiveDistanceMm: Double? {
        guard isSourceReliable else {
            return nil
        }

        return distanceMm
    }

    private var displayDistanceMm: Double? {
        guard let distanceMm,
              distanceMm.isFinite
        else {
            return nil
        }

        return distanceMm
    }

    private func yLocation(for distanceMm: Double) -> CGFloat {
        let clampedDistance = min(max(distanceMm, minimumDistance), maximumDistance)
        let normalizedLocation = CGFloat((clampedDistance - minimumDistance) / distanceRange)

        return min(max(1 - normalizedLocation, 0), 1)
    }

    private var minimumDistance: Double {
        min(configuration.minimumDistanceMm, configuration.maximumDistanceMm)
    }

    private var maximumDistance: Double {
        max(configuration.minimumDistanceMm, configuration.maximumDistanceMm)
    }

    private var distanceRange: Double {
        max(maximumDistance - minimumDistance, 1)
    }

    private enum DistanceState {
        case tooClose
        case ideal
        case tooFar
        case unavailable
        case unreliable

        var title: String {
            switch self {
            case .tooClose:
                return "Muito perto"
            case .ideal:
                return "Ideal"
            case .tooFar:
                return "Muito longe"
            case .unavailable:
                return "Sem pose"
            case .unreliable:
                return "Qualidade ruim"
            }
        }
    }
}

#Preview {
    ZStack {
        Color.black
            .ignoresSafeArea()

        ScanDistanceGuideView(
            distanceMm: 118,
            configuration: .default,
            isSourceReliable: true,
            statusText: "Distancia ideal"
        )
    }
}
