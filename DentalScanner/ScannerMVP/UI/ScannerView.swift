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
                        detections: viewModel.overlayMarkers,
                        frameResolution: viewModel.arucoFrameResolution ?? viewModel.frameResolution
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 360)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    torchButton
                        .padding(12)
                }
                .overlay(alignment: .bottomLeading) {
                    cameraStateBadge
                        .padding(12)
                }

                VStack(alignment: .leading, spacing: 12) {
                    metricRow(title: "Estado da camera", value: formattedCameraState)
                    metricRow(title: "Lanterna", value: formattedTorchState)
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
                    metricRow(title: "Marcador pose", value: formattedPoseMarkerId)
                    metricRow(title: "Tamanho marcador", value: String(format: "%.1f mm", viewModel.poseMarkerSizeMillimeters))
                    metricRow(title: "Distancia bruta", value: formattedRawPoseDistance)
                    metricRow(title: "Distancia estavel", value: formattedStablePoseDistance)
                    metricRow(title: "Erro reprojecao", value: formattedPoseReprojectionError)
                    metricRow(title: "Status pose", value: viewModel.poseStabilityStatus)
                    metricRow(title: "Candidatos rejeitados", value: formattedRejectedCandidates)
                    metricRow(title: "Ultimo erro detector", value: formattedArucoErrorMessage)
                    metricRow(title: "Ultimo erro pose", value: formattedPoseErrorMessage)

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

    private var formattedTorchState: String {
        guard viewModel.isTorchAvailable else {
            return "Indisponivel"
        }

        return viewModel.isTorchEnabled ? "Ligada" : "Desligada"
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

    private var formattedPoseMarkerId: String {
        guard let poseMarkerId = viewModel.rawPoseResult?.markerId ?? viewModel.stablePoseResult?.markerId else {
            return "-"
        }

        return "\(poseMarkerId)"
    }

    private var formattedRawPoseDistance: String {
        guard let distanceMm = viewModel.rawPoseResult?.distanceMm else {
            return "-"
        }

        return String(format: "%.1f mm", distanceMm)
    }

    private var formattedStablePoseDistance: String {
        guard let distanceMm = viewModel.stablePoseResult?.distanceMm else {
            return "-"
        }

        return String(format: "%.1f mm", distanceMm)
    }

    private var formattedPoseReprojectionError: String {
        guard let poseReprojectionError = viewModel.rawPoseResult?.reprojectionError else {
            return "-"
        }

        return String(format: "%.2f px", poseReprojectionError)
    }

    private var formattedPoseErrorMessage: String {
        viewModel.poseErrorMessage ?? "Nenhum"
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

    private var torchButton: some View {
        Button {
            viewModel.toggleTorch()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: viewModel.isTorchEnabled ? "flashlight.on.fill" : "flashlight.off.fill")
                Text(viewModel.isTorchEnabled ? "Lanterna on" : "Lanterna off")
            }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .foregroundStyle(viewModel.isTorchAvailable ? Color.primary : Color.secondary)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
        }
        .disabled(!viewModel.isTorchAvailable)
        .opacity(viewModel.isTorchAvailable ? 1 : 0.65)
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
