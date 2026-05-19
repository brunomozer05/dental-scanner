import SwiftUI

struct ScannerDebugPanelView: View {
    let snapshot: ScannerDebugSnapshot
    let onClose: () -> Void

    private let enableMotionDebugSection = false
    private let enableNormalDebugSection = false
    private let enableStaticStabilityDebugSection = false
    private let enablePlanarDebugSection = false
    private let enableQualityDebugSection = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Scanner Debug")
                        .font(.headline)

                    Text("SAFE DEBUG PANEL 88dae22")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.62))
                }

                Spacer()

                Button("Fechar", action: onClose)
                    .buttonStyle(.plain)
                    .font(.caption.weight(.semibold))
            }

            debugSection(title: "Estado") {
                debugRow(title: "Estado", value: snapshot.state.scanState)
                debugRow(title: "Perfil marker", value: snapshot.state.markerProfile)
                debugRow(title: "Readiness", value: snapshot.state.readinessMessage)
                debugRow(title: "Markers atuais", value: snapshot.state.currentMarkerCount)
            }

            debugSection(title: "Export STL") {
                debugRow(title: "Gerando STL", value: snapshot.export.isGeneratingSTL)
                debugRow(title: "STL URL existe", value: snapshot.export.stlURLExists)
                debugRow(title: "STL existe", value: snapshot.export.stlFileExists)
                debugRow(title: "Erro STL", value: snapshot.export.stlError)
                debugRow(title: "tagPoses atuais", value: snapshot.export.currentExportableTagPoseCount)
                debugRow(title: "Ultimo export poses", value: snapshot.export.lastSTLExportPoseCount)
            }

            debugSection(title: "Readiness") {
                debugRow(title: "coverageReady", value: snapshot.readiness.coverageReady)
                debugRow(title: "goodFramesReady", value: snapshot.readiness.goodFramesReady)
                debugRow(title: "reprojectionReady", value: snapshot.readiness.reprojectionReady)
                debugRow(title: "distanceReady", value: snapshot.readiness.distanceReady)
                debugRow(title: "jitterReady", value: snapshot.readiness.jitterReady)
                debugRow(title: "stableReady", value: snapshot.readiness.stableReady)
                debugRow(title: "currentFrameGood", value: snapshot.readiness.currentFrameGood)
            }

            debugSection(title: "Config") {
                debugRow(title: "Perfil marker", value: snapshot.configuration.markerProfile)
                debugRow(title: "Barra distancia", value: snapshot.configuration.showDistanceGuide)
                debugRow(title: "Cobertura angular", value: snapshot.configuration.requiredAngularCoverage)
                debugRow(title: "Frames dual min", value: snapshot.configuration.minimumDualTagFrames)
                debugRow(title: "Cobertura dual", value: snapshot.configuration.minimumDualAngularCoverage)
                debugRow(title: "Precision v2", value: snapshot.configuration.precisionModeV2)
            }

            if snapshot.isDualArucoV2 {
                debugSection(title: "Marker v2 basico") {
                    if snapshot.markerV2Rows.isEmpty {
                        debugRow(title: "Markers v2", value: "Sem dados v2 ainda")
                    } else {
                        ForEach(snapshot.markerV2Rows) { marker in
                            debugRow(
                                title: "M\(marker.markerId)",
                                value: "Dual \(marker.dualFrames), Top \(marker.topFallbackFrames), Bottom \(marker.bottomFallbackFrames), \(marker.dualPercent)"
                            )
                        }
                    }
                }
            }

            if enableMotionDebugSection ||
                enableNormalDebugSection ||
                enableStaticStabilityDebugSection ||
                enablePlanarDebugSection ||
                enableQualityDebugSection {
                debugSection(title: "Avancado") {
                    debugRow(title: "Status", value: "Secoes avancadas desligadas")
                }
            }
        }
        .padding(12)
        .foregroundStyle(.white)
        .background(Color.black.opacity(0.90))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onAppear {
            print("[DEBUG_GEAR] rendering rebuilt scanner debug panel")
        }
    }

    private func debugSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white.opacity(0.86))

            content()
        }
        .padding(.top, 3)
    }

    private func debugRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .foregroundStyle(.white.opacity(0.58))

            Spacer(minLength: 8)

            Text(value.isEmpty ? ScannerDebugSnapshot.missingValue : value)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .monospacedDigit()
        }
        .font(.caption2.weight(.semibold))
    }
}
