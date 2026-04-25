import SwiftUI

struct ScannerView: View {
    @StateObject private var viewModel = ScannerViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ZStack {
                    CameraPreviewView(session: viewModel.captureSession)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    ArUcoOverlayView(
                        detections: viewModel.detectedMarkers,
                        frameResolution: viewModel.arucoFrameResolution ?? viewModel.frameResolution
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
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
                    metricRow(title: "OpenCV disponivel", value: viewModel.isOpenCVAvailable ? "true" : "false")
                    metricRow(title: "Dicionario ArUco", value: viewModel.arucoDictionaryName)
                    metricRow(title: "Frame no detector", value: viewModel.hasFrameReachedArucoDetector ? "true" : "false")
                    metricRow(title: "Chamadas detector", value: "\(viewModel.arucoDetectionCallCount)")
                    metricRow(title: "Frame OpenCV", value: formattedArucoFrameResolution)
                    metricRow(title: "Formato OpenCV", value: viewModel.arucoFramePixelFormat)
                    metricRow(title: "Bytes por linha", value: formattedArucoBytesPerRow)
                    metricRow(title: "Conversao OpenCV", value: viewModel.arucoPreprocessingDescription)
                    metricRow(title: "Marcadores detectados", value: "\(viewModel.detectedMarkerCount)")
                    metricRow(title: "IDs detectados", value: formattedDetectedMarkerIds)
                    metricRow(title: "Candidatos rejeitados", value: formattedRejectedCandidates)
                    metricRow(title: "Ultimo erro detector", value: formattedArucoErrorMessage)

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
            }
            .padding(20)
        }
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

    private var formattedArucoFrameResolution: String {
        guard let resolution = viewModel.arucoFrameResolution else {
            return "-"
        }

        return "\(resolution.width) x \(resolution.height)"
    }

    private var formattedDetectedMarkerIds: String {
        guard !viewModel.detectedMarkerIds.isEmpty else {
            return "-"
        }

        return viewModel.detectedMarkerIds.map(String.init).joined(separator: ", ")
    }

    private var formattedArucoBytesPerRow: String {
        guard let bytesPerRow = viewModel.arucoBytesPerRow else {
            return "-"
        }

        return "\(bytesPerRow)"
    }

    private var formattedRejectedCandidates: String {
        guard let rejectedCandidateCount = viewModel.arucoRejectedCandidateCount else {
            return "-"
        }

        return "\(rejectedCandidateCount)"
    }

    private var formattedArucoErrorMessage: String {
        viewModel.arucoErrorMessage ?? "Nenhum"
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
        HStack(alignment: .top) {
            Text(title)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            Text(value)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .layoutPriority(1)
        }
        .font(.body)
    }
}

#Preview {
    ScannerView()
}
