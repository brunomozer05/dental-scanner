import SwiftUI
import UIKit

struct ScannerView: View {
    let onCancel: (() -> Void)?

    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel = ScannerViewModel()
    @State private var scaleValidationRealDistanceText = ""
    @State private var previewOrientation: CameraPreviewOrientation = .landscapeRight
    @State private var scannerDebugPanelVisible = false
    @State private var stlViewerPresentation: STLViewerPresentation?

    private let panelBackgroundColor = Color(red: 0.11, green: 0.11, blue: 0.12)
    private let chipBackgroundColor = Color(red: 0.16, green: 0.16, blue: 0.18)
    private let scannerAccentColor = Color(red: 0.23, green: 0.51, blue: 0.96)
    private let forceEmergencyDebugPanel = true

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
                        configuration: .default,
                        isSourceReliable: viewModel.distanceGuideSourceReliable,
                        statusText: viewModel.distanceGuideStateTitle
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

                scannerFeedbackPanel
                    .padding(.bottom, 10)

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

            if scannerDebugPanelVisible {
                VStack {
                    Spacer()

                    HStack {
                        Spacer()

                        if forceEmergencyDebugPanel {
                            ScannerDebugEmergencyPanelView(
                                scannerState: formattedScanState(viewModel.scanState),
                                feedbackState: viewModel.scanUserFeedbackState,
                                feedbackMessage: viewModel.scanUserFeedbackMessage,
                                captureProgressPercent: viewModel.scanCaptureProgressPercent,
                                refinementProgressPercent: viewModel.scanRefinementProgressPercent,
                                friendlyBlockingReason: viewModel.scanFriendlyBlockingReason,
                                marker0ProgressPercent: viewModel.debugExpectedMarker0Progress,
                                marker1ProgressPercent: viewModel.debugExpectedMarker1Progress,
                                marker2ProgressPercent: viewModel.debugExpectedMarker2Progress,
                                marker3ProgressPercent: viewModel.debugExpectedMarker3Progress,
                                allExpectedMarkersAt100Percent:
                                    viewModel.debugAllExpectedMarkersAt100Percent,
                                normalFinalizationState:
                                    viewModel.debugNormalFinalizationStateText,
                                normalFinalizationElapsedSeconds:
                                    viewModel.debugNormalFinalizationElapsedSeconds,
                                normalFinalizationMaxSeconds:
                                    viewModel.debugNormalFinalizationMaxSeconds,
                                normalFinalizationStableSeconds:
                                    viewModel.debugNormalFinalizationStableSeconds,
                                normalFinalizationMaturityGatePassed:
                                    viewModel.debugNormalFinalizationMaturityGatePassed,
                                normalFinalizationMinObservationsReached:
                                    viewModel.debugNormalFinalizationMinObservationsReached,
                                normalFinalizationAverageObservationsReached:
                                    viewModel.debugNormalFinalizationAverageObservationsReached,
                                normalFinalizationNormalGatePassed:
                                    viewModel.debugNormalFinalizationNormalGatePassed,
                                normalFinalizationReprojectionGatePassed:
                                    viewModel.debugNormalFinalizationReprojectionGatePassed,
                                normalFinalizationWorstNormalStd:
                                    viewModel.debugNormalFinalizationWorstNormalStd,
                                normalFinalizationAutoExportReason:
                                    viewModel.debugNormalFinalizationAutoExportReason,
                                normalFinalizationBlockedReason:
                                    viewModel.debugNormalFinalizationBlockedReason,
                                finalObservationsM0: viewModel.debugFinalObservationsM0,
                                finalObservationsM1: viewModel.debugFinalObservationsM1,
                                finalObservationsM2: viewModel.debugFinalObservationsM2,
                                finalObservationsM3: viewModel.debugFinalObservationsM3,
                                finalObservationsAverage:
                                    viewModel.debugFinalObservationsAverage,
                                bestCandidateScore:
                                    viewModel.debugBestFinalPoseCandidateScore,
                                bestCandidateGeometryAdjustedScore:
                                    viewModel.debugBestFinalPoseCandidateGeometryAdjustedScore,
                                bestCandidateGeometryPenalty:
                                    viewModel.debugBestFinalPoseCandidateGeometryPenalty,
                                bestCandidateAgeSeconds:
                                    viewModel.debugBestFinalPoseCandidateAgeSeconds,
                                bestCandidateWorstNormalStd:
                                    viewModel.debugBestFinalPoseCandidateWorstNormalStd,
                                bestCandidateWorstReprojection:
                                    viewModel.debugBestFinalPoseCandidateWorstReprojection,
                                bestCandidateObservationsM0:
                                    viewModel.debugBestFinalPoseCandidateObservationsM0,
                                bestCandidateObservationsM1:
                                    viewModel.debugBestFinalPoseCandidateObservationsM1,
                                bestCandidateObservationsM2:
                                    viewModel.debugBestFinalPoseCandidateObservationsM2,
                                bestCandidateObservationsM3:
                                    viewModel.debugBestFinalPoseCandidateObservationsM3,
                                bestCandidateSaved:
                                    viewModel.debugBestFinalPoseCandidateSaved,
                                bestCandidateUpdates:
                                    viewModel.debugBestFinalPoseCandidateUpdateCount,
                                bestCandidateMarkerIds:
                                    viewModel.debugBestFinalPoseCandidateMarkerIds,
                                bestCandidateHasExportablePoses:
                                    viewModel.debugBestFinalPoseCandidateHasExportablePoses,
                                useBestCandidateForExport:
                                    viewModel.debugUseBestFinalPoseCandidateForExport,
                                usedBestCandidate:
                                    viewModel.debugUsedBestFinalPoseCandidate,
                                cameraProfileId:
                                    viewModel.debugCameraProfileId,
                                cameraProfileName:
                                    viewModel.debugCameraProfileName,
                                deviceModelIdentifier:
                                    viewModel.debugDeviceModelIdentifier,
                                deviceMarketingName:
                                    viewModel.debugDeviceMarketingName,
                                selectedCameraLocalizedName:
                                    viewModel.debugSelectedCameraLocalizedName,
                                selectedCameraDeviceType:
                                    viewModel.debugSelectedCameraDeviceType,
                                requestedZoomFactor:
                                    viewModel.debugRequestedZoomFactor,
                                appliedZoomFactor:
                                    viewModel.debugAppliedZoomFactor,
                                currentVideoZoomFactor:
                                    viewModel.debugCurrentVideoZoomFactor,
                                cameraFocusMode:
                                    viewModel.debugCameraFocusMode,
                                cameraExposureMode:
                                    viewModel.debugCameraExposureMode,
                                cameraIsAdjustingFocus:
                                    viewModel.debugCameraIsAdjustingFocus,
                                cameraIsAdjustingExposure:
                                    viewModel.debugCameraIsAdjustingExposure,
                                cameraIntrinsicsAvailable:
                                    viewModel.debugCameraIntrinsicsAvailable,
                                cameraIntrinsicFx:
                                    viewModel.debugCameraIntrinsicFx,
                                cameraIntrinsicFy:
                                    viewModel.debugCameraIntrinsicFy,
                                cameraIntrinsicCx:
                                    viewModel.debugCameraIntrinsicCx,
                                cameraIntrinsicCy:
                                    viewModel.debugCameraIntrinsicCy,
                                activeVideoDimensions:
                                    viewModel.debugActiveVideoDimensions,
                                activeFormatDescription:
                                    viewModel.debugActiveFormatDescription,
                                cameraProfileEvaluationScore:
                                    viewModel.debugCameraProfileEvaluationScore,
                                cameraProfileEvaluationWarnings:
                                    viewModel.debugCameraProfileEvaluationWarnings,
                                relativeMarkerGeometryScore:
                                    viewModel.debugRelativeMarkerGeometryScore,
                                relativeMarkerDistanceStdMean:
                                    viewModel.debugRelativeMarkerDistanceStdMean,
                                relativeMarkerDistanceStdMax:
                                    viewModel.debugRelativeMarkerDistanceStdMax,
                                relativeMarkerDistanceM01:
                                    viewModel.debugRelativeMarkerDistanceM01,
                                relativeMarkerDistanceM02:
                                    viewModel.debugRelativeMarkerDistanceM02,
                                relativeMarkerDistanceM03:
                                    viewModel.debugRelativeMarkerDistanceM03,
                                relativeMarkerDistanceM12:
                                    viewModel.debugRelativeMarkerDistanceM12,
                                relativeMarkerDistanceM13:
                                    viewModel.debugRelativeMarkerDistanceM13,
                                relativeMarkerDistanceM23:
                                    viewModel.debugRelativeMarkerDistanceM23,
                                candidateVsFinalTranslationDeltaMean:
                                    viewModel.debugCandidateVsFinalTranslationDeltaMean,
                                candidateVsFinalRotationDeltaMean:
                                    viewModel.debugCandidateVsFinalRotationDeltaMean,
                                candidateVsFinalGeometryDelta:
                                    viewModel.debugCandidateVsFinalGeometryDelta,
                                onSelectCameraProfile: { profileId in
                                    viewModel.setCameraProfile(profileId: profileId)
                                }
                            ) {
                                print("[DEBUG_GEAR] emergency debug panel close tapped")
                                scannerDebugPanelVisible = false
                            }
                            .frame(width: 300)
                            .padding(12)
                        } else {
                        ScannerDebugPanelView(
                            snapshot: viewModel.scannerDebugSnapshot,
                            markerProfiles: viewModel.markerProfiles,
                            requiredCoverageRange: viewModel.scanRequiredAngularCoverageRange,
                            requiredCoverageStep: viewModel.scanAngularCoverageStepPercent,
                            minimumGoodFrameRange: viewModel.scanMinimumGoodFrameRange,
                            minimumGoodFrameStep: viewModel.scanMinimumGoodFrameStep,
                            targetGoodFrameRange: viewModel.scanTargetValidFrameRange,
                            targetGoodFrameStep: viewModel.scanTargetValidFrameStep,
                            minimumDualTagFrameRange: viewModel.scanMinimumDualTagFrameRange,
                            dualAngularCoverageRange: viewModel.scanRequiredDualAngularCoverageRange,
                            dualAngularCoverageStep: viewModel.scanAngularCoverageStepPercent,
                            lensPositionChangeThresholdRange: viewModel.cameraLensPositionChangeThresholdRange,
                            lensPositionChangeThresholdStep: viewModel.cameraLensPositionChangeThresholdStep,
                            focusSettleTimeRange: viewModel.cameraFocusSettleTimeRange,
                            focusSettleTimeStep: viewModel.cameraFocusSettleTimeStep,
                            sharpnessThresholdRange: viewModel.sharpnessThresholdRange,
                            sharpnessThresholdStep: viewModel.sharpnessThresholdStep,
                            cameraZoomFactorRange: viewModel.cameraZoomFactorRange,
                            cameraZoomFactorStep: viewModel.cameraZoomFactorStep,
                            manualLensPositionRange: viewModel.manualLensPositionRange,
                            manualLensPositionStep: viewModel.manualLensPositionStep,
                            guidedStaticRequiredStagesRange: viewModel.guidedStaticRequiredStagesRange,
                            guidedStaticFramesPerStageRange: viewModel.guidedStaticFramesPerStageRange,
                            guidedStaticFramesPerStageStep: viewModel.guidedStaticFramesPerStageStep,
                            markerProfile: markerProfileBinding,
                            requiredCoveragePercent: scanRequiredCoverageBinding,
                            minimumGoodFrames: scanMinimumGoodFrameBinding,
                            targetGoodFrames: scanTargetFrameBinding,
                            minimumDualTagFramesPerMarker: scanMinimumDualTagFrameBinding,
                            minimumDualAngularCoveragePercentPerMarker: scanRequiredDualAngularCoverageBinding,
                            precisionModeV2: precisionModeV2Binding,
                            preferDualTagForFinalExport: preferDualTagForFinalExportBinding,
                            showDistanceGuide: showDistanceGuideBinding,
                            staticPoseStabilityMode: staticPoseStabilityModeBinding,
                            lockFocusAndExposureForScan: lockFocusAndExposureForScanBinding,
                            cameraZoomFactor: cameraZoomFactorBinding,
                            manualFocusEnabled: manualFocusEnabledBinding,
                            manualLensPosition: manualLensPositionBinding,
                            autoFocusOnDetectedAruco: autoFocusOnDetectedArucoBinding,
                            lockAfterArucoFocus: lockAfterArucoFocusBinding,
                            arkitAssistedCaptureEnabled: arkitAssistedCaptureEnabledBinding,
                            guidedStaticCaptureEnabled: guidedStaticCaptureEnabledBinding,
                            guidedStaticRequiredStages: guidedStaticRequiredStagesBinding,
                            guidedStaticFramesPerStage: guidedStaticFramesPerStageBinding,
                            lensPositionChangeThreshold: cameraLensPositionChangeThresholdBinding,
                            focusSettleTimeSeconds: cameraFocusSettleTimeBinding,
                            minimumAllowedSharpness: minimumAllowedSharpnessBinding,
                            minimumPreferredSharpness: minimumPreferredSharpnessBinding,
                            onLockCameraNow: {
                                viewModel.lockCameraNow()
                            },
                            onCalibrateFocusNow: {
                                viewModel.calibrateFocusNow()
                            },
                            onUnlockContinuousCamera: {
                                viewModel.unlockContinuousCamera()
                            }
                        ) {
                            print("[DEBUG_GEAR] scanner debug panel close tapped")
                            scannerDebugPanelVisible = false
                        }
                        .frame(width: 340)
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
            if newScenePhase == .active {
                viewModel.handleAppBecameActive()
            } else {
                viewModel.handleAppBecameInactive()
            }
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

            Button("DBG") {
                print("[DEBUG_GEAR] tapped")
                scannerDebugPanelVisible.toggle()
                print("[DEBUG_GEAR] scanner debug state toggled: \(scannerDebugPanelVisible)")
            }
            .buttonStyle(.plain)
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 46, height: 46)
            .background(Color.black.opacity(0.72))
            .clipShape(Circle())
            .accessibilityLabel("Abrir debug seguro")
        }
    }

    private var scannerBottomBar: some View {
        ScannerGlassPanel(cornerRadius: 20) {
            HStack(spacing: 18) {
                scannerBottomMetric(title: "Cobertura total", value: formattedScanGlobalCoverage)

                ScannerDivider()

                scannerBottomMetric(title: "Refinamento", value: formattedRefinementProgress)

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

    private var scannerFeedbackPanel: some View {
        ScannerGlassPanel(cornerRadius: 16) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(viewModel.scanUserFeedbackMessage)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)

                    Spacer(minLength: 10)

                    Text("Captura \(formattedUserProgress(viewModel.scanCaptureProgressPercent))")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.72))
                        .monospacedDigit()
                }

                Text(viewModel.scanUserFeedbackDetail)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.70))
                    .lineLimit(2)

                if let refinementProgress = viewModel.scanRefinementProgressPercent {
                    HStack(spacing: 8) {
                        ProgressView(value: min(max(refinementProgress, 0), 100), total: 100)
                            .progressViewStyle(.linear)
                            .tint(scannerAccentColor)

                        Text("Refinamento \(formattedUserProgress(refinementProgress))")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.72))
                            .monospacedDigit()
                    }
                }

                Text(viewModel.scanFriendlyBlockingReason)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: 520)
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

    private var formattedRefinementProgress: String {
        guard let progress = viewModel.scanRefinementProgressPercent,
              progress.isFinite
        else {
            return "N/A"
        }

        return formattedUserProgress(progress)
    }

    private func formattedUserProgress(_ progress: Double) -> String {
        guard progress.isFinite else {
            return "N/A"
        }

        return "\(Int(round(min(max(progress, 0), 100))))%"
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

    private var markerProfileBinding: Binding<MarkerProfile> {
        Binding(
            get: { viewModel.markerProfile },
            set: { viewModel.setMarkerProfile($0) }
        )
    }

    private var scanRequiredCoverageBinding: Binding<Double> {
        Binding(
            get: { viewModel.scanRequiredAngularCoveragePercent },
            set: { viewModel.setScanRequiredAngularCoveragePercent($0) }
        )
    }

    private var scanMinimumGoodFrameBinding: Binding<Int> {
        Binding(
            get: { viewModel.scanMinimumGoodFrameCount },
            set: { viewModel.setScanMinimumGoodFrameCount($0) }
        )
    }

    private var scanTargetFrameBinding: Binding<Int> {
        Binding(
            get: { viewModel.scanTargetValidFrameCount },
            set: { viewModel.setScanTargetValidFrameCount($0) }
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

    private var precisionModeV2Binding: Binding<Bool> {
        Binding(
            get: { viewModel.precisionModeV2 },
            set: { viewModel.setPrecisionModeV2($0) }
        )
    }

    private var preferDualTagForFinalExportBinding: Binding<Bool> {
        Binding(
            get: { viewModel.preferDualTagForFinalExport },
            set: { viewModel.setPreferDualTagForFinalExport($0) }
        )
    }

    private var showDistanceGuideBinding: Binding<Bool> {
        Binding(
            get: { viewModel.showDistanceGuide },
            set: { viewModel.setShowDistanceGuide($0) }
        )
    }

    private var staticPoseStabilityModeBinding: Binding<Bool> {
        Binding(
            get: { viewModel.staticPoseStabilityMode },
            set: { viewModel.setStaticPoseStabilityMode($0) }
        )
    }

    private var lockFocusAndExposureForScanBinding: Binding<Bool> {
        Binding(
            get: { viewModel.lockFocusAndExposureForScan },
            set: { viewModel.setLockFocusAndExposureForScan($0) }
        )
    }

    private var cameraZoomFactorBinding: Binding<Double> {
        Binding(
            get: { viewModel.cameraZoomFactor },
            set: { viewModel.setCameraZoomFactor($0) }
        )
    }

    private var manualFocusEnabledBinding: Binding<Bool> {
        Binding(
            get: { viewModel.manualFocusEnabled },
            set: { viewModel.setManualFocusEnabled($0) }
        )
    }

    private var manualLensPositionBinding: Binding<Double> {
        Binding(
            get: { viewModel.manualLensPosition },
            set: { viewModel.setManualLensPosition($0) }
        )
    }

    private var autoFocusOnDetectedArucoBinding: Binding<Bool> {
        Binding(
            get: { viewModel.autoFocusOnDetectedAruco },
            set: { viewModel.setAutoFocusOnDetectedAruco($0) }
        )
    }

    private var lockAfterArucoFocusBinding: Binding<Bool> {
        Binding(
            get: { viewModel.lockAfterArucoFocus },
            set: { viewModel.setLockAfterArucoFocus($0) }
        )
    }

    private var arkitAssistedCaptureEnabledBinding: Binding<Bool> {
        Binding(
            get: { viewModel.arkitAssistedCaptureEnabled },
            set: { viewModel.setARKitAssistedCaptureEnabled($0) }
        )
    }

    private var guidedStaticCaptureEnabledBinding: Binding<Bool> {
        Binding(
            get: { viewModel.guidedStaticCaptureEnabled },
            set: { viewModel.setGuidedStaticCaptureEnabled($0) }
        )
    }

    private var guidedStaticRequiredStagesBinding: Binding<Int> {
        Binding(
            get: { viewModel.guidedStaticRequiredStages },
            set: { viewModel.setGuidedStaticRequiredStages($0) }
        )
    }

    private var guidedStaticFramesPerStageBinding: Binding<Int> {
        Binding(
            get: { viewModel.guidedStaticFramesPerStage },
            set: { viewModel.setGuidedStaticFramesPerStage($0) }
        )
    }

    private var cameraLensPositionChangeThresholdBinding: Binding<Double> {
        Binding(
            get: { viewModel.cameraLensPositionChangeThreshold },
            set: { viewModel.setCameraLensPositionChangeThreshold($0) }
        )
    }

    private var cameraFocusSettleTimeBinding: Binding<Double> {
        Binding(
            get: { viewModel.cameraFocusSettleTimeSeconds },
            set: { viewModel.setCameraFocusSettleTimeSeconds($0) }
        )
    }

    private var minimumAllowedSharpnessBinding: Binding<Double> {
        Binding(
            get: { viewModel.minimumAllowedSharpness },
            set: { viewModel.setMinimumAllowedSharpness($0) }
        )
    }

    private var minimumPreferredSharpnessBinding: Binding<Double> {
        Binding(
            get: { viewModel.minimumPreferredSharpness },
            set: { viewModel.setMinimumPreferredSharpness($0) }
        )
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

private struct ScannerDebugEmergencyPanelView: View {
    let scannerState: String
    let feedbackState: String
    let feedbackMessage: String
    let captureProgressPercent: Double?
    let refinementProgressPercent: Double?
    let friendlyBlockingReason: String
    let marker0ProgressPercent: Double?
    let marker1ProgressPercent: Double?
    let marker2ProgressPercent: Double?
    let marker3ProgressPercent: Double?
    let allExpectedMarkersAt100Percent: Bool
    let normalFinalizationState: String?
    let normalFinalizationElapsedSeconds: Double?
    let normalFinalizationMaxSeconds: Double?
    let normalFinalizationStableSeconds: Double?
    let normalFinalizationMaturityGatePassed: Bool?
    let normalFinalizationMinObservationsReached: Bool?
    let normalFinalizationAverageObservationsReached: Bool?
    let normalFinalizationNormalGatePassed: Bool?
    let normalFinalizationReprojectionGatePassed: Bool?
    let normalFinalizationWorstNormalStd: Double?
    let normalFinalizationAutoExportReason: String?
    let normalFinalizationBlockedReason: String?
    let finalObservationsM0: Int?
    let finalObservationsM1: Int?
    let finalObservationsM2: Int?
    let finalObservationsM3: Int?
    let finalObservationsAverage: Double?
    let bestCandidateScore: Double?
    let bestCandidateGeometryAdjustedScore: Double?
    let bestCandidateGeometryPenalty: Double?
    let bestCandidateAgeSeconds: Double?
    let bestCandidateWorstNormalStd: Double?
    let bestCandidateWorstReprojection: Double?
    let bestCandidateObservationsM0: Int?
    let bestCandidateObservationsM1: Int?
    let bestCandidateObservationsM2: Int?
    let bestCandidateObservationsM3: Int?
    let bestCandidateSaved: Bool
    let bestCandidateUpdates: Int
    let bestCandidateMarkerIds: String
    let bestCandidateHasExportablePoses: Bool
    let useBestCandidateForExport: Bool
    let usedBestCandidate: Bool
    let cameraProfileId: String
    let cameraProfileName: String
    let deviceModelIdentifier: String
    let deviceMarketingName: String
    let selectedCameraLocalizedName: String?
    let selectedCameraDeviceType: String?
    let requestedZoomFactor: Double?
    let appliedZoomFactor: Double?
    let currentVideoZoomFactor: Double?
    let cameraFocusMode: String?
    let cameraExposureMode: String?
    let cameraIsAdjustingFocus: Bool?
    let cameraIsAdjustingExposure: Bool?
    let cameraIntrinsicsAvailable: Bool
    let cameraIntrinsicFx: Double?
    let cameraIntrinsicFy: Double?
    let cameraIntrinsicCx: Double?
    let cameraIntrinsicCy: Double?
    let activeVideoDimensions: String?
    let activeFormatDescription: String?
    let cameraProfileEvaluationScore: Double?
    let cameraProfileEvaluationWarnings: String?
    let relativeMarkerGeometryScore: Double?
    let relativeMarkerDistanceStdMean: Double?
    let relativeMarkerDistanceStdMax: Double?
    let relativeMarkerDistanceM01: Double?
    let relativeMarkerDistanceM02: Double?
    let relativeMarkerDistanceM03: Double?
    let relativeMarkerDistanceM12: Double?
    let relativeMarkerDistanceM13: Double?
    let relativeMarkerDistanceM23: Double?
    let candidateVsFinalTranslationDeltaMean: Double?
    let candidateVsFinalRotationDeltaMean: Double?
    let candidateVsFinalGeometryDelta: Double?
    let onSelectCameraProfile: (String) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Debug mode: emergency")
                .font(.headline)

            Text("App alive: yes")
                .font(.subheadline.weight(.semibold))

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        debugRow(title: "Scanner state", value: safeText(scannerState))
                        debugRow(title: "Feedback state", value: safeText(feedbackState))
                        debugRow(title: "Message", value: safeText(feedbackMessage))
                        debugRow(title: "Capture", value: safePercent(captureProgressPercent))
                        debugRow(title: "Refinement", value: safePercent(refinementProgressPercent))
                        debugRow(title: "Reason", value: safeText(friendlyBlockingReason))
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Markers:")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white.opacity(0.82))

                        debugRow(title: "M0", value: safePercent(marker0ProgressPercent))
                        debugRow(title: "M1", value: safePercent(marker1ProgressPercent))
                        debugRow(title: "M2", value: safePercent(marker2ProgressPercent))
                        debugRow(title: "M3", value: safePercent(marker3ProgressPercent))
                        debugRow(
                            title: "All markers 100%",
                            value: allExpectedMarkersAt100Percent ? "yes" : "no"
                        )
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Finalization:")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white.opacity(0.82))

                        debugRow(title: "State", value: safeText(normalFinalizationState))
                        debugRow(title: "Elapsed", value: safeSeconds(normalFinalizationElapsedSeconds))
                        debugRow(title: "Max", value: safeSeconds(normalFinalizationMaxSeconds))
                        debugRow(title: "Stable", value: safeSeconds(normalFinalizationStableSeconds))
                        debugRow(
                            title: "Maturity gate",
                            value: safeBool(normalFinalizationMaturityGatePassed)
                        )
                        debugRow(
                            title: "Min obs",
                            value: safeBool(normalFinalizationMinObservationsReached)
                        )
                        debugRow(
                            title: "Avg obs",
                            value: safeBool(normalFinalizationAverageObservationsReached)
                        )
                        debugRow(
                            title: "Normal gate",
                            value: safeBool(normalFinalizationNormalGatePassed)
                        )
                        debugRow(
                            title: "Reprojection gate",
                            value: safeBool(normalFinalizationReprojectionGatePassed)
                        )
                        debugRow(
                            title: "Worst normal",
                            value: safeDegrees(normalFinalizationWorstNormalStd)
                        )
                        debugRow(
                            title: "Auto export",
                            value: safeText(normalFinalizationAutoExportReason)
                        )
                        debugRow(
                            title: "Blocked",
                            value: safeText(normalFinalizationBlockedReason)
                        )
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Observations:")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white.opacity(0.82))

                        debugRow(title: "M0", value: safeInt(finalObservationsM0))
                        debugRow(title: "M1", value: safeInt(finalObservationsM1))
                        debugRow(title: "M2", value: safeInt(finalObservationsM2))
                        debugRow(title: "M3", value: safeInt(finalObservationsM3))
                        debugRow(title: "Average", value: safeNumber(finalObservationsAverage))
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Best candidate:")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white.opacity(0.82))

                        debugRow(title: "Score", value: safeNumber(bestCandidateScore))
                        debugRow(
                            title: "Adjusted score",
                            value: safeNumber(bestCandidateGeometryAdjustedScore)
                        )
                        debugRow(
                            title: "Geometry penalty",
                            value: safeNumber(bestCandidateGeometryPenalty)
                        )
                        debugRow(title: "Age", value: safeSeconds(bestCandidateAgeSeconds))
                        debugRow(title: "Normal", value: safeDegrees(bestCandidateWorstNormalStd))
                        debugRow(title: "Reprojection", value: safeNumber(bestCandidateWorstReprojection))
                        debugRow(title: "Obs M0", value: safeInt(bestCandidateObservationsM0))
                        debugRow(title: "Obs M1", value: safeInt(bestCandidateObservationsM1))
                        debugRow(title: "Obs M2", value: safeInt(bestCandidateObservationsM2))
                        debugRow(title: "Obs M3", value: safeInt(bestCandidateObservationsM3))
                        debugRow(title: "Saved", value: bestCandidateSaved ? "yes" : "no")
                        debugRow(title: "Updates", value: safeInt(bestCandidateUpdates))
                        debugRow(title: "Marker ids", value: safeText(bestCandidateMarkerIds))
                        debugRow(
                            title: "Has export poses",
                            value: bestCandidateHasExportablePoses ? "yes" : "no"
                        )
                        debugRow(
                            title: "Use for export",
                            value: useBestCandidateForExport ? "yes" : "no"
                        )
                        debugRow(title: "Used", value: usedBestCandidate ? "yes" : "no")
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Camera profile:")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white.opacity(0.82))

                        debugRow(title: "Profile", value: safeText(cameraProfileName))
                        debugRow(title: "Profile id", value: safeText(cameraProfileId))
                        debugRow(title: "Device id", value: safeText(deviceModelIdentifier))
                        debugRow(title: "Device name", value: safeText(deviceMarketingName))
                        debugRow(title: "Camera", value: safeText(selectedCameraLocalizedName))
                        debugRow(title: "Device type", value: safeText(selectedCameraDeviceType))
                        debugRow(title: "Requested zoom", value: safeZoom(requestedZoomFactor))
                        debugRow(title: "Applied zoom", value: safeZoom(appliedZoomFactor))
                        debugRow(title: "Current zoom", value: safeZoom(currentVideoZoomFactor))
                        debugRow(title: "Focus mode", value: safeText(cameraFocusMode))
                        debugRow(title: "Exposure mode", value: safeText(cameraExposureMode))
                        debugRow(title: "Adjusting focus", value: safeBool(cameraIsAdjustingFocus))
                        debugRow(title: "Adjusting exposure", value: safeBool(cameraIsAdjustingExposure))
                        debugRow(title: "Intrinsics", value: cameraIntrinsicsAvailable ? "yes" : "no")
                        debugRow(title: "fx", value: safeNumber(cameraIntrinsicFx))
                        debugRow(title: "fy", value: safeNumber(cameraIntrinsicFy))
                        debugRow(title: "cx", value: safeNumber(cameraIntrinsicCx))
                        debugRow(title: "cy", value: safeNumber(cameraIntrinsicCy))
                        debugRow(title: "Video dimensions", value: safeText(activeVideoDimensions))
                        debugRow(title: "Format", value: safeText(activeFormatDescription))
                        debugRow(title: "Eval score", value: safeNumber(cameraProfileEvaluationScore))
                        debugRow(title: "Warnings", value: safeText(cameraProfileEvaluationWarnings))

                        VStack(alignment: .leading, spacing: 5) {
                            profileButton(title: "Default", id: CameraProfile.Identifier.defaultProfile.rawValue)
                            profileButton(title: "Wide 1.0x", id: CameraProfile.Identifier.wide1x.rawValue)
                            profileButton(title: "Wide 1.5x", id: CameraProfile.Identifier.wide15x.rawValue)
                            profileButton(title: "Wide 2.0x", id: CameraProfile.Identifier.wide2x.rawValue)
                            profileButton(
                                title: "Wide 1.5x Conservative",
                                id: CameraProfile.Identifier.wide15xConservativeFocus.rawValue
                            )
                            profileButton(
                                title: "Wide 2.0x Conservative",
                                id: CameraProfile.Identifier.wide2xConservativeFocus.rawValue
                            )
                        }
                        .padding(.top, 4)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Geometry:")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white.opacity(0.82))

                        debugRow(title: "Score", value: safeNumber(relativeMarkerGeometryScore))
                        debugRow(
                            title: "Distance std mean",
                            value: safeMillimeters(relativeMarkerDistanceStdMean)
                        )
                        debugRow(
                            title: "Distance std max",
                            value: safeMillimeters(relativeMarkerDistanceStdMax)
                        )
                        debugRow(title: "Dist M01", value: safeMillimeters(relativeMarkerDistanceM01))
                        debugRow(title: "Dist M02", value: safeMillimeters(relativeMarkerDistanceM02))
                        debugRow(title: "Dist M03", value: safeMillimeters(relativeMarkerDistanceM03))
                        debugRow(title: "Dist M12", value: safeMillimeters(relativeMarkerDistanceM12))
                        debugRow(title: "Dist M13", value: safeMillimeters(relativeMarkerDistanceM13))
                        debugRow(title: "Dist M23", value: safeMillimeters(relativeMarkerDistanceM23))
                        debugRow(
                            title: "Candidate vs final T",
                            value: safeMillimeters(candidateVsFinalTranslationDeltaMean)
                        )
                        debugRow(
                            title: "Candidate vs final R",
                            value: safeDegrees(candidateVsFinalRotationDeltaMean)
                        )
                        debugRow(
                            title: "Candidate vs final G",
                            value: safeMillimeters(candidateVsFinalGeometryDelta)
                        )
                    }
                }
            }
            .frame(maxHeight: 520)

            Button("Fechar", action: onClose)
                .buttonStyle(.borderedProminent)
        }
        .padding(20)
        .foregroundStyle(.white)
        .background(Color.black.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func debugRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(title):")
                .foregroundStyle(.white.opacity(0.58))

            Spacer(minLength: 8)

            Text(value)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .monospacedDigit()
        }
        .font(.caption2.weight(.semibold))
    }

    private func profileButton(title: String, id: String) -> some View {
        Button {
            onSelectCameraProfile(id)
        } label: {
            HStack {
                Text(title)
                    .lineLimit(1)

                Spacer(minLength: 8)

                if cameraProfileId == id {
                    Text("selected")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.green.opacity(0.9))
                }
            }
        }
        .buttonStyle(.bordered)
        .tint(cameraProfileId == id ? .green : .blue)
        .font(.caption2.weight(.semibold))
    }

    private func safeText(_ value: String?) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            return "N/A"
        }

        return trimmed
    }

    private func safeBool(_ value: Bool?) -> String {
        guard let value else {
            return "N/A"
        }

        return value ? "yes" : "no"
    }

    private func safeNumber(_ value: Double?, digits: Int = 2) -> String {
        guard let value, value.isFinite else {
            return "N/A"
        }

        let clampedDigits = min(max(digits, 0), 4)
        return String(format: "%.\(clampedDigits)f", value)
    }

    private func safeZoom(_ value: Double?) -> String {
        guard let value, value.isFinite else {
            return "N/A"
        }

        return String(format: "%.2fx", value)
    }

    private func safeInt(_ value: Int?) -> String {
        guard let value else {
            return "N/A"
        }

        return "\(value)"
    }

    private func safeSeconds(_ value: Double?) -> String {
        let text = safeNumber(value)
        guard text != "N/A" else {
            return text
        }

        return "\(text)s"
    }

    private func safeDegrees(_ value: Double?) -> String {
        let text = safeNumber(value)
        guard text != "N/A" else {
            return text
        }

        return "\(text) deg"
    }

    private func safeMillimeters(_ value: Double?) -> String {
        let text = safeNumber(value)
        guard text != "N/A" else {
            return text
        }

        return "\(text) mm"
    }

    private func safePercent(_ value: Double?) -> String {
        guard let value, value.isFinite else {
            return "N/A"
        }

        let normalized = value > 1.0 ? value : value * 100.0
        return "\(Int(round(min(max(normalized, 0), 100))))%"
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
