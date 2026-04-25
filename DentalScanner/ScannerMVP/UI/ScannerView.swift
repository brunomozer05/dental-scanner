import SwiftUI

struct ScannerView: View {
    @StateObject private var viewModel = ScannerViewModel()

    var body: some View {
        VStack(spacing: 16) {
            CameraPreviewView(session: viewModel.captureSession)
                .frame(maxWidth: .infinity)
                .frame(height: 360)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(alignment: .bottomLeading) {
                    cameraStateBadge
                        .padding(12)
                }

            VStack(alignment: .leading, spacing: 12) {
                metricRow(title: "Estado da camera", value: formattedCameraState)
                metricRow(title: "Frames recebidos", value: "\(viewModel.totalFramesReceived)")
                metricRow(title: "FPS estimado", value: String(format: "%.1f", viewModel.estimatedFPS))
                metricRow(title: "Resolucao", value: formattedResolution)
                metricRow(title: "Matriz intrinseca", value: viewModel.isIntrinsicMatrixAvailable ? "Disponivel" : "Indisponivel")

                if let lastFrameTimestamp = viewModel.lastFrameTimestamp {
                    metricRow(title: "Ultimo timestamp", value: String(format: "%.3f s", lastFrameTimestamp))
                }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)
        }
        .padding(20)
        .background(Color(.systemBackground))
        .task {
            await viewModel.startCamera()
        }
        .onDisappear {
            viewModel.stopCamera()
        }
    }

    private var formattedCameraState: String {
        switch viewModel.cameraState {
        case .idle:
            return "Idle"
        case .preparing:
            return "Preparing"
        case .ready:
            return "Ready"
        case .running:
            return "Running"
        case .failed:
            return "Failed"
        }
    }

    private var formattedResolution: String {
        guard let resolution = viewModel.frameResolution else {
            return "-"
        }

        return "\(resolution.width) x \(resolution.height)"
    }

    private var cameraStateBadge: some View {
        Text(formattedCameraState)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
    }

    private func metricRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .monospacedDigit()
        }
        .font(.body)
    }
}

#Preview {
    ScannerView()
}
