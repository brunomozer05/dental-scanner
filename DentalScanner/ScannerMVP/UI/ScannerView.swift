import SwiftUI

struct ScannerView: View {
    @StateObject private var viewModel = ScannerViewModel()
    @State private var scaleValidationRealDistanceText = ""

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
                    metricRow(title: "Offset implante", value: viewModel.implantOffsetDescription)
                    metricRow(title: "Implantes x/y/z", value: formattedImplantPositions)
                    metricRow(title: "Distancia implante", value: formattedImplantDistance)
                    implantComparisonControls
                    metricRow(title: "Implantes selecionados", value: formattedSelectedImplantMarkers)
                    metricRow(title: "Distancia tag-tag", value: formattedSelectedTagDistance)
                    metricRow(title: "Distancia implante-implante", value: formattedSelectedImplantDistance)
                    scaleValidationSection
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

    private var formattedImplantPositions: String {
        guard !viewModel.implantPoseResults.isEmpty else {
            return "-"
        }

        return viewModel.implantPoseResults.map { implantPose in
            String(
                format: "ID %d: x %.1f, y %.1f, z %.1f mm",
                implantPose.markerId,
                implantPose.translationVector.x,
                implantPose.translationVector.y,
                implantPose.translationVector.z
            )
        }
        .joined(separator: "\n")
    }

    private var formattedImplantDistance: String {
        guard let implantPose = viewModel.implantPoseResult else {
            return "-"
        }

        return String(format: "ID %d: %.1f mm", implantPose.markerId, implantPose.distanceMm)
    }

    private var formattedSelectedImplantMarkers: String {
        guard !viewModel.selectedImplantMarkerIds.isEmpty else {
            return "-"
        }

        return viewModel.selectedImplantMarkerIds.map { "ID \($0)" }.joined(separator: " x ")
    }

    private var formattedSelectedTagDistance: String {
        guard let selectedTagDistanceMm = viewModel.selectedTagDistanceMm else {
            return "-"
        }

        return String(format: "%.1f mm", selectedTagDistanceMm)
    }

    private var formattedSelectedImplantDistance: String {
        guard let selectedImplantDistanceMm = viewModel.selectedImplantDistanceMm else {
            return "-"
        }

        return String(format: "%.1f mm", selectedImplantDistanceMm)
    }

    private var parsedScaleValidationRealDistanceMm: Double? {
        let normalizedText = scaleValidationRealDistanceText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")

        guard !normalizedText.isEmpty,
              let distanceMm = Double(normalizedText),
              distanceMm > 0
        else {
            return nil
        }

        return distanceMm
    }

    private var formattedScaleValidationRealDistance: String {
        if scaleValidationRealDistanceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "-"
        }

        guard let distanceMm = parsedScaleValidationRealDistanceMm else {
            return "Valor invalido"
        }

        return String(format: "%.2f mm", distanceMm)
    }

    private var formattedScaleValidationAppDistance: String {
        formattedSelectedImplantDistance
    }

    private var formattedScaleValidationAbsoluteError: String {
        formattedMillimeterValue(scaleValidationAbsoluteErrorMm(for: viewModel.selectedImplantDistanceMm))
    }

    private var formattedScaleValidationPercentError: String {
        formattedPercentValue(scaleValidationPercentError(for: viewModel.selectedImplantDistanceMm))
    }

    private var formattedScaleValidationCorrectionFactor: String {
        formattedCorrectionFactor(scaleValidationCorrectionFactor(for: viewModel.selectedImplantDistanceMm))
    }

    private var formattedScaleValidationTagAbsoluteError: String {
        formattedMillimeterValue(scaleValidationAbsoluteErrorMm(for: viewModel.selectedTagDistanceMm))
    }

    private var formattedScaleValidationTagPercentError: String {
        formattedPercentValue(scaleValidationPercentError(for: viewModel.selectedTagDistanceMm))
    }

    private var formattedScaleValidationTagCorrectionFactor: String {
        formattedCorrectionFactor(scaleValidationCorrectionFactor(for: viewModel.selectedTagDistanceMm))
    }

    private func scaleValidationAbsoluteErrorMm(for measuredDistanceMm: Double?) -> Double? {
        guard let realDistanceMm = parsedScaleValidationRealDistanceMm,
              let measuredDistanceMm
        else {
            return nil
        }

        return abs(measuredDistanceMm - realDistanceMm)
    }

    private func scaleValidationPercentError(for measuredDistanceMm: Double?) -> Double? {
        guard let realDistanceMm = parsedScaleValidationRealDistanceMm,
              let absoluteErrorMm = scaleValidationAbsoluteErrorMm(for: measuredDistanceMm)
        else {
            return nil
        }

        return absoluteErrorMm / realDistanceMm * 100.0
    }

    private func scaleValidationCorrectionFactor(for measuredDistanceMm: Double?) -> Double? {
        guard let realDistanceMm = parsedScaleValidationRealDistanceMm,
              let measuredDistanceMm,
              measuredDistanceMm > 0
        else {
            return nil
        }

        return realDistanceMm / measuredDistanceMm
    }

    private func formattedMillimeterValue(_ value: Double?) -> String {
        guard let value else {
            return "-"
        }

        return String(format: "%.2f mm", value)
    }

    private func formattedPercentValue(_ value: Double?) -> String {
        guard let value else {
            return "-"
        }

        return String(format: "%.2f%%", value)
    }

    private func formattedCorrectionFactor(_ value: Double?) -> String {
        guard let value else {
            return "-"
        }

        return String(format: "%.4fx", value)
    }

    private var formattedPoseErrorMessage: String {
        viewModel.poseErrorMessage ?? "Nenhum"
    }

    private var formattedArucoErrorMessage: String {
        viewModel.arucoErrorMessage ?? "Nenhum"
    }

    @ViewBuilder
    private var implantComparisonControls: some View {
        if !viewModel.implantPoseResults.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Comparar implantes")
                    .font(.headline)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(viewModel.implantPoseResults, id: \.markerId) { implantPose in
                            implantMarkerButton(for: implantPose)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var scaleValidationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Validacao de escala")
                .font(.headline)

            HStack(alignment: .center, spacing: 12) {
                Text("Distancia real")
                    .foregroundStyle(.secondary)

                TextField("mm", text: $scaleValidationRealDistanceText)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
            }

            metricRow(title: "Real informado", value: formattedScaleValidationRealDistance)
            metricRow(title: "Medida app tag", value: formattedSelectedTagDistance)
            metricRow(title: "Erro tag", value: formattedScaleValidationTagAbsoluteError)
            metricRow(title: "Erro tag %", value: formattedScaleValidationTagPercentError)
            metricRow(title: "Fator tag", value: formattedScaleValidationTagCorrectionFactor)
            metricRow(title: "Medida app implante", value: formattedScaleValidationAppDistance)
            metricRow(title: "Erro implante", value: formattedScaleValidationAbsoluteError)
            metricRow(title: "Erro implante %", value: formattedScaleValidationPercentError)
            metricRow(title: "Fator implante", value: formattedScaleValidationCorrectionFactor)
        }
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

    private func implantMarkerButton(for implantPose: ImplantPose) -> some View {
        let isSelected = viewModel.selectedImplantMarkerIds.contains(implantPose.markerId)

        return Button {
            viewModel.toggleImplantMarkerSelection(implantPose.markerId)
        } label: {
            Label("ID \(implantPose.markerId)", systemImage: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .background(isSelected ? Color.accentColor : Color(.secondarySystemBackground))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func metricRow(title: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)

            Spacer()

            Text(value)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .minimumScaleFactor(0.8)
                .layoutPriority(1)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.body)
    }
}

#Preview {
    ScannerView()
}
