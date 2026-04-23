import SwiftUI

struct CaptureView: View {
    @ObservedObject var viewModel: CaptureViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                GroupBox("Estado da Sessao") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(viewModel.stage.rawValue.capitalized)
                            .font(.title3.weight(.semibold))
                        Text("Cobertura angular: \(Int(viewModel.coverageFraction * 100))%")
                            .foregroundStyle(.secondary)
                        ProgressView(value: viewModel.coverageFraction)
                    }
                }

                QualityIndicators(
                    qualityScore: viewModel.guidance.qualityScore,
                    validFrames: viewModel.guidance.validFrameCount,
                    visibleMarkerCount: viewModel.visibleMarkerCount,
                    latestMetrics: viewModel.latestMetrics
                )

                GroupBox("Mapa de Cobertura") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 10) {
                        ForEach(Array(viewModel.guidance.coverageMap.enumerated()), id: \.offset) { entry in
                            Circle()
                                .fill(entry.element ? Color.green : Color.gray.opacity(0.25))
                                .frame(height: 18)
                        }
                    }
                    .padding(.vertical, 4)
                }

                GroupBox("Tags Visiveis") {
                    if viewModel.visibleMarkerIDs.isEmpty {
                        Text("Nenhuma tag detectada no ultimo frame.")
                            .foregroundStyle(.secondary)
                    } else {
                        HStack {
                            ForEach(viewModel.visibleMarkerIDs, id: \.self) { markerID in
                                Text("ID \(markerID)")
                                    .font(.caption.weight(.medium))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.blue.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }

                GroupBox("Recomendacoes") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(viewModel.guidance.recommendations, id: \.self) { recommendation in
                            Text("- \(recommendation)")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }

                HStack(spacing: 12) {
                    Button("Nova Sessao") {
                        viewModel.startNewSession()
                    }
                    .buttonStyle(.bordered)

                    Button("Adicionar Frame Demo") {
                        viewModel.addDemoFrame()
                    }
                    .buttonStyle(.borderedProminent)
                }

                Button("Gerar STL das Tags") {
                    viewModel.reconstruct()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canReconstruct)
            }
            .padding()
        }
        .navigationTitle("Captura ArUco")
    }
}
