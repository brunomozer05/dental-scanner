import SwiftUI
import UIKit

struct ScannerView: View {
    let onCancel: (() -> Void)?

    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel = ScannerViewModel()
    @State private var scaleValidationRealDistanceText = ""
    @State private var previewOrientation: CameraPreviewOrientation = .landscapeRight
    @State private var isDebugPanelExpanded = false
    @State private var stlViewerPresentation: STLViewerPresentation?

    private let panelBackgroundColor = Color(red: 0.11, green: 0.11, blue: 0.12)
    private let chipBackgroundColor = Color(red: 0.16, green: 0.16, blue: 0.18)
    private let scannerAccentColor = Color(red: 0.23, green: 0.51, blue: 0.96)

    init(onCancel: (() -> Void)? = nil) {
        self.onCancel = onCancel
    }

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

            ScannerCrosshairView(accentColor: scannerAccentColor)
                .zIndex(2)

            if viewModel.showDistanceGuide {
                HStack {
                    Spacer()

                    ScanDistanceGuideView(
                        distanceMm: viewModel.poseDistanceMm,
                        configuration: .default
                    )
                    .padding(.trailing, 16)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
                .zIndex(2)
            }

            VStack {
                HStack(alignment: .top, spacing: 12) {
                    scannerTagListPanel

                    Spacer(minLength: 12)

                    scannerUtilityControls
                }
                .padding(.top, 14)
                .padding(.horizontal, 14)

                Spacer()

                ZStack(alignment: .bottom) {
                    scannerBottomBar

                    HStack {
                        cancelScanButton
                        Spacer()
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
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
        .onChange(of: scaleValidationRealDistanceText) { _, _ in
            updatePrecisionValidationExpectedDistance()
        }
        .fullScreenCover(
            item: $stlViewerPresentation,
            onDismiss: {
                viewModel.resumeCameraAfterExternalPresentation()
            }
        ) { presentation in
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

    private func updatePrecisionValidationExpectedDistance() {
        viewModel.setPrecisionValidationExpectedDistanceMillimeters(parsedScaleValidationRealDistanceMm)
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

    private var scannerTagListPanel: some View {
        ScannerGlassPanel(cornerRadius: 16) {
            VStack(alignment: .leading, spacing: 9) {
                Text("TAGS")
                    .font(.caption2.weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.52))

                if scannerTagCoverageItems.isEmpty {
                    Text("Aguardando marcadores")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.white.opacity(0.46))
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVGrid(columns: scannerTagGridColumns, spacing: 6) {
                            ForEach(scannerTagCoverageItems) { item in
                                ScannerTagCoverageRow(
                                    label: item.label,
                                    progress: item.progress,
                                    accentColor: scannerAccentColor
                                )
                            }
                        }
                    }
                    .frame(maxHeight: 74)
                }
            }
        }
        .frame(width: 186, alignment: .leading)
    }

    private var scannerUtilityControls: some View {
        HStack(spacing: 10) {
            ScannerCircleButton(
                systemImage: viewModel.isTorchEnabled ? "flashlight.on.fill" : "flashlight.off.fill",
                accessibilityLabel: viewModel.isTorchEnabled ? "Desligar lanterna" : "Ligar lanterna",
                accentColor: scannerAccentColor,
                isEnabled: viewModel.isTorchAvailable,
                isActive: viewModel.isTorchEnabled
            ) {
                viewModel.toggleTorch()
            }

            ScannerCircleButton(
                systemImage: isDebugPanelExpanded ? "gearshape.fill" : "gearshape",
                accessibilityLabel: isDebugPanelExpanded ? "Fechar debug" : "Abrir debug",
                accentColor: scannerAccentColor,
                isEnabled: true,
                isActive: isDebugPanelExpanded
            ) {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isDebugPanelExpanded.toggle()
                }
            }
        }
    }

    private var scannerBottomBar: some View {
        ScannerGlassPanel(cornerRadius: 20) {
            HStack(spacing: 18) {
                scannerBottomMetric(title: "Cobertura total", value: formattedScanGlobalCoverage)

                ScannerDivider()

                scannerBottomMetric(title: "Qualidade", value: scannerQualityLabel)

                ScannerDivider()

                Button {
                    startOrRestartScanFromHUD()
                } label: {
                    Label(scanActionTitle, systemImage: scanActionIconName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 13)
                        .frame(height: 38)
                        .background(scannerAccentColor.opacity(0.82))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                if viewModel.isGeneratingSTL {
                    stlGenerationIndicator
                } else if viewModel.canExportSTL {
                    Button {
                        openSTLViewer()
                    } label: {
                        Image(systemName: "cube.transparent")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Visualizar modelo 3D")
                }
            }
        }
    }

    private var cancelScanButton: some View {
        ScannerCircleButton(
            systemImage: "xmark",
            accessibilityLabel: "Cancelar",
            accentColor: scannerAccentColor,
            isEnabled: true,
            isActive: false
        ) {
            viewModel.stopCamera()
            onCancel?()
        }
    }

    private var stlGenerationIndicator: some View {
        HStack(spacing: 8) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(.white)
                .scaleEffect(0.75)

            Text("Gerando modelo...")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.78))
        }
        .frame(height: 38)
        .padding(.horizontal, 10)
        .background(Color.white.opacity(0.08))
        .clipShape(Capsule())
    }

    private func scannerBottomMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.white.opacity(0.52))

            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .monospacedDigit()
        }
    }

    private func startOrRestartScanFromHUD() {
        viewModel.startScan()
    }

    private var scannerQualityLabel: String {
        if viewModel.scanState == .ready {
            return "Boa"
        }

        switch viewModel.scanQualityScore {
        case 75...:
            return "Boa"
        case 45..<75:
            return "Media"
        case 1..<45:
            return "Baixa"
        default:
            return "Aguardando"
        }
    }

    private var scannerTagCoverageItems: [ScannerTagCoverageItem] {
        var progressByMarkerId: [Int: Double] = [:]

        for marker in viewModel.overlayMarkers {
            progressByMarkerId[marker.markerId] = 0
        }

        for coverage in viewModel.scanTagCoverages.values {
            progressByMarkerId[coverage.markerId] = coverage.progress
        }

        let items = progressByMarkerId
            .map {
                ScannerTagCoverageItem(
                    markerId: $0.key,
                    label: viewModel.markerProfile == .dualArucoV2 ? "M\($0.key)" : "ID \($0.key)",
                    progress: $0.value
                )
            }
            .sorted { $0.markerId < $1.markerId }

        return viewModel.markerProfile == .dualArucoV2
            ? Array(items.prefix(4))
            : items
    }

    private var scannerTagGridColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 6),
            GridItem(.flexible(), spacing: 6)
        ]
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
                    poseDebugSection
                    scanDebugControl
                    dualMarkerDebugSection
                    scanQualitySection
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
            metricRow(title: "Perfil marker", value: viewModel.markerProfile.debugTitle)
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
            metricRow(title: "Modo pose", value: formattedPoseMode)
            metricRow(title: "Pontos pose", value: formattedPosePointCount)
            metricRow(title: "Status", value: viewModel.poseStabilityStatus)
            metricRow(title: "Implante", value: formattedImplantDistance)
            metricRow(title: "Implantes x/y/z", value: formattedImplantPositions)
        }
    }

    @ViewBuilder
    private var dualMarkerDebugSection: some View {
        if viewModel.markerProfile == .dualArucoV2 {
            VStack(alignment: .leading, spacing: 6) {
                Text("Markers v2")
                    .font(.subheadline.weight(.semibold))

                ForEach(viewModel.dualMarkerDebugStates) { state in
                    VStack(alignment: .leading, spacing: 4) {
                        metricRow(title: "Marker fisico", value: "ID \(state.physicalMarkerId)")
                        metricRow(title: "Top \(state.topTagId)", value: formattedDualTagDetection(state, role: .top))
                        metricRow(title: "Bottom \(state.bottomTagId)", value: formattedDualTagDetection(state, role: .bottom))
                        metricRow(title: "Top area", value: formattedDualTagArea(state, role: .top))
                        metricRow(title: "Bottom area", value: formattedDualTagArea(state, role: .bottom))
                        metricRow(title: "Top frames", value: formattedDualTagCounts(state, role: .top))
                        metricRow(title: "Bottom frames", value: formattedDualTagCounts(state, role: .bottom))
                        metricRow(title: "Top ultimos", value: formattedDualTagRecentCounts(state, role: .top))
                        metricRow(title: "Bottom ultimos", value: formattedDualTagRecentCounts(state, role: .bottom))
                        metricRow(title: "Modo", value: formattedDualMarkerPoseMode(state))
                        metricRow(title: "Erro reproj.", value: formattedDualMarkerReprojectionError(state))
                        metricRow(title: "Pontos", value: formattedDualMarkerPointCount(state))
                        metricRow(title: "Aviso", value: formattedDualMarkerDetectionWarning(state))
                    }
                    .padding(.vertical, 4)
                }
            }
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

            if viewModel.isGeneratingSTL {
                stlGenerationIndicator
            } else if viewModel.canExportSTL {
                Button {
                    openSTLViewer()
                } label: {
                    Label("Visualizar modelo 3D", systemImage: "cube.transparent")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .frame(height: 46)
                        .background(chipBackgroundColor.opacity(0.95))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
        guard viewModel.canExportSTL,
              !viewModel.isGeneratingSTL
        else {
            return
        }

        let stlFileURL = viewModel.stlExportURL ?? viewModel.exportCurrentImplantsAsSTL()
        guard let stlFileURL else {
            return
        }

        viewModel.pauseCameraForExternalPresentation()
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

    private func formattedCoveragePercent(_ percent: Double) -> String {
        "\(roundedCoveragePercent(percent))%"
    }

    private func formattedPreciseCoveragePercent(_ percent: Double) -> String {
        guard percent.isFinite else {
            return "0.0%"
        }

        let clampedPercent = min(max(percent, 0.0), 100.0)
        return String(format: "%.1f%%", clampedPercent)
    }

    private func roundedCoveragePercent(_ percent: Double) -> Int {
        Int(round(normalizedCoverage(percent / 100.0) * 100.0))
    }

    private func normalizedCoverage(_ value: Double) -> Double {
        guard value.isFinite else {
            return 0
        }

        let clamped = min(max(value, 0.0), 1.0)
        return clamped >= 0.995 ? 1.0 : clamped
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
        formattedScanState(viewModel.scanState)
    }

    private var formattedPreviousScanState: String {
        formattedScanState(viewModel.previousScanState)
    }

    private func formattedScanState(_ scanState: ScannerViewModel.ScanState) -> String {
        switch scanState {
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
        formattedCoveragePercent(viewModel.scanProgress)
    }

    private var formattedScanQualityScore: String {
        formattedCoveragePercent(viewModel.scanQualityScore)
    }

    private var formattedScanValidFrames: String {
        "\(viewModel.scanValidFrameCount)/\(viewModel.scanTargetGoodFrameCount)"
    }

    private var formattedScanGlobalCoverage: String {
        formattedCoveragePercent(viewModel.scanGlobalCoveragePercent)
    }

    private var formattedScanNormalizedCoverageProgress: String {
        formattedPreciseCoveragePercent(viewModel.scanNormalizedCoverageProgressPercent)
    }

    private var formattedScanCurrentCoverage: String {
        formattedPreciseCoveragePercent(viewModel.scanCurrentAngularCoveragePercent)
    }

    private var formattedScanAverageDistance: String {
        guard let scanAverageDistanceMm = viewModel.scanAverageDistanceMm else {
            return "-"
        }

        return String(format: "%.1f mm", scanAverageDistanceMm)
    }

    private var formattedScanAverageReprojectionError: String {
        guard let scanAverageReprojectionError = viewModel.scanAverageReprojectionError else {
            return "-"
        }

        return String(format: "%.2f px", scanAverageReprojectionError)
    }

    private var formattedScanPoseJitter: String {
        guard let scanPositionJitterMm = viewModel.scanPositionJitterMm else {
            return "-"
        }

        return String(format: "%.2f mm", scanPositionJitterMm)
    }

    private var formattedScanRotationJitter: String {
        guard let scanRotationJitterDegrees = viewModel.scanRotationJitterDegrees else {
            return "-"
        }

        return String(format: "%.2f deg", scanRotationJitterDegrees)
    }

    private var formattedScanStableReadinessDuration: String {
        String(
            format: "%.1f/%.1f s",
            viewModel.scanStableReadinessDurationSeconds,
            viewModel.scanRequiredStableDurationSeconds
        )
    }

    private var formattedReadyTransitionCount: String {
        "\(viewModel.readyTransitionCount)"
    }

    private var formattedLastSTLExportTagPoseCount: String {
        "\(viewModel.lastSTLExportTagPoseCount)"
    }

    private var formattedLastSTLExportMarkerIds: String {
        guard !viewModel.lastSTLExportMarkerIds.isEmpty else {
            return "-"
        }

        return viewModel.lastSTLExportMarkerIds.map(String.init).joined(separator: ", ")
    }

    private var formattedLastSTLExportBottomGeometry: String {
        guard let bottomTagSize = viewModel.lastSTLExportBottomTagSizeMillimeters,
              let bottomCenterY = viewModel.lastSTLExportBottomCenterYMillimeters
        else {
            return "-"
        }

        return String(format: "%.1f mm / y %.2f mm", bottomTagSize, bottomCenterY)
    }

    private var formattedCurrentExportableTagPoseCount: String {
        "\(viewModel.currentExportableTagPoseCount)"
    }

    private var formattedCanExportSTL: String {
        formattedBool(viewModel.canExportSTL)
    }

    private var formattedScanRequiredCoverage: String {
        formattedPreciseCoveragePercent(viewModel.scanRequiredAngularCoveragePercent)
    }

    private var formattedScanCoverageMarkerIds: String {
        let markerIds = viewModel.scanCoverageMarkerIds
        guard !markerIds.isEmpty else {
            return "-"
        }

        return markerIds.map(String.init).joined(separator: ", ")
    }

    private var formattedScanTagCoverageSummary: String {
        guard !viewModel.scanTagCoverages.isEmpty else {
            return "-"
        }

        return viewModel.scanTagCoverages.values
            .sorted { $0.markerId < $1.markerId }
            .map { coverage in
                String(
                    format: "ID %d: atual %d%% / exigida %d%% (%d/%d)",
                    coverage.markerId,
                    roundedCoveragePercent(coverage.rawAngularCoveragePercent),
                    roundedCoveragePercent(coverage.requiredAngularCoveragePercent),
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

    private var markerProfileBinding: Binding<MarkerProfile> {
        Binding(
            get: { viewModel.markerProfile },
            set: { viewModel.setMarkerProfile($0) }
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

    private var showDistanceGuideBinding: Binding<Bool> {
        Binding(
            get: { viewModel.showDistanceGuide },
            set: { viewModel.setShowDistanceGuide($0) }
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

    private var formattedPoseMode: String {
        viewModel.rawPoseResult?.poseSource.debugTitle ?? "-"
    }

    private var formattedPosePointCount: String {
        guard let usedPointCount = viewModel.rawPoseResult?.usedPointCount else {
            return "-"
        }

        return "\(usedPointCount)"
    }

    private func formattedDualMarkerPoseMode(_ state: DualArucoMarkerDebugState) -> String {
        state.poseSource?.debugTitle ?? "missing"
    }

    private func formattedDualTagDetection(
        _ state: DualArucoMarkerDebugState,
        role: DualArucoTagRole
    ) -> String {
        let rawDetected: Bool
        let acceptedDetected: Bool
        let areaBelowMinimum: Bool
        let recentlySeen: Bool

        switch role {
        case .top:
            rawDetected = state.topTagRawDetected
            acceptedDetected = state.topTagDetected
            areaBelowMinimum = state.topAreaBelowMinimum
            recentlySeen = state.topTagRecentlySeen
        case .bottom:
            rawDetected = state.bottomTagRawDetected
            acceptedDetected = state.bottomTagDetected
            areaBelowMinimum = state.bottomAreaBelowMinimum
            recentlySeen = state.bottomTagRecentlySeen
        }

        if acceptedDetected {
            return "sim"
        }

        if rawDetected && areaBelowMinimum {
            return "area baixa"
        }

        if rawDetected {
            return "rejeitada"
        }

        if recentlySeen {
            return "recente"
        }

        return "nao"
    }

    private func formattedDualTagArea(
        _ state: DualArucoMarkerDebugState,
        role: DualArucoTagRole
    ) -> String {
        let area: Double?
        switch role {
        case .top:
            area = state.topAreaPixels
        case .bottom:
            area = state.bottomAreaPixels
        }

        guard let area, area.isFinite else {
            return "-"
        }

        return String(format: "%.0f px2", area)
    }

    private func formattedDualTagCounts(
        _ state: DualArucoMarkerDebugState,
        role: DualArucoTagRole
    ) -> String {
        switch role {
        case .top:
            return "\(state.topAcceptedDetectionCount)/\(state.topDetectionCount)"
        case .bottom:
            return "\(state.bottomAcceptedDetectionCount)/\(state.bottomDetectionCount)"
        }
    }

    private func formattedDualTagRecentCounts(
        _ state: DualArucoMarkerDebugState,
        role: DualArucoTagRole
    ) -> String {
        let acceptedCount: Int
        let rawCount: Int

        switch role {
        case .top:
            acceptedCount = state.topRecentAcceptedDetectionCount
            rawCount = state.topRecentDetectionCount
        case .bottom:
            acceptedCount = state.bottomRecentAcceptedDetectionCount
            rawCount = state.bottomRecentDetectionCount
        }

        return String(
            format: "%d/%d em %d frames",
            acceptedCount,
            rawCount,
            viewModel.dualMarkerRecentDetectionWindowFrameCount
        )
    }

    private func formattedDualMarkerReprojectionError(_ state: DualArucoMarkerDebugState) -> String {
        guard let reprojectionError = state.reprojectionError,
              reprojectionError.isFinite
        else {
            return "-"
        }

        return String(format: "%.2f px", reprojectionError)
    }

    private func formattedDualMarkerPointCount(_ state: DualArucoMarkerDebugState) -> String {
        guard let usedPointCount = state.usedPointCount else {
            return "-"
        }

        return "\(usedPointCount)"
    }

    private func formattedDualMarkerDetectionWarning(_ state: DualArucoMarkerDebugState) -> String {
        state.detectionWarning ?? "-"
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

    private var formattedSTLExportStatus: String {
        if viewModel.isGeneratingSTL {
            return "Gerando modelo..."
        }

        if viewModel.stlExportErrorMessage != nil {
            return "Erro"
        }

        return viewModel.stlExportURL == nil ? "Pendente" : "Pronto"
    }

    private var formattedSTLExportFileExists: String {
        viewModel.hasSTLExportFile ? "Sim" : "Nao"
    }

    private var formattedSTLExportURLExists: String {
        viewModel.hasSTLExportURL ? "Sim" : "Nao"
    }

    private var formattedSTLExportError: String {
        viewModel.stlExportErrorMessage ?? "Nenhum"
    }

    private func formattedBool(_ value: Bool) -> String {
        value ? "Sim" : "Nao"
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
        formattedMillimeterValue(viewModel.precisionValidationCurrentErrorMm)
    }

    private var formattedScaleValidationAverageError: String {
        formattedMillimeterValue(viewModel.precisionValidationAverageErrorMm)
    }

    private var formattedScaleValidationSampleCount: String {
        guard viewModel.precisionValidationSampleCount > 0 else {
            return "-"
        }

        return "\(viewModel.precisionValidationSampleCount)"
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
            metricRow(title: "Estado anterior", value: formattedPreviousScanState)
            metricRow(title: "Bloqueio principal", value: viewModel.scanReadinessBlockerSummary)
            metricRow(title: "Ready transitions", value: formattedReadyTransitionCount)
            metricRow(title: "Frames bons", value: formattedScanValidFrames)
            metricRow(title: "rawAngularCoverage min", value: formattedScanCurrentCoverage)
            metricRow(title: "requiredAngularCoverage", value: formattedScanRequiredCoverage)
            metricRow(title: "normalizedCoverageProgress", value: formattedScanNormalizedCoverageProgress)
            metricRow(title: "coverageReady", value: formattedBool(viewModel.scanCoverageReady))
            metricRow(title: "goodFramesReady", value: formattedBool(viewModel.scanGoodFramesReady))
            metricRow(title: "distanceReady", value: formattedBool(viewModel.scanDistanceReady))
            metricRow(title: "reprojectionReady", value: formattedBool(viewModel.scanReprojectionReady))
            metricRow(title: "jitterReady", value: formattedBool(viewModel.scanJitterReady))
            metricRow(title: "stableReady", value: formattedBool(viewModel.scanStableReady))
            metricRow(title: "currentFrameGood", value: formattedBool(viewModel.scanCurrentFrameGood))
            metricRow(title: "Gerando STL", value: formattedBool(viewModel.isGeneratingSTL))
            metricRow(title: "Export iniciado", value: formattedBool(viewModel.didStartSTLExportForCurrentScan))
            metricRow(title: "tagPoses atuais", value: formattedCurrentExportableTagPoseCount)
            metricRow(title: "tagPoses export", value: formattedLastSTLExportTagPoseCount)
            metricRow(title: "Perfil export", value: viewModel.lastSTLExportMarkerProfile.debugTitle)
            metricRow(title: "STL ref", value: viewModel.lastSTLReferenceModelFileName)
            metricRow(title: "IDs export", value: formattedLastSTLExportMarkerIds)
            metricRow(title: "Bottom v2", value: formattedLastSTLExportBottomGeometry)
            metricRow(title: "handleReady chamado", value: formattedBool(viewModel.didCallHandleScanBecameReady))
            metricRow(title: "saveScan chamado", value: formattedBool(viewModel.didCallSaveCurrentScanIfNeeded))
            metricRow(title: "canExportSTL", value: formattedCanExportSTL)
            metricRow(title: "STL URL existe", value: formattedSTLExportURLExists)
            metricRow(title: "STL existe", value: formattedSTLExportFileExists)
            metricRow(title: "Erro STL", value: formattedSTLExportError)
            metricRow(title: "Evento STL", value: viewModel.lastSTLExportEventMessage)
        }
    }

    private var scanDebugControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Config scan")
                .font(.subheadline.weight(.semibold))

            Picker("Perfil marker", selection: markerProfileBinding) {
                ForEach(viewModel.markerProfiles) { profile in
                    Text(profile.debugTitle)
                        .tag(profile)
                }
            }
            .pickerStyle(.segmented)

            markerSizeDebugControl

            Toggle("Barra distancia", isOn: showDistanceGuideBinding)

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

            metricRow(title: "Marcadores", value: formattedSelectedImplantMarkers)
            metricRow(title: "Real informado", value: formattedScaleValidationRealDistance)
            metricRow(title: "Medida app tag", value: formattedSelectedTagDistance)
            metricRow(title: "Erro atual tag", value: formattedScaleValidationTagAbsoluteError)
            metricRow(title: "Erro medio tag", value: formattedScaleValidationAverageError)
            metricRow(title: "Amostras erro", value: formattedScaleValidationSampleCount)
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
                    Label(
                        viewModel.isGeneratingSTL ? "Gerando modelo..." : "Exportar STL",
                        systemImage: viewModel.isGeneratingSTL ? "hourglass" : "doc.badge.plus"
                    )
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .foregroundStyle(
                            viewModel.canExportSTL && !viewModel.isGeneratingSTL ? Color.primary : Color.secondary
                        )
                        .background(Color(.secondarySystemBackground))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.canExportSTL || viewModel.isGeneratingSTL)
                .opacity(viewModel.canExportSTL && !viewModel.isGeneratingSTL ? 1 : 0.65)

                if viewModel.canExportSTL,
                   !viewModel.isGeneratingSTL,
                   let stlExportURL = viewModel.stlExportURL {
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

            metricRow(title: "Markers no STL", value: formattedSTLExportedImplantCount)
            metricRow(title: "tagPoses atuais", value: formattedCurrentExportableTagPoseCount)
            metricRow(title: "tagPoses export", value: formattedLastSTLExportTagPoseCount)
            metricRow(title: "canExportSTL", value: formattedCanExportSTL)
            metricRow(title: "Export iniciado", value: formattedBool(viewModel.didStartSTLExportForCurrentScan))
            metricRow(title: "Status STL", value: formattedSTLExportStatus)
            metricRow(title: "URL STL existe", value: formattedSTLExportURLExists)
            metricRow(title: "Arquivo existe", value: formattedSTLExportFileExists)
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

private struct ScannerTagCoverageItem: Identifiable {
    let markerId: Int
    let label: String
    let progress: Double

    var id: Int {
        markerId
    }
}

private struct ScannerGlassPanel<Content: View>: View {
    let cornerRadius: CGFloat
    let content: Content

    init(cornerRadius: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        content
            .padding(12)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(Color.black.opacity(0.58))
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            }
            .foregroundStyle(.white)
    }
}

private struct ScannerCrosshairView: View {
    let accentColor: Color

    var body: some View {
        ZStack {
            Rectangle()
                .fill(accentColor.opacity(0.62))
                .frame(width: 22, height: 1)

            Rectangle()
                .fill(accentColor.opacity(0.62))
                .frame(width: 1, height: 22)
        }
        .shadow(color: accentColor.opacity(0.28), radius: 4, x: 0, y: 0)
        .allowsHitTesting(false)
    }
}

private struct ScannerCircleButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let accentColor: Color
    let isEnabled: Bool
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(foregroundColor)
                .frame(width: 46, height: 46)
                .background {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay {
                            Circle()
                                .fill(Color.black.opacity(isActive ? 0.42 : 0.62))
                        }
                }
                .overlay {
                    Circle()
                        .stroke(borderColor, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.42)
        .accessibilityLabel(accessibilityLabel)
    }

    private var foregroundColor: Color {
        if !isEnabled {
            return .white.opacity(0.38)
        }

        return isActive ? accentColor : .white.opacity(0.88)
    }

    private var borderColor: Color {
        isActive ? accentColor.opacity(0.50) : Color.white.opacity(0.10)
    }
}

private struct ScannerTagCoverageRow: View {
    let label: String
    let progress: Double
    let accentColor: Color

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)

            Spacer(minLength: 2)

            Text("\(Int(round(normalizedProgress * 100.0)))%")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.62))
                .monospacedDigit()
        }
        .frame(height: 26)
        .padding(.horizontal, 7)
        .background(Color.white.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var normalizedProgress: Double {
        guard progress.isFinite else {
            return 0
        }

        let clamped = min(max(progress / 100.0, 0.0), 1.0)
        return clamped >= 0.995 ? 1.0 : clamped
    }
}

private struct ScannerDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.12))
            .frame(width: 1, height: 28)
    }
}

private struct RingProgressView: View {
    let progress: Double
    let accentColor: Color
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.13), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(
                    accentColor.opacity(0.92),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: accentColor.opacity(0.35), radius: 3, x: 0, y: 0)
        }
    }
}

private struct STLViewerPresentation: Identifiable {
    let id = UUID()
    let fileURL: URL
}
