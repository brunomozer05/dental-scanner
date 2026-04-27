import SwiftUI
import UIKit

struct ScannerView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel = ScannerViewModel()
    @State private var scaleValidationRealDistanceText = ""
    @State private var previewOrientation: CameraPreviewOrientation = .landscapeRight
    @State private var isDebugPanelExpanded = false
    @State private var stlViewerPresentation: STLViewerPresentation?

    private let panelBackgroundColor = Color(red: 0.11, green: 0.11, blue: 0.12)
    private let chipBackgroundColor = Color(red: 0.16, green: 0.16, blue: 0.18)

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea(.all)
                .allowsHitTesting(false)

            CameraPreviewView(
                session: viewModel.captureSession,
                videoOrientation: previewOrientation.captureVideoOrientation
            )
            .ignoresSafeArea(.all)
            .allowsHitTesting(false)
            .zIndex(0)

            ArUcoOverlayView(
                detections: viewModel.overlayMarkers,
                frameResolution: viewModel.arucoFrameResolution ?? viewModel.frameResolution,
                orientation: previewOrientation,
                tagCoverages: viewModel.scanTagCoverages
            )
            .ignoresSafeArea(.all)
            .allowsHitTesting(false)
            .zIndex(1)

            VStack {
                topControlBar
                    .padding(.top, 12)
                    .padding(.horizontal, 12)

                Spacer()
            }
            .zIndex(3)

            VStack {
                Spacer()

                HStack {
                    scanWorkflowPanel
                        .padding(12)

                    Spacer()
                }
            }
            .zIndex(3)

            if isDebugPanelExpanded {
                VStack {
                    Spacer()

                    HStack {
                        Spacer()

                        debugPanel(isLandscape: true)
                            .frame(width: 320)
                            .padding(12)
                    }
                }
                .zIndex(2)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .background(Color.black)
        .ignoresSafeArea(.all)
        .supportedInterfaceOrientations(.landscape)
        .animation(.easeInOut(duration: 0.18), value: isDebugPanelExpanded)
        .task {
            applyPreviewOrientation(previewOrientation)
            updateLandscapePreviewOrientation()
            await viewModel.startCamera()
        }
        .onAppear {
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            updateLandscapePreviewOrientation()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            updateLandscapePreviewOrientation()
        }
        .onChange(of: scenePhase) { _, newScenePhase in
            guard newScenePhase == .active else {
                return
            }

            viewModel.handleAppBecameActive()
        }
        .onDisappear {
            viewModel.stopCamera()
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
        }
        .fullScreenCover(item: $stlViewerPresentation) { presentation in
            STLViewerView(stlFileURL: presentation.fileURL)
        }
    }

    private func updateLandscapePreviewOrientation() {
        guard let orientation = scannerPreviewOrientation(from: UIDevice.current.orientation) else {
            return
        }

        applyPreviewOrientation(orientation, shouldReapplyTorch: true)
    }

    private func applyPreviewOrientation(
        _ orientation: CameraPreviewOrientation,
        shouldReapplyTorch: Bool = false
    ) {
        let didChangeOrientation = previewOrientation != orientation

        previewOrientation = orientation
        viewModel.setPreviewOrientation(orientation)

        if shouldReapplyTorch && didChangeOrientation {
            viewModel.handleScannerOrientationChanged()
        }
    }

    private func scannerPreviewOrientation(from deviceOrientation: UIDeviceOrientation) -> CameraPreviewOrientation? {
        switch deviceOrientation {
        case .landscapeLeft, .landscapeRight:
            guard let resolvedVideoOrientation = videoOrientation(from: deviceOrientation) else {
                return nil
            }

            return CameraPreviewOrientation(videoOrientation: resolvedVideoOrientation)
        default:
            return nil
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

            statusChip(
                title: "Scan",
                value: formattedScanProgress,
                isActive: viewModel.scanState == .ready || viewModel.scanState.isCollectingFrames
            )

            Spacer(minLength: 4)

            compactTorchButton
            compactExportButton
            debugPanelToggleButton
        }
        .padding(8)
        .background(panelBackgroundColor.opacity(0.88))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                    scanQualitySection
                    scanDebugControl
                    scaleValidationSection
                    stlExportSection
                    errorDebugSection
                }
                .padding(.trailing, 2)
            }
            .frame(maxHeight: isLandscape ? 260 : 360)
        }
        .padding(12)
        .foregroundStyle(.white)
        .background(panelBackgroundColor.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
            withAnimation(.easeInOut(duration: 0.18)) {
                isDebugPanelExpanded.toggle()
            }
        } label: {
            Image(systemName: isDebugPanelExpanded ? "gearshape.fill" : "gearshape")
                .font(.body.weight(.semibold))
                .frame(width: 34, height: 34)
                .foregroundStyle(Color.white.opacity(isDebugPanelExpanded ? 1.0 : 0.72))
                .background(chipBackgroundColor.opacity(0.82))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isDebugPanelExpanded ? "Fechar debug" : "Abrir debug")
    }

    private var compactTorchButton: some View {
        Button {
            viewModel.toggleTorch()
        } label: {
            Image(systemName: viewModel.isTorchEnabled ? "flashlight.on.fill" : "flashlight.off.fill")
                .font(.body.weight(.semibold))
                .frame(width: 34, height: 34)
                .foregroundStyle(viewModel.isTorchAvailable ? Color.white : Color.white.opacity(0.35))
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
                .foregroundStyle(viewModel.canExportSTL ? Color.white : Color.white.opacity(0.35))
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.canExportSTL)
        .opacity(viewModel.canExportSTL ? 1 : 0.65)
    }

    private var scanWorkflowPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    viewModel.startScan()
                } label: {
                    Label(scanActionTitle, systemImage: scanActionIconName)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .foregroundStyle(Color.white)
                        .background(viewModel.scanState == .ready ? Color.green : Color.accentColor)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 2) {
                    Text(formattedScanState)
                        .font(.caption.weight(.semibold))

                    Text(viewModel.scanQualityStatus)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            ProgressView(value: viewModel.scanProgress, total: 100)
                .progressViewStyle(.linear)
                .tint(viewModel.scanState == .ready ? Color.green : Color.accentColor)
                .frame(width: 260)

            HStack(spacing: 12) {
                scanMetric(title: "Progresso", value: formattedScanProgress)
                scanMetric(title: "Frames", value: formattedScanValidFrames)
                scanMetric(title: "Qualidade", value: formattedScanQualityScore)
            }

            if viewModel.canExportSTL {
                Button {
                    openSTLViewer()
                } label: {
                    Label("Visualizar STL", systemImage: "cube.transparent")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.88))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .foregroundStyle(.white)
        .background(panelBackgroundColor.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func openSTLViewer() {
        guard viewModel.canExportSTL else {
            return
        }

        let stlFileURL = viewModel.stlExportURL ?? viewModel.exportCurrentImplantsAsSTL()
        guard let stlFileURL else {
            return
        }

        stlViewerPresentation = STLViewerPresentation(fileURL: stlFileURL)
    }

    private func scanMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
        }
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
        .foregroundStyle(.white)
        .background(chipBackgroundColor.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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

    private var formattedScanState: String {
        switch viewModel.scanState {
        case .idle:
            return "Idle"
        case .scanning:
            return "Scanning"
        case .stabilizing:
            return "Stabilizing"
        case .ready:
            return "Ready"
        }
    }

    private var scanActionTitle: String {
        switch viewModel.scanState {
        case .idle:
            return "Iniciar escaneamento"
        case .scanning, .stabilizing:
            return "Reiniciar"
        case .ready:
            return "Novo escaneamento"
        }
    }

    private var scanActionIconName: String {
        switch viewModel.scanState {
        case .idle:
            return "record.circle"
        case .scanning, .stabilizing:
            return "arrow.clockwise"
        case .ready:
            return "checkmark.circle"
        }
    }

    private var formattedScanProgress: String {
        String(format: "%.0f%%", viewModel.scanProgress)
    }

    private var formattedScanQualityScore: String {
        String(format: "%.0f%%", viewModel.scanQualityScore)
    }

    private var formattedScanValidFrames: String {
        "\(viewModel.scanValidFrameCount)"
    }

    private var formattedScanAverageReprojectionError: String {
        guard let scanAverageReprojectionError = viewModel.scanAverageReprojectionError else {
            return "-"
        }

        return String(format: "%.2f px", scanAverageReprojectionError)
    }

    private var formattedScanPoseJitter: String {
        guard let scanPoseJitterMm = viewModel.scanPoseJitterMm else {
            return "-"
        }

        return String(format: "%.2f mm", scanPoseJitterMm)
    }

    private var formattedScanRequiredCoverage: String {
        String(format: "%.0f%%", viewModel.scanRequiredAngularCoveragePercent)
    }

    private var formattedScanTagCoverageSummary: String {
        guard !viewModel.scanTagCoverages.isEmpty else {
            return "-"
        }

        return viewModel.scanTagCoverages.values
            .sorted { $0.markerId < $1.markerId }
            .map { coverage in
                String(
                    format: "ID %d: %.0f%% (%d/%d)",
                    coverage.markerId,
                    coverage.progress,
                    coverage.coveredBinCount,
                    coverage.requiredBinCount
                )
            }
            .joined(separator: "\n")
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

    private var scanTargetFrameBinding: Binding<Int> {
        Binding(
            get: { viewModel.scanTargetValidFrameCount },
            set: { viewModel.setScanTargetValidFrameCount($0) }
        )
    }

    private var scanRequiredCoverageBinding: Binding<Double> {
        Binding(
            get: { viewModel.scanRequiredAngularCoveragePercent },
            set: { viewModel.setScanRequiredAngularCoveragePercent($0) }
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

    private var scanQualitySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Escaneamento")
                .font(.subheadline.weight(.semibold))

            metricRow(title: "Estado", value: formattedScanState)
            metricRow(title: "Progresso", value: formattedScanProgress)
            metricRow(title: "Qualidade", value: formattedScanQualityScore)
            metricRow(title: "Frames validos", value: formattedScanValidFrames)
            metricRow(title: "Cobertura tags", value: formattedScanTagCoverageSummary)
            metricRow(title: "Erro medio", value: formattedScanAverageReprojectionError)
            metricRow(title: "Jitter pose", value: formattedScanPoseJitter)
            metricRow(title: "Status", value: viewModel.scanQualityStatus)
        }
    }

    private var scanDebugControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Config scan")
                .font(.subheadline.weight(.semibold))

            Stepper(
                value: scanTargetFrameBinding,
                in: viewModel.scanTargetValidFrameRange,
                step: 5
            ) {
                HStack(alignment: .center) {
                    Text("Frames alvo")
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("\(viewModel.scanTargetValidFrameCount)")
                        .monospacedDigit()
                }
            }

            Stepper(
                value: scanRequiredCoverageBinding,
                in: viewModel.scanRequiredAngularCoverageRange,
                step: viewModel.scanAngularCoverageStepPercent
            ) {
                HStack(alignment: .center) {
                    Text("Cobertura angular")
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text(formattedScanRequiredCoverage)
                        .monospacedDigit()
                }
            }
        }
        .font(.caption)
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
                        .foregroundStyle(viewModel.canExportSTL ? Color.primary : Color.secondary)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.canExportSTL)
                .opacity(viewModel.canExportSTL ? 1 : 0.65)

                if viewModel.canExportSTL, let stlExportURL = viewModel.stlExportURL {
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

private struct STLViewerPresentation: Identifiable {
    let id = UUID()
    let fileURL: URL
}
