import SwiftUI
import UIKit

struct ScannerDebugPanelView: View {
    let snapshot: ScannerDebugSnapshot
    let markerProfiles: [MarkerProfile]
    let requiredCoverageRange: ClosedRange<Double>
    let requiredCoverageStep: Double
    let minimumGoodFrameRange: ClosedRange<Int>
    let minimumGoodFrameStep: Int
    let targetGoodFrameRange: ClosedRange<Int>
    let targetGoodFrameStep: Int
    let minimumDualTagFrameRange: ClosedRange<Int>
    let dualAngularCoverageRange: ClosedRange<Double>
    let dualAngularCoverageStep: Double
    let lensPositionChangeThresholdRange: ClosedRange<Double>
    let lensPositionChangeThresholdStep: Double
    let focusSettleTimeRange: ClosedRange<Double>
    let focusSettleTimeStep: Double
    let sharpnessThresholdRange: ClosedRange<Double>
    let sharpnessThresholdStep: Double
    let cameraZoomFactorRange: ClosedRange<Double>
    let cameraZoomFactorStep: Double
    let manualLensPositionRange: ClosedRange<Double>
    let manualLensPositionStep: Double
    let guidedStaticRequiredStagesRange: ClosedRange<Int>
    let guidedStaticFramesPerStageRange: ClosedRange<Int>
    let guidedStaticFramesPerStageStep: Int
    @Binding var markerProfile: MarkerProfile
    @Binding var requiredCoveragePercent: Double
    @Binding var minimumGoodFrames: Int
    @Binding var targetGoodFrames: Int
    @Binding var minimumDualTagFramesPerMarker: Int
    @Binding var minimumDualAngularCoveragePercentPerMarker: Double
    @Binding var precisionModeV2: Bool
    @Binding var preferDualTagForFinalExport: Bool
    @Binding var showDistanceGuide: Bool
    @Binding var staticPoseStabilityMode: Bool
    @Binding var lockFocusAndExposureForScan: Bool
    @Binding var cameraZoomFactor: Double
    @Binding var manualFocusEnabled: Bool
    @Binding var manualLensPosition: Double
    @Binding var autoFocusOnDetectedAruco: Bool
    @Binding var lockAfterArucoFocus: Bool
    @Binding var arkitAssistedCaptureEnabled: Bool
    @Binding var guidedStaticCaptureEnabled: Bool
    @Binding var guidedStaticRequiredStages: Int
    @Binding var guidedStaticFramesPerStage: Int
    @Binding var lensPositionChangeThreshold: Double
    @Binding var focusSettleTimeSeconds: Double
    @Binding var minimumAllowedSharpness: Double
    @Binding var minimumPreferredSharpness: Double
    let onLockCameraNow: () -> Void
    let onCalibrateFocusNow: () -> Void
    let onUnlockContinuousCamera: () -> Void
    let onClose: () -> Void

    private let enableMotionDebugSection = false
    private let enableNormalDebugSection = false
    private let enableStaticStabilityDebugSection = false
    private let enablePlanarDebugSection = false
    private let enableQualityDebugSection = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            Divider()
                .overlay(Color.white.opacity(0.18))

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 12) {
                    debugSection(title: "Estado") {
                        debugRow(title: "Estado", value: snapshot.state.scanState)
                        debugRow(title: "Perfil marker", value: snapshot.state.markerProfile)
                        debugRow(title: "Readiness", value: snapshot.state.readinessMessage)
                        debugRow(title: "Markers atuais", value: snapshot.state.currentMarkerCount)
                        debugRow(title: "IDs detectados", value: snapshot.state.detectedMarkerIds)
                        debugRow(title: "Poses exportaveis", value: snapshot.state.exportablePoseCount)
                    }

                    debugSection(title: "Export STL") {
                        debugRow(title: "Gerando STL", value: snapshot.export.isGeneratingSTL)
                        debugRow(title: "STL URL existe", value: snapshot.export.stlURLExists)
                        debugRow(title: "STL existe", value: snapshot.export.stlFileExists)
                        debugRow(title: "Erro STL", value: snapshot.export.stlError)
                        debugRow(title: "tagPoses atuais", value: snapshot.export.currentExportableTagPoseCount)
                        debugRow(title: "Ultimo export poses", value: snapshot.export.lastSTLExportPoseCount)
                    }

                    debugSection(title: "Export gate") {
                        debugRow(title: "Perfil gate", value: snapshot.exportGate.profile)
                        debugRow(title: "Scan confidence", value: snapshot.exportGate.scanConfidence)
                        debugRow(title: "Markers visuais", value: snapshot.exportGate.visualMarkerCount)
                        debugRow(title: "Markers com pose", value: snapshot.exportGate.currentPoseMarkerCount)
                        debugRow(title: "Markers com obs", value: snapshot.exportGate.observedMarkerCount)
                        debugRow(title: "Markers exportaveis", value: snapshot.exportGate.markerCountSummary)
                        debugRow(title: "Expected markers", value: snapshot.exportGate.expectedMarkerCount)
                        debugRow(title: "Missing markers", value: snapshot.exportGate.missingMarkerIds)
                        debugRow(title: "Invalid markers", value: snapshot.exportGate.invalidMarkerIds)
                        debugRow(title: "Ultimo bloqueio", value: snapshot.exportGate.lastBlockedReason)

                        if snapshot.markerExportGateRows.isEmpty {
                            debugRow(title: "Markers", value: "Sem validacao ainda")
                        } else {
                            ForEach(snapshot.markerExportGateRows) { marker in
                                debugRow(
                                    title: "M\(marker.markerId)",
                                    value: "\(marker.status) | \(marker.reason) | visual \(marker.visuallyRecent), pose \(marker.hasCurrentPose), obs \(marker.accumulatedObservations), usadas \(marker.finalObservationsUsed)"
                                )
                            }
                        }
                    }

                    debugSection(title: "Readiness") {
                        debugRow(title: "coverageReady", value: snapshot.readiness.coverageReady)
                        debugRow(title: "goodFramesReady", value: snapshot.readiness.goodFramesReady)
                        debugRow(title: "reprojectionReady", value: snapshot.readiness.reprojectionReady)
                        debugRow(title: "distanceReady", value: snapshot.readiness.distanceReady)
                        debugRow(title: "jitterReady", value: snapshot.readiness.jitterReady)
                        debugRow(title: "stableReady", value: snapshot.readiness.stableReady)
                        debugRow(title: "currentFrameGood", value: snapshot.readiness.currentFrameGood)
                        debugRow(title: "dualTagReady", value: snapshot.readiness.dualTagReady)
                        debugRow(title: "dualAngularReady", value: snapshot.readiness.dualAngularReady)
                    }

                    debugSection(title: "Guided Static Capture") {
                        debugRow(title: "Ligado", value: snapshot.guidedStatic.enabled)
                        debugRow(title: "Etapa atual", value: snapshot.guidedStatic.currentStage)
                        debugRow(title: "Progresso etapa", value: snapshot.guidedStatic.stageProgress)
                        debugRow(title: "Estado etapa", value: snapshot.guidedStatic.stageState)
                        debugRow(title: "Etapas concluidas", value: snapshot.guidedStatic.completedStages)
                        debugRow(title: "Etapas exigidas", value: snapshot.guidedStatic.requiredStages)
                        debugRow(title: "Frames por etapa", value: snapshot.guidedStatic.framesPerStage)
                        debugRow(title: "Tempo estavel min", value: snapshot.guidedStatic.minStableTime)
                        debugRow(title: "Normal std max", value: snapshot.guidedStatic.maxNormalStdDegrees)
                        debugRow(title: "Exigir todos markers", value: snapshot.guidedStatic.requireAllMarkersPerStage)
                        debugRow(title: "Rejeitados foco", value: snapshot.guidedStatic.framesRejectedByFocus)
                        debugRow(title: "Rejeitados motion", value: snapshot.guidedStatic.framesRejectedByMotion)
                        debugRow(title: "Rejeitados normal", value: snapshot.guidedStatic.framesRejectedByNormal)
                        debugRow(title: "Rejeitados reproj", value: snapshot.guidedStatic.framesRejectedByReprojection)
                        debugRow(title: "Markers vistos etapa", value: snapshot.guidedStatic.markersSeenThisStage)
                        debugRow(title: "Markers aceitos etapa", value: snapshot.guidedStatic.markersAcceptedThisStage)

                        if snapshot.guidedStaticStageRows.isEmpty {
                            debugRow(title: "Etapas", value: "Sem etapas")
                        } else {
                            ForEach(snapshot.guidedStaticStageRows) { stage in
                                debugRow(
                                    title: stage.stageName,
                                    value: "\(stage.status) | aceitos \(stage.framesAccepted) | foco \(stage.framesRejectedByFocus), motion \(stage.framesRejectedByMotion), normal \(stage.framesRejectedByNormal), reproj \(stage.framesRejectedByReprojection) | markers \(stage.markersAccepted) | normal \(stage.normalStdDegreesMean)"
                                )
                            }
                        }
                    }

                    debugSection(title: "Performance") {
                        debugRow(title: "FPS estimado", value: snapshot.performance.estimatedFPS)
                        debugRow(title: "Frames processados", value: snapshot.performance.processedFrames)
                        debugRow(title: "Obs finais", value: snapshot.performance.finalObservationBuffer)
                        debugRow(title: "Obs por marker", value: snapshot.performance.finalObservationsByMarker)
                        debugRow(title: "Limite obs", value: snapshot.performance.finalObservationLimitPerMarker)
                        debugRow(title: "Static samples", value: snapshot.performance.staticPoseSamples)
                        debugRow(title: "Static pares", value: snapshot.performance.staticPosePairSamples)
                        debugRow(title: "Static planos", value: snapshot.performance.staticPosePlaneSamples)
                        debugRow(title: "Frame proc", value: snapshot.performance.lastFrameProcessingTimeMs)
                        debugRow(title: "Diag Hz", value: snapshot.performance.diagnosticsUpdateHz)
                    }

                    debugSection(title: "Diagnostics") {
                        debugRow(title: "Diagnostics enabled", value: snapshot.diagnostics.enabled)
                        debugRow(title: "Events count", value: snapshot.diagnostics.eventsCount)
                        debugRow(title: "Last event", value: snapshot.diagnostics.lastEvent)
                        debugRow(title: "Diagnostics file", value: snapshot.diagnostics.fileAvailable)
                        debugRow(title: "FPS mean", value: snapshot.diagnostics.fpsMean)
                        debugRow(title: "FPS min", value: snapshot.diagnostics.fpsMin)
                        debugRow(title: "Scan duration", value: snapshot.diagnostics.scanDuration)
                        debugRow(title: "Expected markers", value: snapshot.diagnostics.expectedMarkerIds)
                        debugRow(title: "Unexpected markers", value: snapshot.diagnostics.unexpectedMarkerIdsSeen)
                        debugRow(title: "Current block", value: snapshot.diagnostics.currentBlockingReason)
                        debugRow(title: "Last export block", value: snapshot.diagnostics.lastExportBlockReason)
                        debugRow(
                            title: "Block before export",
                            value: snapshot.diagnostics.lastBlockingReasonBeforeExport
                        )
                        debugRow(title: "Slowest marker", value: snapshot.diagnostics.slowestMarker)
                        debugRow(title: "Slowest expected", value: snapshot.diagnostics.slowestExpectedMarker)
                        debugRow(title: "All markers seen", value: snapshot.diagnostics.timeToAllMarkersSeen)
                        debugRow(title: "All markers exportable", value: snapshot.diagnostics.timeToAllMarkersExportable)
                        debugRow(title: "Extra after 100%", value: snapshot.diagnostics.extraTimeAfter100Percent)
                        debugRow(title: "Distance samples", value: snapshot.diagnostics.distanceSamples)
                        debugRow(title: "Distance valid", value: snapshot.diagnostics.distanceValidPercent)
                    }

                    debugSection(title: "Camera / Focus") {
                        debugRow(title: "Device", value: snapshot.camera.deviceName)
                        debugRow(title: "Type", value: snapshot.camera.deviceType)
                        debugRow(title: "Unique ID", value: snapshot.camera.uniqueID)
                        debugRow(title: "Resolution", value: snapshot.camera.resolution)
                        debugRow(title: "FPS", value: snapshot.camera.fps)
                        debugRow(title: "Format", value: snapshot.camera.activeFormatDescription)
                        debugRow(title: "Intrinsics", value: snapshot.camera.hasIntrinsics)
                        debugRow(title: "fx/fy", value: "\(snapshot.camera.fx) / \(snapshot.camera.fy)")
                        debugRow(title: "cx/cy", value: "\(snapshot.camera.cx) / \(snapshot.camera.cy)")
                        debugRow(title: "Lens position", value: snapshot.camera.lensPosition)
                        debugRow(title: "Focus stable", value: snapshot.camera.cameraFocusStable)
                        debugRow(title: "Focus settling", value: snapshot.camera.focusSettling)
                        debugRow(title: "Lens change age", value: snapshot.camera.lastLensPositionChangeAge)
                        debugRow(title: "Sharpness", value: snapshot.camera.sharpness)
                        debugRow(title: "Sharpness medio", value: snapshot.camera.averageSharpness)
                        debugRow(title: "Sharpness min", value: snapshot.camera.minimumAllowedSharpness)
                        debugRow(title: "Sharpness pref", value: snapshot.camera.minimumPreferredSharpness)
                        debugRow(title: "Adjusting focus", value: snapshot.camera.isAdjustingFocus)
                        debugRow(title: "Adjusting exposure", value: snapshot.camera.isAdjustingExposure)
                        debugRow(title: "Adjusting WB", value: snapshot.camera.isAdjustingWhiteBalance)
                        debugRow(title: "ISO", value: snapshot.camera.iso)
                        debugRow(title: "Exposure", value: snapshot.camera.exposureDuration)
                        debugRow(title: "Camera score", value: snapshot.camera.cameraStabilityScore)
                        debugRow(title: "Rotation score", value: snapshot.camera.rotationStabilityScore)
                        debugRow(title: "Zoom", value: snapshot.camera.videoZoomFactor)
                        debugRow(title: "Zoom min/max", value: "\(snapshot.camera.minimumAvailableVideoZoomFactor) / \(snapshot.camera.maximumAvailableVideoZoomFactor)")
                        debugRow(title: "Manual focus", value: snapshot.camera.manualFocusEnabled)
                        debugRow(title: "Manual lens target", value: snapshot.camera.manualLensPosition)
                        debugRow(title: "Manual focus supported", value: snapshot.camera.manualFocusSupported)
                        debugRow(title: "Auto lock", value: snapshot.camera.automaticLockEnabled)
                        debugRow(title: "Camera locked", value: snapshot.camera.cameraLocked)
                        debugRow(title: "Lock error", value: snapshot.camera.lockError)
                        debugRow(title: "Focus recovery", value: snapshot.camera.focusRecoveryState)
                        debugRow(title: "Last focus target", value: snapshot.camera.lastFocusTarget)
                        debugRow(title: "Last focus point", value: snapshot.camera.lastFocusPoint)
                        debugRow(title: "Cooldown restante", value: snapshot.camera.focusCooldownRemaining)
                        debugRow(title: "ArUco visible", value: snapshot.camera.arucoVisible)
                        debugRow(title: "ArUco lost age", value: snapshot.camera.arucoLostAge)
                        debugRow(title: "Recovering focus", value: snapshot.camera.recoveringFocus)
                        debugRow(title: "ArUco lost count", value: snapshot.camera.arucoLostCount)
                        debugRow(title: "Center recoveries", value: snapshot.camera.centerFocusRecoveryCount)
                        debugRow(title: "Last focus tag ID", value: snapshot.camera.lastArucoFocusTagId)
                        debugRow(title: "Last focus marker ID", value: snapshot.camera.lastArucoFocusMarkerId)
                        debugRow(title: "Last ArUco focus point", value: snapshot.camera.lastArucoFocusPoint)
                        debugRow(title: "Last focus age", value: snapshot.camera.lastArucoFocusRequestAge)
                        debugRow(title: "Focus cooldown", value: snapshot.camera.arucoFocusCooldown)
                        debugRow(title: "Focus error", value: snapshot.camera.lastArucoFocusError)
                        debugRow(title: "Focus adjusting frames", value: snapshot.camera.focusAdjustingFrames)
                        debugRow(title: "Frames rejeitados foco", value: snapshot.camera.focusRejectedFrames)
                        debugRow(title: "Frames rejeitados blur", value: snapshot.camera.blurRejectedFrames)
                        debugRow(title: "Exposure adjusting frames", value: snapshot.camera.exposureAdjustingFrames)
                        debugRow(title: "WB adjusting frames", value: snapshot.camera.whiteBalanceAdjustingFrames)
                        debugRow(title: "Unstable frames", value: snapshot.camera.unstableFrames)
                        debugRow(title: "Intrinsics changed", value: snapshot.camera.intrinsicsChanged)
                        debugRow(title: "Device changed", value: snapshot.camera.deviceChanged)
                        debugRow(title: "Format changed", value: snapshot.camera.formatChanged)
                        debugRow(title: "Resolution changed", value: snapshot.camera.resolutionChanged)
                        debugRow(title: "Warning", value: snapshot.camera.warning)
                        debugRow(title: "Ultimo frame ruim", value: snapshot.camera.lastBadFrameReason)
                        debugRow(title: "Estado distancia", value: snapshot.camera.distanceGuideState)
                        debugRow(title: "Distancia confiavel", value: snapshot.camera.distanceGuideSourceReliable)
                        debugRow(title: "Distancia", value: snapshot.camera.distanceMm)
                        debugRow(title: "distanceReady", value: snapshot.camera.distanceReady)
                        debugRow(title: "Screen awake", value: snapshot.camera.screenAwake)
                        debugRow(title: "Idle timer disabled", value: snapshot.camera.idleTimerDisabled)
                    }

                    debugSection(title: "ARKit Assist") {
                        debugRow(title: "Enabled", value: snapshot.arkit.enabled)
                        debugRow(title: "Available", value: snapshot.arkit.available)
                        debugRow(title: "Tracking", value: snapshot.arkit.trackingState)
                        debugRow(title: "Reliable", value: snapshot.arkit.reliable)
                        debugRow(title: "Has transform", value: snapshot.arkit.hasTransform)
                        debugRow(title: "Has intrinsics", value: snapshot.arkit.hasIntrinsics)
                        debugRow(title: "Motion/frame", value: snapshot.arkit.motionSinceLastFrame)
                        debugRow(title: "Intrinsics changed", value: snapshot.arkit.intrinsicsChanged)
                        debugRow(title: "Light estimate", value: snapshot.arkit.lightEstimate)
                        debugRow(title: "Score", value: snapshot.arkit.stabilityScore)
                        debugRow(title: "Rotation score", value: snapshot.arkit.rotationStabilityScore)
                        debugRow(title: "Recent", value: snapshot.arkit.recent)
                        debugRow(title: "Frames penalizados", value: snapshot.arkit.penalizedFrames)
                    }

                    debugSection(title: "Export Quality") {
                        debugRow(title: "Confianca", value: snapshot.exportQuality.confidence)
                        debugRow(title: "Markers alta", value: snapshot.exportQuality.highMarkers)
                        debugRow(title: "Markers media", value: snapshot.exportQuality.mediumMarkers)
                        debugRow(title: "Markers baixa", value: snapshot.exportQuality.lowMarkers)
                        debugRow(title: "Worst marker", value: snapshot.exportQuality.worstMarker)
                        debugRow(title: "Main issue", value: snapshot.exportQuality.mainIssue)
                        debugRow(title: "Observacoes finais", value: snapshot.exportQuality.finalObservationsUsed)
                        debugRow(title: "Rejeitadas foco", value: snapshot.exportQuality.rejectedByFocus)
                        debugRow(title: "Rejeitadas blur", value: snapshot.exportQuality.rejectedByBlur)
                        debugRow(title: "Rejeitadas camera", value: snapshot.exportQuality.rejectedByCamera)
                        debugRow(title: "Rejeitadas normal", value: snapshot.exportQuality.rejectedByNormal)
                        debugRow(title: "Rejeitadas fallback", value: snapshot.exportQuality.rejectedByFallback)
                        debugRow(title: "Rejeitadas edge", value: snapshot.exportQuality.rejectedByEdge)
                        debugRow(title: "Rejeitadas motion", value: snapshot.exportQuality.rejectedByMotion)
                        debugRow(title: "Penalizadas ARKit", value: snapshot.exportQuality.penalizedByARKit)
                    }

                    debugSection(title: "Config") {
                        debugRow(title: "Perfil marker", value: snapshot.configuration.markerProfile)
                        debugRow(title: "Barra distancia", value: snapshot.configuration.showDistanceGuide)
                        debugRow(title: "Travar camera", value: snapshot.configuration.lockFocusAndExposureForScan)
                        debugRow(title: "Zoom", value: snapshot.configuration.cameraZoomFactor)
                        debugRow(title: "Foco manual", value: snapshot.configuration.manualFocusEnabled)
                        debugRow(title: "Lens manual", value: snapshot.configuration.manualLensPosition)
                        debugRow(title: "Auto focus ArUco", value: snapshot.configuration.autoFocusOnDetectedAruco)
                        debugRow(title: "Lock apos ArUco", value: snapshot.configuration.lockAfterArucoFocus)
                        debugRow(title: "ARKit Assist", value: snapshot.configuration.arkitAssistedCaptureEnabled)
                        debugRow(title: "Guided Static", value: snapshot.guidedStatic.enabled)
                        debugRow(title: "Guided etapas", value: snapshot.guidedStatic.requiredStages)
                        debugRow(title: "Guided frames/etapa", value: snapshot.guidedStatic.framesPerStage)
                        debugRow(title: "Static stability", value: snapshot.configuration.staticPoseStabilityMode)
                        debugRow(title: "Frames min", value: snapshot.configuration.minimumGoodFrames)
                        debugRow(title: "Frames alvo", value: snapshot.configuration.targetValidFrames)
                        debugRow(title: "Cobertura angular", value: snapshot.configuration.requiredAngularCoverage)
                        debugRow(title: "Frames dual min", value: snapshot.configuration.minimumDualTagFrames)
                        debugRow(title: "Cobertura dual", value: snapshot.configuration.minimumDualAngularCoverage)
                        debugRow(title: "Precision v2", value: snapshot.configuration.precisionModeV2)
                        debugRow(title: "Dual export", value: snapshot.configuration.preferDualTagForFinalExport)
                        debugRow(title: "Sharpness min", value: snapshot.configuration.minimumAllowedSharpness)
                        debugRow(title: "Sharpness pref", value: snapshot.configuration.minimumPreferredSharpness)
                        debugRow(title: "Lens delta foco", value: snapshot.configuration.lensPositionChangeThreshold)
                        debugRow(title: "Focus settle", value: snapshot.configuration.focusSettleTimeSeconds)
                    }

                    debugSection(title: "Config scan") {
                        Picker("Perfil marker", selection: $markerProfile) {
                            ForEach(markerProfiles) { profile in
                                Text(profile.debugTitle)
                                    .tag(profile)
                            }
                        }
                        .pickerStyle(.segmented)

                        Toggle("Mostrar barra de distancia", isOn: $showDistanceGuide)
                        Toggle("Travar foco/exposicao", isOn: $lockFocusAndExposureForScan)
                        Toggle("Foco manual", isOn: $manualFocusEnabled)
                        Toggle("Auto focus no ArUco", isOn: $autoFocusOnDetectedAruco)
                        Toggle("Travar apos foco ArUco", isOn: $lockAfterArucoFocus)
                        Toggle("ARKit Assist experimental", isOn: $arkitAssistedCaptureEnabled)
                        Toggle("Guided Static Capture", isOn: $guidedStaticCaptureEnabled)

                        HStack(spacing: 8) {
                            Button("Lock camera now", action: onLockCameraNow)
                                .buttonStyle(.bordered)

                            Button("Lock focus now", action: onCalibrateFocusNow)
                                .buttonStyle(.bordered)
                        }
                        .font(.caption2.weight(.semibold))

                        HStack(spacing: 8) {
                            Button("Unlock continuous camera", action: onUnlockContinuousCamera)
                                .buttonStyle(.bordered)
                        }
                        .font(.caption2.weight(.semibold))

                        debugDoubleStepper(
                            title: "Zoom camera",
                            value: $cameraZoomFactor,
                            range: cameraZoomFactorRange,
                            step: cameraZoomFactorStep,
                            decimals: 1,
                            suffix: "x"
                        )

                        debugDoubleStepper(
                            title: "Lens manual",
                            value: $manualLensPosition,
                            range: manualLensPositionRange,
                            step: manualLensPositionStep,
                            decimals: 2,
                            suffix: ""
                        )
                        .disabled(!manualFocusEnabled)
                        .opacity(manualFocusEnabled ? 1.0 : 0.55)

                        debugDoubleStepper(
                            title: "Lens delta foco",
                            value: $lensPositionChangeThreshold,
                            range: lensPositionChangeThresholdRange,
                            step: lensPositionChangeThresholdStep,
                            decimals: 3,
                            suffix: ""
                        )

                        debugDoubleStepper(
                            title: "Focus settle",
                            value: $focusSettleTimeSeconds,
                            range: focusSettleTimeRange,
                            step: focusSettleTimeStep,
                            decimals: 1,
                            suffix: "s"
                        )

                        debugDoubleStepper(
                            title: "Sharpness minimo",
                            value: $minimumAllowedSharpness,
                            range: sharpnessThresholdRange,
                            step: sharpnessThresholdStep,
                            decimals: 0,
                            suffix: ""
                        )

                        debugDoubleStepper(
                            title: "Sharpness preferido",
                            value: $minimumPreferredSharpness,
                            range: sharpnessThresholdRange,
                            step: sharpnessThresholdStep,
                            decimals: 0,
                            suffix: ""
                        )

                        debugIntStepper(
                            title: "Etapas guiadas",
                            value: $guidedStaticRequiredStages,
                            range: guidedStaticRequiredStagesRange,
                            step: 1
                        )

                        debugIntStepper(
                            title: "Frames por etapa guiada",
                            value: $guidedStaticFramesPerStage,
                            range: guidedStaticFramesPerStageRange,
                            step: guidedStaticFramesPerStageStep
                        )

                        debugIntStepper(
                            title: "Minimum good frames",
                            value: $minimumGoodFrames,
                            range: minimumGoodFrameRange,
                            step: minimumGoodFrameStep
                        )

                        debugIntStepper(
                            title: "Target good frames",
                            value: $targetGoodFrames,
                            range: targetGoodFrameRange,
                            step: targetGoodFrameStep
                        )

                        debugPercentStepper(
                            title: "Cobertura angular minima",
                            value: $requiredCoveragePercent,
                            range: requiredCoverageRange,
                            step: requiredCoverageStep
                        )

                        if markerProfile == .dualArucoV2 {
                            debugIntStepper(
                                title: "Dual-tag frames por marker",
                                value: $minimumDualTagFramesPerMarker,
                                range: minimumDualTagFrameRange,
                                step: 1
                            )

                            debugPercentStepper(
                                title: "Cobertura angular dual",
                                value: $minimumDualAngularCoveragePercentPerMarker,
                                range: dualAngularCoverageRange,
                                step: dualAngularCoverageStep
                            )

                            Toggle("Precision mode v2", isOn: $precisionModeV2)
                            Toggle("Preferir dual-tag no export", isOn: $preferDualTagForFinalExport)
                            Toggle("Static Pose Stability Test", isOn: $staticPoseStabilityMode)
                        }
                    }

                    if snapshot.isDualArucoV2 {
                        debugSection(title: "Marker v2 basico") {
                            if snapshot.markerV2Rows.isEmpty {
                                debugRow(title: "Markers v2", value: "Sem dados v2 ainda")
                            } else {
                                ForEach(snapshot.markerV2Rows) { marker in
                                    debugRow(
                                        title: "M\(marker.markerId)",
                                        value: "Dual \(marker.dualFrames), Top \(marker.topFallbackFrames), Bottom \(marker.bottomFallbackFrames), \(marker.dualPercent), \(marker.dominantMode)"
                                    )
                                }
                            }
                        }
                    }

                    if enableMotionDebugSection ||
                        enableNormalDebugSection ||
                        enableStaticStabilityDebugSection ||
                        enablePlanarDebugSection ||
                        enableQualityDebugSection {
                        debugSection(title: "Avancado") {
                            debugRow(title: "Status", value: "Secoes avancadas desligadas")
                        }
                    }
                }
                .padding(.trailing, 4)
            }
        }
        .padding(12)
        .frame(maxHeight: max(CGFloat(220), UIScreen.main.bounds.height * 0.85))
        .foregroundStyle(.white)
        .background(Color.black.opacity(0.90))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onAppear {
            print("[DEBUG_GEAR] rendering rebuilt scanner debug panel")
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Scanner Debug")
                    .font(.headline)

                Text("SAFE DEBUG PANEL 88dae22")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.62))
            }

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3.weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Fechar debug")
        }
    }

    private func debugSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white.opacity(0.86))

            content()
        }
        .padding(.top, 3)
    }

    private func debugRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .foregroundStyle(.white.opacity(0.58))

            Spacer(minLength: 8)

            Text(value.isEmpty ? ScannerDebugSnapshot.missingValue : value)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .monospacedDigit()
        }
        .font(.caption2.weight(.semibold))
    }

    private func debugIntStepper(
        title: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        step: Int
    ) -> some View {
        Stepper(value: value, in: range, step: step) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .foregroundStyle(.white.opacity(0.58))

                Spacer(minLength: 8)

                Text("\(value.wrappedValue)")
                    .monospacedDigit()
            }
        }
        .font(.caption2.weight(.semibold))
    }

    private func debugPercentStepper(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double
    ) -> some View {
        Stepper(value: value, in: range, step: step) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .foregroundStyle(.white.opacity(0.58))

                Spacer(minLength: 8)

                Text(percentText(value.wrappedValue))
                    .monospacedDigit()
            }
        }
        .font(.caption2.weight(.semibold))
    }

    private func debugDoubleStepper(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        decimals: Int,
        suffix: String
    ) -> some View {
        Stepper(value: value, in: range, step: step) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .foregroundStyle(.white.opacity(0.58))

                Spacer(minLength: 8)

                Text(numberText(value.wrappedValue, decimals: decimals, suffix: suffix))
                    .monospacedDigit()
            }
        }
        .font(.caption2.weight(.semibold))
    }

    private func percentText(_ value: Double) -> String {
        guard value.isFinite else {
            return ScannerDebugSnapshot.missingValue
        }

        return "\(Int(round(value)))%"
    }

    private func numberText(_ value: Double, decimals: Int, suffix: String) -> String {
        guard value.isFinite else {
            return ScannerDebugSnapshot.missingValue
        }

        let safeDecimals = min(max(decimals, 0), 6)
        let text = String(format: "%.\(safeDecimals)f", value)
        return suffix.isEmpty ? text : "\(text) \(suffix)"
    }
}
