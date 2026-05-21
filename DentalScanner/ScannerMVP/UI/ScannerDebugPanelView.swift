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
    let onLockCameraNow: () -> Void
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

                    debugSection(title: "Camera") {
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
                        debugRow(title: "Adjusting focus", value: snapshot.camera.isAdjustingFocus)
                        debugRow(title: "Adjusting exposure", value: snapshot.camera.isAdjustingExposure)
                        debugRow(title: "Adjusting WB", value: snapshot.camera.isAdjustingWhiteBalance)
                        debugRow(title: "ISO", value: snapshot.camera.iso)
                        debugRow(title: "Exposure", value: snapshot.camera.exposureDuration)
                        debugRow(title: "Camera score", value: snapshot.camera.cameraStabilityScore)
                        debugRow(title: "Rotation score", value: snapshot.camera.rotationStabilityScore)
                        debugRow(title: "Auto lock", value: snapshot.camera.automaticLockEnabled)
                        debugRow(title: "Camera locked", value: snapshot.camera.cameraLocked)
                        debugRow(title: "Lock error", value: snapshot.camera.lockError)
                        debugRow(title: "Focus adjusting frames", value: snapshot.camera.focusAdjustingFrames)
                        debugRow(title: "Exposure adjusting frames", value: snapshot.camera.exposureAdjustingFrames)
                        debugRow(title: "WB adjusting frames", value: snapshot.camera.whiteBalanceAdjustingFrames)
                        debugRow(title: "Unstable frames", value: snapshot.camera.unstableFrames)
                        debugRow(title: "Intrinsics changed", value: snapshot.camera.intrinsicsChanged)
                        debugRow(title: "Device changed", value: snapshot.camera.deviceChanged)
                        debugRow(title: "Format changed", value: snapshot.camera.formatChanged)
                        debugRow(title: "Resolution changed", value: snapshot.camera.resolutionChanged)
                        debugRow(title: "Warning", value: snapshot.camera.warning)
                    }

                    debugSection(title: "Config") {
                        debugRow(title: "Perfil marker", value: snapshot.configuration.markerProfile)
                        debugRow(title: "Barra distancia", value: snapshot.configuration.showDistanceGuide)
                        debugRow(title: "Travar camera", value: snapshot.configuration.lockFocusAndExposureForScan)
                        debugRow(title: "Frames min", value: snapshot.configuration.minimumGoodFrames)
                        debugRow(title: "Frames alvo", value: snapshot.configuration.targetValidFrames)
                        debugRow(title: "Cobertura angular", value: snapshot.configuration.requiredAngularCoverage)
                        debugRow(title: "Frames dual min", value: snapshot.configuration.minimumDualTagFrames)
                        debugRow(title: "Cobertura dual", value: snapshot.configuration.minimumDualAngularCoverage)
                        debugRow(title: "Precision v2", value: snapshot.configuration.precisionModeV2)
                        debugRow(title: "Dual export", value: snapshot.configuration.preferDualTagForFinalExport)
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

                        HStack(spacing: 8) {
                            Button("Lock camera now", action: onLockCameraNow)
                                .buttonStyle(.bordered)

                            Button("Unlock continuous camera", action: onUnlockContinuousCamera)
                                .buttonStyle(.bordered)
                        }
                        .font(.caption2.weight(.semibold))

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

    private func percentText(_ value: Double) -> String {
        guard value.isFinite else {
            return ScannerDebugSnapshot.missingValue
        }

        return "\(Int(round(value)))%"
    }
}
