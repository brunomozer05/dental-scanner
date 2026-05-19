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
    private let useSafeDebugPanelOnly = true
    private let showAdvancedPoseDebug = false
    private let showMotionDebug = false
    private let showStaticStabilityDebug = false
    private let showPlanarDebug = false
    private let showQualityDebug = false

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

                        if useSafeDebugPanelOnly {
                            EmergencyScannerDebugPanelView {
                                isDebugPanelExpanded = false
                            }
                            .frame(width: 260)
                            .padding(12)
                        } else {
                            debugPanel(isLandscape: true)
                                .frame(width: 320)
                                .padding(12)
                        }
                    }
                }
                .zIndex(4)
            }
        }
        .background(Color.black)
        .ignoresSafeArea(.all)
        .supportedInterfaceOrientations(.landscape)
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
                systemImage: "gearshape",
                accessibilityLabel: "Abrir debug",
                accentColor: scannerAccentColor,
                isEnabled: true,
                isActive: false
            ) {
                isDebugPanelExpanded.toggle()
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

    private func debugPanel(isLandscape _: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Debug")
                    .font(.headline)

                Spacer()

                Text(formattedCameraState)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                basicDebugSection

                if showAdvancedPoseDebug {
                    debugSummarySection
                    poseDebugSection
                }

                if showStaticStabilityDebug {
                    staticPoseStabilitySection
                }

                if showQualityDebug {
                    dualMarkerDebugSection
                    scanQualitySection
                }

                if showMotionDebug || showPlanarDebug {
                    scanQualitySection
                }

                if showAdvancedPoseDebug {
                    scanDebugControl
                    errorDebugSection
                }
            }
        }
        .padding(12)
        .foregroundStyle(.white)
        .background(panelBackgroundColor.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var basicDebugSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Debug seguro")
                .font(.subheadline.weight(.semibold))

            basicDebugRow(title: "Estado atual", value: formattedScanState)
            basicDebugRow(title: "Perfil marker", value: viewModel.markerProfile.debugTitle)
            basicDebugRow(title: "isGeneratingSTL", value: formattedBool(viewModel.isGeneratingSTL))
            basicDebugRow(title: "STL URL existe", value: formattedSTLExportURLExists)
            basicDebugRow(title: "Erro STL", value: formattedSTLExportError)
            basicDebugRow(title: "tagPoses atuais", value: formattedCurrentExportableTagPoseCount)
        }
    }

    private func basicDebugRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            Text(value.isEmpty ? missingDebugValue : value)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .font(.caption.weight(.semibold))
    }

    private var debugSummarySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            metricRow(title: "Lanterna", value: formattedTorchState)
            metricRow(title: "FPS", value: safeDouble(viewModel.estimatedFPS, decimals: 1))
            metricRow(title: "Resolucao", value: formattedResolution)
            metricRow(title: "Intrinseca", value: viewModel.isIntrinsicMatrixAvailable ? "Disponivel" : "Indisponivel")
            metricRow(title: "IDs", value: formattedDetectedMarkerIds)
            metricRow(title: "Perfil marker", value: viewModel.markerProfile.debugTitle)
            metricRow(title: "Marker size", value: safeUnit(viewModel.poseMarkerSizeMillimeters, decimals: 1, unit: "mm"))
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
    private var staticPoseStabilitySection: some View {
        if viewModel.markerProfile == .dualArucoV2 {
            VStack(alignment: .leading, spacing: 6) {
                Text("Static Pose Stability")
                    .font(.subheadline.weight(.semibold))

                metricRow(title: "Modo", value: formattedBool(viewModel.staticPoseStabilityMode))
                metricRow(
                    title: "Janela",
                    value: safeUnit(viewModel.staticPoseStabilityWindowSeconds, decimals: 1, unit: "s")
                )
                metricRow(title: "Referencia", value: formattedBool(viewModel.staticPoseReferenceCaptured))
                metricRow(title: "Diagnostico", value: viewModel.staticPoseGlobalDiagnosis)

                if !viewModel.staticPoseStabilityMode {
                    metricRow(title: "Static markers", value: missingDebugValue)
                } else if viewModel.staticPoseMarkerDiagnostics.isEmpty {
                    metricRow(title: "Static markers", value: missingDebugValue)
                } else {
                    ForEach(viewModel.staticPoseMarkerDiagnostics) { state in
                        VStack(alignment: .leading, spacing: 4) {
                            metricRow(title: "Marker estatico", value: "M\(state.markerId)")
                            metricRow(title: "Samples", value: "\(state.sampleCount)")
                            metricRow(title: "Pos std", value: formattedStaticMillimeters(state.positionStdDevMm))
                            metricRow(title: "Rot std", value: formattedStaticDegrees(state.rotationStdDevDegrees))
                            metricRow(title: "Normal std", value: formattedStaticDegrees(state.normalStdDevDegrees))
                            metricRow(title: "Dual ratio", value: formattedStaticRatio(state.dualTagRatio))
                            metricRow(title: "Top fallback", value: formattedStaticRatio(state.topFallbackRatio))
                            metricRow(title: "Bottom fallback", value: formattedStaticRatio(state.bottomFallbackRatio))
                        }
                        .padding(.vertical, 4)
                    }
                }

                if viewModel.staticPoseStabilityMode,
                   let plane = viewModel.staticPosePlaneDiagnostics {
                    Text("Plano estatico")
                        .font(.caption.weight(.semibold))

                    metricRow(title: "Plane samples", value: "\(plane.sampleCount)")
                    metricRow(title: "Plane avg mean", value: formattedStaticMillimeters(plane.planeAverageErrorMeanMm))
                    metricRow(title: "Plane max worst", value: formattedStaticMillimeters(plane.planeMaximumErrorWorstMm))
                }
            }
        }
    }

    @ViewBuilder
    private var dualMarkerDebugSection: some View {
        if viewModel.markerProfile == .dualArucoV2 {
            VStack(alignment: .leading, spacing: 6) {
                Text("Markers v2")
                    .font(.subheadline.weight(.semibold))

                if viewModel.dualMarkerDebugStates.isEmpty {
                    metricRow(title: "Markers v2", value: "Sem dados v2 ainda")
                } else {
                    ForEach(viewModel.dualMarkerDebugStates) { state in
                        VStack(alignment: .leading, spacing: 4) {
                            metricRow(title: "Marker fisico", value: "ID \(state.physicalMarkerId)")
                            metricRow(title: "Top agora \(state.topTagId)", value: formattedBool(state.topTagRawDetected))
                            metricRow(title: "Bottom agora \(state.bottomTagId)", value: formattedBool(state.bottomTagRawDetected))
                            metricRow(title: "Bottom recente", value: formattedBool(state.bottomTagRecentlySeen))
                            metricRow(title: "Modo", value: formattedDualMarkerPoseMode(state))
                            metricRow(title: "Dual validos", value: "\(state.scanDualTagFrameCount)")
                            metricRow(title: "Top fallback validos", value: "\(state.scanTopFallbackFrameCount)")
                            metricRow(title: "Bottom fallback validos", value: "\(state.scanBottomFallbackFrameCount)")
                            metricRow(title: "Dual %", value: formattedDualMarkerScanDualPercent(state))
                            metricRow(title: "Dual angular", value: formattedDualMarkerAngularCoverage(state))
                            metricRow(title: "Modo dominante", value: formattedDualMarkerDominantMode(state))
                            metricRow(title: "Erro reproj.", value: formattedDualMarkerReprojectionError(state))
                            metricRow(title: "Pontos", value: formattedDualMarkerPointCount(state))
                            metricRow(title: "Aviso", value: formattedDualMarkerDetectionWarning(state))
                        }
                        .padding(.vertical, 4)
                    }
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
            isDebugPanelExpanded.toggle()
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

    private var missingDebugValue: String {
        "\u{2014}"
    }

    private func safeDouble(_ value: Double?, decimals: Int = 2) -> String {
        guard let value, value.isFinite else {
            return missingDebugValue
        }

        let safeDecimals = min(max(decimals, 0), 6)
        return String(format: "%.\(safeDecimals)f", value)
    }

    private func safeSignedDouble(_ value: Double?, decimals: Int = 2) -> String {
        guard let value, value.isFinite else {
            return missingDebugValue
        }

        let safeDecimals = min(max(decimals, 0), 6)
        let magnitude = String(format: "%.\(safeDecimals)f", abs(value))
        return "\(value >= 0 ? "+" : "-")\(magnitude)"
    }

    private func safeUnit(_ value: Double?, decimals: Int = 2, unit: String) -> String {
        let number = safeDouble(value, decimals: decimals)
        guard number != missingDebugValue else {
            return missingDebugValue
        }

        return "\(number) \(unit)"
    }

    private func safeSignedUnit(_ value: Double?, decimals: Int = 2, unit: String) -> String {
        let number = safeSignedDouble(value, decimals: decimals)
        guard number != missingDebugValue else {
            return missingDebugValue
        }

        return "\(number) \(unit)"
    }

    private func safePercent(_ value: Double?, decimals: Int = 0) -> String {
        let number = safeDouble(value, decimals: decimals)
        guard number != missingDebugValue else {
            return missingDebugValue
        }

        return "\(number)%"
    }

    private func formattedCoveragePercent(_ percent: Double) -> String {
        "\(roundedCoveragePercent(percent))%"
    }

    private func formattedPreciseCoveragePercent(_ percent: Double) -> String {
        guard percent.isFinite else {
            return missingDebugValue
        }

        let clampedPercent = min(max(percent, 0.0), 100.0)
        return safePercent(clampedPercent, decimals: 1)
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
        safeUnit(viewModel.scanAverageDistanceMm, decimals: 1, unit: "mm")
    }

    private var formattedScanAverageReprojectionError: String {
        safeUnit(viewModel.scanAverageReprojectionError, decimals: 2, unit: "px")
    }

    private var formattedScanPoseJitter: String {
        safeUnit(viewModel.scanPositionJitterMm, decimals: 2, unit: "mm")
    }

    private var formattedScanRotationJitter: String {
        safeUnit(viewModel.scanRotationJitterDegrees, decimals: 2, unit: "deg")
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
            return missingDebugValue
        }

        return viewModel.lastSTLExportMarkerIds.map(String.init).joined(separator: ", ")
    }

    private var formattedLastSTLExportBottomGeometry: String {
        guard let bottomTagSize = viewModel.lastSTLExportBottomTagSizeMillimeters,
              let bottomCenterY = viewModel.lastSTLExportBottomCenterYMillimeters,
              bottomTagSize.isFinite,
              bottomCenterY.isFinite
        else {
            return missingDebugValue
        }

        return "\(safeUnit(bottomTagSize, decimals: 1, unit: "mm")) / y \(safeUnit(bottomCenterY, decimals: 2, unit: "mm"))"
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
            return missingDebugValue
        }

        return markerIds.map(String.init).joined(separator: ", ")
    }

    private var formattedScanTagCoverageSummary: String {
        guard !viewModel.scanTagCoverages.isEmpty else {
            return missingDebugValue
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

    private var formattedPlanarAverageError: String {
        formattedMillimeterValue(viewModel.scanPlanarAverageErrorMm)
    }

    private var formattedPlanarMaximumError: String {
        formattedMillimeterValue(viewModel.scanPlanarMaximumErrorMm)
    }

    private var formattedPlanarMarkerDistances: String {
        guard !viewModel.scanMarkerPlanarDistancesMm.isEmpty else {
            return missingDebugValue
        }

        return viewModel.scanMarkerPlanarDistancesMm.keys
            .sorted()
            .compactMap { markerId in
                guard let distanceMm = viewModel.scanMarkerPlanarDistancesMm[markerId],
                      distanceMm.isFinite
                else {
                    return nil
                }

                return "M\(markerId): \(safeSignedUnit(distanceMm, decimals: 2, unit: "mm"))"
            }
            .joined(separator: "\n")
    }

    private var formattedMarkerPairDistances: String {
        guard !viewModel.scanMarkerPairDistances.isEmpty else {
            return missingDebugValue
        }

        return viewModel.scanMarkerPairDistances
            .map { pairDistance in
                "M\(pairDistance.firstMarkerId)-M\(pairDistance.secondMarkerId): \(safeUnit(pairDistance.distanceMm, decimals: 2, unit: "mm"))"
            }
            .joined(separator: "\n")
    }

    private var formattedMotionAngularVelocity: String {
        guard viewModel.currentMotionFrameQuality.isRecent else {
            return missingDebugValue
        }

        let value = viewModel.currentMotionFrameQuality.angularVelocityRadPerSec
        return safeUnit(value, decimals: 3, unit: "rad/s")
    }

    private var formattedMotionAcceleration: String {
        guard viewModel.currentMotionFrameQuality.isRecent else {
            return missingDebugValue
        }

        let value = viewModel.currentMotionFrameQuality.accelerationMagnitude
        return safeUnit(value, decimals: 3, unit: "g")
    }

    private var formattedMotionStability: String {
        guard viewModel.currentMotionFrameQuality.isRecent else {
            return missingDebugValue
        }

        let value = viewModel.currentMotionFrameQuality.stabilityScore
        guard value.isFinite else {
            return missingDebugValue
        }

        let recency = viewModel.currentMotionFrameQuality.isRecent ? "recente" : "neutro"
        return "\(safePercent(value * 100.0)) \(recency)"
    }

    private var formattedMotionWarning: String {
        let quality = viewModel.currentMotionFrameQuality
        guard quality.isRecent else {
            return missingDebugValue
        }

        if quality.stabilityScore < 0.45 {
            return "Mantenha o celular estavel"
        }

        if !quality.isStable {
            return "Movimento moderado: menor confianca"
        }

        return missingDebugValue
    }

    private func formattedMillimeterValue(_ value: Double?) -> String {
        safeUnit(value, decimals: 2, unit: "mm")
    }

    private var formattedResolution: String {
        guard let resolution = viewModel.frameResolution else {
            return missingDebugValue
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
            return missingDebugValue
        }

        return "\(resolution.width) x \(resolution.height)"
    }

    private var formattedDetectedMarkerIds: String {
        guard !viewModel.detectedMarkerIds.isEmpty else {
            return missingDebugValue
        }

        return viewModel.detectedMarkerIds.map(String.init).joined(separator: ", ")
    }

    private var formattedArucoBytesPerRow: String {
        guard let bytesPerRow = viewModel.arucoBytesPerRow else {
            return missingDebugValue
        }

        return "\(bytesPerRow)"
    }

    private var formattedRejectedCandidates: String {
        guard let rejectedCandidateCount = viewModel.arucoRejectedCandidateCount else {
            return missingDebugValue
        }

        return "\(rejectedCandidateCount)"
    }

    private var formattedPoseMarkerId: String {
        guard let poseMarkerId = viewModel.rawPoseResult?.markerId ?? viewModel.stablePoseResult?.markerId else {
            return missingDebugValue
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

    private var scanMinimumDualTagFrameBinding: Binding<Int> {
        Binding(
            get: { viewModel.scanMinimumDualTagFrameCount },
            set: { viewModel.setScanMinimumDualTagFrameCount($0) }
        )
    }

    private var scanRequiredDualAngularCoverageBinding: Binding<Double> {
        Binding(
            get: { viewModel.scanRequiredDualAngularCoveragePercent },
            set: { viewModel.setScanRequiredDualAngularCoveragePercent($0) }
        )
    }

    private var scanMaximumFinalNormalOutlierBinding: Binding<Double> {
        Binding(
            get: { viewModel.scanMaximumFinalNormalOutlierDegrees },
            set: { viewModel.setScanMaximumFinalNormalOutlierDegrees($0) }
        )
    }

    private var precisionModeV2Binding: Binding<Bool> {
        Binding(
            get: { viewModel.precisionModeV2 },
            set: { viewModel.setPrecisionModeV2($0) }
        )
    }

    private var staticPoseStabilityModeBinding: Binding<Bool> {
        Binding(
            get: { viewModel.staticPoseStabilityMode },
            set: { viewModel.setStaticPoseStabilityMode($0) }
        )
    }

    private var showDistanceGuideBinding: Binding<Bool> {
        Binding(
            get: { viewModel.showDistanceGuide },
            set: { viewModel.setShowDistanceGuide($0) }
        )
    }

    private var formattedRawPoseDistance: String {
        safeUnit(viewModel.rawPoseResult?.distanceMm, decimals: 1, unit: "mm")
    }

    private var formattedStablePoseDistance: String {
        safeUnit(viewModel.stablePoseResult?.distanceMm, decimals: 1, unit: "mm")
    }

    private var formattedPoseReprojectionError: String {
        safeUnit(viewModel.rawPoseResult?.reprojectionError, decimals: 2, unit: "px")
    }

    private var formattedPoseMode: String {
        viewModel.rawPoseResult?.poseSource.debugTitle ?? missingDebugValue
    }

    private var formattedPosePointCount: String {
        guard let usedPointCount = viewModel.rawPoseResult?.usedPointCount else {
            return missingDebugValue
        }

        return "\(usedPointCount)"
    }

    private func formattedDualMarkerPoseMode(_ state: DualArucoMarkerDebugState) -> String {
        state.poseSource?.debugTitle ?? "missing"
    }

    private func formattedDualMarkerVisualMode(_ state: DualArucoMarkerDebugState) -> String {
        state.visualModeTitle ?? missingDebugValue
    }

    private func formattedDualMarkerVisualAge(_ state: DualArucoMarkerDebugState) -> String {
        formattedVisualAge(state.visualLastSeenAgeSeconds)
    }

    private func formattedDualMarkerVisualDualAge(_ state: DualArucoMarkerDebugState) -> String {
        formattedVisualAge(state.visualLastDualSeenAgeSeconds)
    }

    private func formattedVisualAge(_ ageSeconds: Double?) -> String {
        safeUnit(ageSeconds, decimals: 2, unit: "s")
    }

    private func formattedStaticMillimeters(_ value: Double?) -> String {
        safeUnit(value, decimals: 3, unit: "mm")
    }

    private func formattedStaticDegrees(_ value: Double?) -> String {
        safeUnit(value, decimals: 3, unit: "deg")
    }

    private func formattedDegreesValue(_ value: Double?) -> String {
        safeUnit(value, decimals: 1, unit: "deg")
    }

    private func formattedStaticPixels(_ value: Double?) -> String {
        safeUnit(value, decimals: 3, unit: "px")
    }

    private func formattedStaticRatio(_ ratio: Double) -> String {
        safePercent(ratio.isFinite ? ratio * 100.0 : nil)
    }

    private func formattedStaticPairDistance(
        _ state: ScannerViewModel.StaticPosePairDistanceDiagnostics
    ) -> String {
        let mean = formattedStaticMillimeters(state.meanDistanceMm)
        let std = formattedStaticMillimeters(state.standardDeviationMm)
        let peak = formattedStaticMillimeters(state.peakToPeakMm)
        let minimum = formattedStaticMillimeters(state.minimumDistanceMm)
        let maximum = formattedStaticMillimeters(state.maximumDistanceMm)

        return "mean \(mean), std \(std), min \(minimum), max \(maximum), p2p \(peak)"
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
            return missingDebugValue
        }

        return safeUnit(area, decimals: 0, unit: "px2")
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
            return missingDebugValue
        }

        return safeUnit(reprojectionError, decimals: 2, unit: "px")
    }

    private func formattedDualMarkerPointCount(_ state: DualArucoMarkerDebugState) -> String {
        guard let usedPointCount = state.usedPointCount else {
            return missingDebugValue
        }

        return "\(usedPointCount)"
    }

    private func formattedDualMarkerImageX(_ state: DualArucoMarkerDebugState) -> String {
        guard let normalizedImageX = state.normalizedImageX,
              normalizedImageX.isFinite
        else {
            return missingDebugValue
        }

        return safeDouble(normalizedImageX, decimals: 2)
    }

    private func formattedDualMarkerImageY(_ state: DualArucoMarkerDebugState) -> String {
        guard let normalizedImageY = state.normalizedImageY,
              normalizedImageY.isFinite
        else {
            return missingDebugValue
        }

        return safeDouble(normalizedImageY, decimals: 2)
    }

    private func formattedDualMarkerNearestImageEdge(
        _ state: DualArucoMarkerDebugState
    ) -> String {
        state.nearestImageEdge ?? missingDebugValue
    }

    private func formattedDualMarkerNearImageEdge(
        _ state: DualArucoMarkerDebugState
    ) -> String {
        guard state.normalizedImageX != nil,
              state.normalizedImageY != nil
        else {
            return missingDebugValue
        }

        return formattedBool(state.nearImageEdge)
    }

    private func formattedDualMarkerImageEdgeDistance(
        _ state: DualArucoMarkerDebugState
    ) -> String {
        guard let imageEdgeDistancePercent = state.imageEdgeDistancePercent,
              imageEdgeDistancePercent.isFinite
        else {
            return missingDebugValue
        }

        return safePercent(imageEdgeDistancePercent)
    }

    private func formattedDualMarkerNearImageEdgeFrames(
        _ state: DualArucoMarkerDebugState
    ) -> String {
        guard state.scanNearImageEdgeFramePercent.isFinite else {
            return "\(state.scanNearImageEdgeFrameCount)"
        }

        return String(
            format: "%d (%.0f%%)",
            state.scanNearImageEdgeFrameCount,
            state.scanNearImageEdgeFramePercent
        )
    }

    private func formattedDualMarkerNearImageEdgeMode(
        _ state: DualArucoMarkerDebugState
    ) -> String {
        state.scanNearImageEdgeDominantPoseSource?.debugTitle ?? missingDebugValue
    }

    private func formattedDualMarkerScanDualPercent(_ state: DualArucoMarkerDebugState) -> String {
        guard state.scanDualTagPosePercent.isFinite else {
            return missingDebugValue
        }

        return safePercent(state.scanDualTagPosePercent)
    }

    private func formattedDualMarkerAngularCoverage(_ state: DualArucoMarkerDebugState) -> String {
        guard state.scanDualAngularCoveragePercent.isFinite else {
            return missingDebugValue
        }

        return safePercent(state.scanDualAngularCoveragePercent, decimals: 1)
    }

    private func formattedDualMarkerDominantMode(_ state: DualArucoMarkerDebugState) -> String {
        state.scanDominantPoseSource?.debugTitle ?? missingDebugValue
    }

    private func formattedDualMarkerPlanarDistance(_ state: DualArucoMarkerDebugState) -> String {
        guard let distanceMm = state.finalPlanarDistanceMm,
              distanceMm.isFinite
        else {
            return missingDebugValue
        }

        return safeSignedUnit(distanceMm, decimals: 2, unit: "mm")
    }

    private func formattedDualMarkerDetectionWarning(_ state: DualArucoMarkerDebugState) -> String {
        state.scanConsistencyWarning ??
            state.imageEdgeWarning ??
            (state.finalRefinementSmallBottomDiscardedObservationCount > 0
                ? "Bottom pequena / baixa confianca"
                : nil) ??
            state.detectionWarning ??
            missingDebugValue
    }

    private func formattedDualMarkerFinalAverageReprojectionError(
        _ state: DualArucoMarkerDebugState
    ) -> String {
        guard let error = state.finalRefinementAverageReprojectionError,
              error.isFinite
        else {
            return missingDebugValue
        }

        return safeUnit(error, decimals: 2, unit: "px")
    }

    private func formattedDualMarkerFinalAverageQualityScore(
        _ state: DualArucoMarkerDebugState
    ) -> String {
        guard let score = state.finalRefinementAverageQualityScore,
              score.isFinite
        else {
            return missingDebugValue
        }

        return safeDouble(score, decimals: 2)
    }

    private func formattedDualMarkerFinalAverageImageX(
        _ state: DualArucoMarkerDebugState
    ) -> String {
        guard let normalizedImageX = state.finalRefinementAverageNormalizedImageX,
              normalizedImageX.isFinite
        else {
            return missingDebugValue
        }

        return safeDouble(normalizedImageX, decimals: 2)
    }

    private func formattedDualMarkerFinalAverageImageY(
        _ state: DualArucoMarkerDebugState
    ) -> String {
        guard let normalizedImageY = state.finalRefinementAverageNormalizedImageY,
              normalizedImageY.isFinite
        else {
            return missingDebugValue
        }

        return safeDouble(normalizedImageY, decimals: 2)
    }

    private func formattedDualMarkerFinalAverageImageEdgeMargin(
        _ state: DualArucoMarkerDebugState
    ) -> String {
        guard let edgeMargin = state.finalRefinementAverageImageEdgeMargin,
              edgeMargin.isFinite
        else {
            return missingDebugValue
        }

        return safePercent(edgeMargin * 100.0)
    }

    private func formattedDualMarkerFinalPositionVariation(
        _ state: DualArucoMarkerDebugState
    ) -> String {
        guard let positionVariation = state.finalRefinementPositionVariationMm,
              positionVariation.isFinite
        else {
            return missingDebugValue
        }

        return safeUnit(positionVariation, decimals: 2, unit: "mm")
    }

    private func formattedDualMarkerFinalRotationVariation(
        _ state: DualArucoMarkerDebugState
    ) -> String {
        guard let rotationVariation = state.finalRefinementRotationVariationDegrees,
              rotationVariation.isFinite
        else {
            return missingDebugValue
        }

        return safeUnit(rotationVariation, decimals: 2, unit: "deg")
    }

    private func formattedDualMarkerFinalAverageNormal(
        _ state: DualArucoMarkerDebugState
    ) -> String {
        guard let normal = state.finalRefinementAverageNormal,
              normal.x.isFinite,
              normal.y.isFinite,
              normal.z.isFinite
        else {
            return missingDebugValue
        }

        return "x \(safeDouble(normal.x, decimals: 2)) y \(safeDouble(normal.y, decimals: 2)) z \(safeDouble(normal.z, decimals: 2))"
    }

    private func formattedDualMarkerNormalStdDev(_ state: DualArucoMarkerDebugState) -> String {
        formattedDegreesValue(state.finalRefinementNormalStdDevDegrees)
    }

    private func formattedDualMarkerNormalPeak(_ state: DualArucoMarkerDebugState) -> String {
        formattedDegreesValue(state.finalRefinementNormalPeakToPeakDegrees)
    }

    private func formattedDualMarkerWorstNormalDifference(
        _ state: DualArucoMarkerDebugState
    ) -> String {
        formattedDegreesValue(state.finalRefinementWorstNormalDifferenceDegrees)
    }

    private func formattedDualMarkerDualNormalStdDev(_ state: DualArucoMarkerDebugState) -> String {
        formattedDegreesValue(state.finalRefinementDualTagNormalStdDevDegrees)
    }

    private func formattedDualMarkerFallbackNormalStdDev(
        _ state: DualArucoMarkerDebugState
    ) -> String {
        formattedDegreesValue(state.finalRefinementFallbackNormalStdDevDegrees)
    }

    private func formattedDualMarkerDualFallbackNormalDifference(
        _ state: DualArucoMarkerDebugState
    ) -> String {
        guard let value = state.finalRefinementDualFallbackNormalDifferenceDegrees,
              value.isFinite
        else {
            return missingDebugValue
        }

        let warning = value > viewModel.scanMaximumFinalNormalOutlierDegrees
            ? " fallback alterando inclinacao"
            : ""
        return "\(safeUnit(value, decimals: 1, unit: "deg"))\(warning)"
    }

    private func formattedDualMarkerAverageMotionScore(
        _ state: DualArucoMarkerDebugState
    ) -> String {
        guard let score = state.finalRefinementAverageMotionStabilityScore,
              score.isFinite
        else {
            return missingDebugValue
        }

        return safePercent(score * 100.0)
    }

    private func formattedDualMarkerFinalDominantMode(_ state: DualArucoMarkerDebugState) -> String {
        state.finalRefinementDominantPoseSource?.debugTitle ?? missingDebugValue
    }

    private func formattedDualMarkerFinalConfidence(_ state: DualArucoMarkerDebugState) -> String {
        state.finalRefinementConfidence.rawValue
    }

    private func formattedDualMarkerFinalConfidenceReason(
        _ state: DualArucoMarkerDebugState
    ) -> String {
        state.finalRefinementConfidenceReason ?? missingDebugValue
    }

    private func formattedDualMarkerDiscardReason(_ state: DualArucoMarkerDebugState) -> String {
        state.finalRefinementDiscardReason ?? state.scanDualTagRejectionReason ?? missingDebugValue
    }

    private var formattedImplantPositions: String {
        guard !viewModel.implantPoseResults.isEmpty else {
            return missingDebugValue
        }

        return viewModel.implantPoseResults.map { implantPose in
            "ID \(implantPose.markerId): x \(safeDouble(implantPose.translationVector.x, decimals: 1)), y \(safeDouble(implantPose.translationVector.y, decimals: 1)), z \(safeUnit(implantPose.translationVector.z, decimals: 1, unit: "mm"))"
        }
        .joined(separator: "\n")
    }

    private var formattedImplantDistance: String {
        guard let implantPose = viewModel.implantPoseResult else {
            return missingDebugValue
        }

        return "ID \(implantPose.markerId): \(safeUnit(implantPose.distanceMm, decimals: 1, unit: "mm"))"
    }

    private var formattedSelectedImplantMarkers: String {
        guard !viewModel.selectedImplantMarkerIds.isEmpty else {
            return missingDebugValue
        }

        return viewModel.selectedImplantMarkerIds.map { "ID \($0)" }.joined(separator: " x ")
    }

    private var formattedSelectedTagDistance: String {
        safeUnit(viewModel.selectedTagDistanceMm, decimals: 1, unit: "mm")
    }

    private var formattedSelectedImplantDistance: String {
        safeUnit(viewModel.selectedImplantDistanceMm, decimals: 1, unit: "mm")
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
            return missingDebugValue
        }

        guard let distanceMm = parsedScaleValidationRealDistanceMm else {
            return "Valor invalido"
        }

        return safeUnit(distanceMm, decimals: 2, unit: "mm")
    }

    private var formattedScaleValidationAppDistance: String {
        formattedSelectedImplantDistance
    }

    private var formattedSTLExportedImplantCount: String {
        guard viewModel.stlExportedImplantCount > 0 else {
            return missingDebugValue
        }

        return "\(viewModel.stlExportedImplantCount)"
    }

    private var formattedSTLExportFileName: String {
        viewModel.stlExportURL?.lastPathComponent ?? missingDebugValue
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

    private func formattedPercentValue(_ value: Double?) -> String {
        safePercent(value, decimals: 2)
    }

    private func formattedCorrectionFactor(_ value: Double?) -> String {
        guard let value, value.isFinite else {
            return missingDebugValue
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
            if viewModel.markerProfile == .dualArucoV2 {
                metricRow(title: "dualTagReady", value: formattedBool(viewModel.scanDualTagReady))
                metricRow(title: "dualAngularReady", value: formattedBool(viewModel.scanDualAngularCoverageReady))
                metricRow(title: "precisionModeV2", value: formattedBool(viewModel.precisionModeV2))
                metricRow(title: "staticPoseMode", value: formattedBool(viewModel.staticPoseStabilityMode))
                metricRow(title: "IMU angular", value: formattedMotionAngularVelocity)
                metricRow(title: "IMU accel", value: formattedMotionAcceleration)
                metricRow(title: "IMU stability", value: formattedMotionStability)
                metricRow(title: "Frames motion pen.", value: "\(viewModel.scanMotionPenalizedFrameCount)")
                metricRow(title: "Obs motion desc.", value: "\(viewModel.scanMotionDiscardedObservationCount)")
                metricRow(title: "Aviso IMU", value: formattedMotionWarning)
                metricRow(title: "Plane avg error", value: formattedPlanarAverageError)
                metricRow(title: "Plane max error", value: formattedPlanarMaximumError)
                metricRow(title: "Plane markers", value: formattedPlanarMarkerDistances)
                metricRow(title: "Dist markers", value: formattedMarkerPairDistances)
                metricRow(title: "Scan confidence", value: viewModel.scanFinalConfidenceSummary)
                metricRow(title: "Worst marker", value: viewModel.scanFinalWorstMarkerSummary)
                metricRow(title: "Main issue", value: viewModel.scanFinalMainIssueSummary)
            }
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

            if viewModel.markerProfile == .dualArucoV2 {
                Stepper(
                    value: scanMinimumDualTagFrameBinding,
                    in: viewModel.scanMinimumDualTagFrameRange,
                    step: 1
                ) {
                    HStack(alignment: .center) {
                        Text("Frames dual-tag min")
                            .foregroundStyle(.secondary)

                        Spacer()

                        Text("\(viewModel.scanMinimumDualTagFrameCount)")
                            .monospacedDigit()
                    }
                }

                Stepper(
                    value: scanRequiredDualAngularCoverageBinding,
                    in: viewModel.scanRequiredDualAngularCoverageRange,
                    step: viewModel.scanAngularCoverageStepPercent
                ) {
                    HStack(alignment: .center) {
                        Text("Cobertura dual-tag")
                            .foregroundStyle(.secondary)

                        Spacer()

                        Text(formattedPreciseCoveragePercent(
                            viewModel.scanRequiredDualAngularCoveragePercent
                        ))
                        .monospacedDigit()
                    }
                }

                Toggle("Modo precisao v2", isOn: precisionModeV2Binding)

                Stepper(
                    value: scanMaximumFinalNormalOutlierBinding,
                    in: viewModel.scanMaximumFinalNormalOutlierDegreesRange,
                    step: viewModel.scanMaximumFinalNormalOutlierDegreesStep
                ) {
                    HStack(alignment: .center) {
                        Text("Outlier normal final")
                            .foregroundStyle(.secondary)

                        Spacer()

                        Text(formattedDegreesValue(viewModel.scanMaximumFinalNormalOutlierDegrees))
                            .monospacedDigit()
                    }
                }

                Toggle("Static Pose Stability Test", isOn: staticPoseStabilityModeBinding)

                Button {
                    viewModel.captureStaticPoseReference()
                } label: {
                    Label("Capturar referencia estatica", systemImage: "camera.metering.center.weighted")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.staticPoseStabilityMode)
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

                    Text(safeUnit(viewModel.poseMarkerSizeMillimeters, decimals: 1, unit: "mm"))
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

private struct EmergencyScannerDebugPanelView: View {
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Debug")
                    .font(.headline)

                Spacer()

                Button("Fechar") {
                    onClose()
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
            }

            Text("Painel debug carregado")
                .font(.caption.weight(.semibold))

            Text("Modo seguro ativo")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.72))
        }
        .padding(12)
        .foregroundStyle(.white)
        .background(Color.black.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onAppear {
            print("Scanner debug panel opened in safe mode")
        }
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
