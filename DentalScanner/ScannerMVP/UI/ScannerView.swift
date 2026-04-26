import SwiftUI
import UIKit

struct ScannerView: View {
    @StateObject private var viewModel = ScannerViewModel()
    @State private var scaleValidationRealDistanceText = ""
    @State private var previewOrientation: CameraPreviewOrientation = .landscapeRight
    @State private var previewOrientationRevision = 0
    @State private var isDebugPanelExpanded = true

    var body: some View {
        ZStack {
            CameraPreviewView(
                session: viewModel.captureSession,
                orientation: previewOrientation,
                orientationRevision: previewOrientationRevision
            )
            .ignoresSafeArea()
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            ArUcoOverlayView(
                detections: viewModel.overlayMarkers,
                frameResolution: viewModel.arucoFrameResolution ?? viewModel.frameResolution,
                orientation: previewOrientation
            )
            .ignoresSafeArea()
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 0) {
                topControlBar
                    .padding(.horizontal, 12)
                    .padding(.top, 12)

                Spacer(minLength: 12)

                if isDebugPanelExpanded {
                    HStack(alignment: .bottom) {
                        Spacer(minLength: 0)

                        debugPanel(isLandscape: true)
                            .frame(width: 380)
                            .frame(maxHeight: 420)
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .ignoresSafeArea()
        .task {
            applyLaunchPreviewOrientation()
            await viewModel.startCamera()
            reapplyPreviewOrientation(after: 0.15)
            reapplyPreviewOrientation(after: 0.45)
        }
        .onAppear {
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            applyLaunchPreviewOrientation()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            updatePreviewOrientation()
        }
        .onDisappear {
            viewModel.stopCamera()
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
        }
    }

    private func applyLaunchPreviewOrientation() {
        applyPreviewOrientation(.landscapeRight)
        reapplyPreviewOrientation(after: 0.05)
        reapplyPreviewOrientation(after: 0.25)
        reapplyPreviewOrientation(after: 0.75)
    }

    private func reapplyPreviewOrientation(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            updatePreviewOrientation()
        }
    }

    private var topControlBar: some View {
        HStack(spacing: 8) {
            statusChip(
                title: "OpenCV",
                value: viewModel.isOpenCVAvailable ? "on" : "off",
                isActive: viewModel.isOpenCVAvailable
            )

            statusChip(
                title: "Tags",
                value: "\(viewModel.detectedMarkerCount)",
                isActive: viewModel.detectedMarkerCount > 0
            )

            statusChip(
                title: "Pose",
                value: viewModel.rawPoseResult == nil ? "-" : formattedRawPoseDistance,
                isActive: viewModel.rawPoseResult != nil
            )

            Spacer(minLength: 4)

            compactTorchButton
            compactExportButton
            debugPanelToggleButton
        }
        .padding(8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func debugPanel(isLandscape: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Debug")
                    .font(.headline)

                Spacer()

                Text(formattedCameraState)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            ScrollView(showsIndicators: true) {
                VStack(alignment: .leading, spacing: 10) {
                    debugSummarySection
                    markerSizeDebugControl
                    poseDebugSection
                    implantComparisonControls
                    scaleValidationSection
                    stlExportSection
                    errorDebugSection
                }
                .padding(.trailing, 2)
            }
            .frame(maxHeight: isLandscape ? .infinity : 360)
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var debugSummarySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            metricRow(title: "Lanterna", value: formattedTorchState)
            metricRow(title: "FPS", value: String(format: "%.1f", viewModel.estimatedFPS))
            metricRow(title: "Resolucao", value: formattedResolution)
            metricRow(title: "Intrinseca", value: viewModel.isIntrinsicMatrixAvailable ? "Disponivel" : "Indisponivel")
            metricRow(title: "IDs", value: formattedDetectedMarkerIds)
            metricRow(title: "Marker size", value: String(format: "%.1f mm", viewModel.poseMarkerSizeMillimeters))
        }
    }

    private var poseDebugSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Pose")
                .font(.subheadline.weight(.semibold))

            metricRow(title: "Marcador", value: formattedPoseMarkerId)
            metricRow(title: "Distancia bruta", value: formattedRawPoseDistance)
            metricRow(title: "Distancia estavel", value: formattedStablePoseDistance)
            metricRow(title: "Erro reproj.", value: formattedPoseReprojectionError)
            metricRow(title: "Status", value: viewModel.poseStabilityStatus)
            metricRow(title: "Implante", value: formattedImplantDistance)
            metricRow(title: "Implantes x/y/z", value: formattedImplantPositions)
        }
    }

    private var errorDebugSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            metricRow(title: "Erro detector", value: formattedArucoErrorMessage)
            metricRow(title: "Erro pose", value: formattedPoseErrorMessage)

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private var debugPanelToggleButton: some View {
        Button {
            isDebugPanelExpanded.toggle()
        } label: {
            Image(systemName: isDebugPanelExpanded ? "info.circle.fill" : "info.circle")
                .font(.body.weight(.semibold))
                .frame(width: 34, height: 34)
                .foregroundStyle(Color.primary)
        }
        .buttonStyle(.plain)
    }

    private var compactTorchButton: some View {
        Button {
            viewModel.toggleTorch()
        } label: {
            Image(systemName: viewModel.isTorchEnabled ? "flashlight.on.fill" : "flashlight.off.fill")
                .font(.body.weight(.semibold))
                .frame(width: 34, height: 34)
                .foregroundStyle(viewModel.isTorchAvailable ? Color.primary : Color.secondary)
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.isTorchAvailable)
        .opacity(viewModel.isTorchAvailable ? 1 : 0.65)
    }

    private var compactExportButton: some View {
        Button {
            viewModel.exportCurrentImplantsAsSTL()
        } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.body.weight(.semibold))
                .frame(width: 34, height: 34)
                .foregroundStyle(viewModel.implantPoseResults.isEmpty ? Color.secondary : Color.primary)
        }
        .buttonStyle(.plain)
        .disabled(viewModel.implantPoseResults.isEmpty)
        .opacity(viewModel.implantPoseResults.isEmpty ? 0.65 : 1)
    }

    private func statusChip(title: String, value: String, isActive: Bool) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(isActive ? Color.green : Color.red)
                .frame(width: 7, height: 7)

            Text(title)
                .foregroundStyle(.secondary)

            Text(value)
                .monospacedDigit()
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(.secondarySystemBackground).opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func updatePreviewOrientation() {
        let foregroundScene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }

        if let interfaceOrientation = foregroundScene?.interfaceOrientation,
           let orientation = landscapeOrientation(from: interfaceOrientation) {
            applyPreviewOrientation(orientation)
            return
        }

        if let orientation = landscapeOrientation(from: UIDevice.current.orientation) {
            applyPreviewOrientation(orientation)
        } else {
            applyPreviewOrientation(.landscapeRight)
        }
    }

    private func applyPreviewOrientation(_ orientation: CameraPreviewOrientation) {
        previewOrientation = orientation
        previewOrientationRevision += 1
        viewModel.setPreviewOrientation(orientation)
    }

    private func landscapeOrientation(from interfaceOrientation: UIInterfaceOrientation) -> CameraPreviewOrientation? {
        switch interfaceOrientation {
        case .landscapeLeft:
            return .landscapeLeft
        case .landscapeRight:
            return .landscapeRight
        default:
            return nil
        }
    }

    private func landscapeOrientation(from deviceOrientation: UIDeviceOrientation) -> CameraPreviewOrientation? {
        switch deviceOrientation {
        case .landscapeLeft:
            return .landscapeLeft
        case .landscapeRight:
            return .landscapeRight
        default:
            return nil
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

    private var markerSizeBinding: Binding<Double> {
        Binding(
            get: { viewModel.poseMarkerSizeMillimeters },
            set: { viewModel.setMarkerSizeMillimeters($0) }
        )
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

    private var formattedSTLExportedImplantCount: String {
        guard viewModel.stlExportedImplantCount > 0 else {
            return "-"
        }

        return "\(viewModel.stlExportedImplantCount)"
    }

    private var formattedSTLExportFileName: String {
        viewModel.stlExportURL?.lastPathComponent ?? "-"
    }

    private var formattedSTLExportError: String {
        viewModel.stlExportErrorMessage ?? "Nenhum"
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

    @ViewBuilder
    private var markerSizeDebugControl: some View {
        if viewModel.isMarkerSizeDebugEditingEnabled {
            Stepper(
                value: markerSizeBinding,
                in: viewModel.markerSizeDebugRange,
                step: viewModel.markerSizeDebugStepMillimeters
            ) {
                HStack(alignment: .center) {
                    Text("Tamanho marcador debug")
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)

                    Spacer()

                    Text(String(format: "%.1f mm", viewModel.poseMarkerSizeMillimeters))
                        .monospacedDigit()
                }
            }
            .font(.body)
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

    private var stlExportSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Exportacao STL")
                .font(.headline)

            HStack(spacing: 10) {
                Button {
                    viewModel.exportCurrentImplantsAsSTL()
                } label: {
                    Label("Exportar STL", systemImage: "doc.badge.plus")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .foregroundStyle(viewModel.implantPoseResults.isEmpty ? Color.secondary : Color.primary)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(viewModel.implantPoseResults.isEmpty)
                .opacity(viewModel.implantPoseResults.isEmpty ? 0.65 : 1)

                if let stlExportURL = viewModel.stlExportURL {
                    ShareLink(item: stlExportURL) {
                        Label("Compartilhar STL", systemImage: "square.and.arrow.up")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .foregroundStyle(Color.white)
                            .background(Color.accentColor)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            metricRow(title: "Implantes no STL", value: formattedSTLExportedImplantCount)
            metricRow(title: "Arquivo STL", value: formattedSTLExportFileName)
            metricRow(title: "Erro STL", value: formattedSTLExportError)
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
        .font(.caption)
    }
}

#Preview {
    ScannerView()
}
