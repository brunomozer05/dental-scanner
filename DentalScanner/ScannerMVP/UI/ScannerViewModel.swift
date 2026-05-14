import AVFoundation
import Combine
import CoreGraphics
import CoreVideo
import Foundation
import simd

final class ScannerViewModel: ObservableObject {
    private enum OverlayStabilization {
        static let timeout: Double = 0.25
    }

    private enum DualMarkerDebugConfiguration {
        static let minimumMarkerAreaPixels: Double = 80.0
        static let recentDetectionWindowFrameCount: Int = 6
        static let recentDetectionTimeoutSeconds: Double = 0.25
    }

    private enum PoseConfiguration {
        static let defaultMarkerSizeMillimeters: Double = 6.9
        static let minimumMarkerSizeMillimeters: Double = 1.0
        static let maximumMarkerSizeMillimeters: Double = 50.0
        static let markerSizeStepMillimeters: Double = 0.1
        static let isMarkerSizeDebugEditingEnabled = true
    }

    private enum ImplantConfiguration {
        static let transform = MarkerToImplantTransform(
            translationMm: SIMD3<Double>(0.0, 0.0, 0.0),
            rotationVector: SIMD3<Double>(0.0, 0.0, 0.0)
        )
    }

    private enum PoseFilterConfiguration {
        static let smoothingAlpha: Double = 0.3
        static let outlierDistanceDeltaMm: Double = 80.0
        static let outlierResetFrameCount: Int = 3
        static let stableFrameCount: Int = 3
        static let stableReprojectionError: Double = 2.0
    }

    private struct ScanReadinessConfiguration {
        let minimumGoodFrames: Int
        let targetGoodFrames: Int

        let minimumCoveragePercentPerTag: Double

        let minimumDistanceMm: Double
        let idealMinimumDistanceMm: Double
        let idealMaximumDistanceMm: Double
        let maximumDistanceMm: Double

        let maximumAverageReprojectionError: Double
        let maximumPositionJitterMm: Double
        let maximumRotationJitterDegrees: Double

        let requiredStableDurationSeconds: Double

        static let `default` = ScanReadinessConfiguration(
            minimumGoodFrames: 90,
            targetGoodFrames: 120,
            minimumCoveragePercentPerTag: 0.50,
            minimumDistanceMm: 50,
            idealMinimumDistanceMm: 80,
            idealMaximumDistanceMm: 180,
            maximumDistanceMm: 250,
            maximumAverageReprojectionError: 2.0,
            maximumPositionJitterMm: 1.0,
            maximumRotationJitterDegrees: 5.0,
            requiredStableDurationSeconds: 0.3
        )
    }

    private enum ScanConfiguration {
        static let readiness = ScanReadinessConfiguration.default
        static let completedCoverageThreshold: Double = 0.995
        static let defaultTargetValidFrameCount: Int = readiness.targetGoodFrames
        static let minimumTargetValidFrameCount: Int = readiness.minimumGoodFrames
        static let maximumTargetValidFrameCount: Int = readiness.targetGoodFrames * 2
        static let poseStabilityWindowCount: Int = 12
        static let targetAverageReprojectionError: Double =
            readiness.maximumAverageReprojectionError * 0.60
        static let maximumAverageReprojectionError: Double = readiness.maximumAverageReprojectionError
        static let targetPoseJitterMm: Double = readiness.maximumPositionJitterMm * 0.50
        static let maximumPoseJitterMm: Double = readiness.maximumPositionJitterMm
        static let targetRotationJitterDegrees: Double = readiness.maximumRotationJitterDegrees * 0.50
        static let maximumRotationJitterDegrees: Double = readiness.maximumRotationJitterDegrees
        static let azimuthBinCount: Int = 8
        static let elevationBinCount: Int = 2
        static let defaultRequiredAngularCoveragePercent: Double =
            readiness.minimumCoveragePercentPerTag * 100.0
        static let minimumRequiredAngularCoveragePercent: Double = 30.0
        static let maximumRequiredAngularCoveragePercent: Double = 95.0
        static let angularCoverageStepPercent: Double = 5.0
        static let precisionErrorHistoryLimit: Int = 30
        static let defaultMinimumDualTagFramesPerMarker: Int = 10
        static let minimumDualTagFramesPerMarkerRange: ClosedRange<Int> = 0...30
    }

    enum CameraState: Equatable {
        case idle
        case preparing
        case ready
        case running
        case failed
    }

    enum ScanState: Equatable {
        case idle
        case scanning
        case stabilizing
        case ready

        var isCollectingFrames: Bool {
            self == .scanning || self == .stabilizing
        }
    }

    struct FrameResolution: Equatable {
        let width: Int
        let height: Int
    }

    struct ScanTagCoverage: Equatable {
        let markerId: Int
        let rawAngularCoveragePercent: Double
        let requiredAngularCoveragePercent: Double
        let normalizedCoverageProgress: Double
        let coveredBinCount: Int
        let requiredBinCount: Int
        let observedFrameCount: Int

        var progress: Double {
            normalizedCoverageProgress
        }
    }

    private struct OverlayMarkerSample {
        let marker: MarkerOverlayResult
        let timestamp: Double
    }

    private struct DualTagDetectionObservation {
        let frameIndex: Int
        let timestamp: Double
        let rawDetected: Bool
        let acceptedDetected: Bool
        let areaPixels: Double?
    }

    private struct DualTagRecentDetectionSummary {
        let rawDetectionCount: Int
        let acceptedDetectionCount: Int
        let recentlySeen: Bool
        let latestAreaPixels: Double?
    }

    private struct DualMarkerPoseObservation {
        let frameIndex: Int
        let timestamp: Double
    }

    @Published private(set) var cameraState: CameraState = .idle
    @Published private(set) var totalFramesReceived: Int = 0
    @Published private(set) var estimatedFPS: Double = 0
    @Published private(set) var lastFrameTimestamp: Double?
    @Published private(set) var frameResolution: FrameResolution?
    @Published private(set) var isIntrinsicMatrixAvailable: Bool = false
    @Published private(set) var isOpenCVAvailable: Bool = false
    @Published private(set) var detectedMarkerCount: Int = 0
    @Published private(set) var detectedMarkerIds: [Int] = []
    @Published private(set) var detectedMarkers: [ArUcoDetectionResult] = []
    @Published private(set) var overlayMarkers: [MarkerOverlayResult] = []
    @Published private(set) var arucoErrorMessage: String?
    @Published private(set) var hasFrameReachedArucoDetector: Bool = false
    @Published private(set) var arucoDetectionCallCount: Int = 0
    @Published private(set) var arucoFrameResolution: FrameResolution?
    @Published private(set) var arucoFramePixelFormat: String = "-"
    @Published private(set) var arucoBytesPerRow: Int?
    @Published private(set) var arucoDictionaryName: String = ArUcoDetector.dictionaryName
    @Published private(set) var arucoPreprocessingDescription: String = ArUcoDetector.preprocessingDescription
    @Published private(set) var arucoInputChannelCount: Int?
    @Published private(set) var arucoGrayscaleChannelCount: Int?
    @Published private(set) var arucoRejectedCandidateCount: Int?
    @Published private(set) var rawPoseResults: [PoseResult] = []
    @Published private(set) var fusedPoseResults: [PoseResult] = []
    @Published private(set) var rawPoseResult: PoseResult?
    @Published private(set) var stablePoseResult: PoseResult?
    @Published private(set) var poseStabilityStatus: String = "Sem pose"
    @Published private(set) var poseMarkerId: Int?
    @Published private(set) var poseDistanceMm: Double?
    @Published private(set) var poseReprojectionError: Double?
    @Published private(set) var poseErrorMessage: String?
    @Published private(set) var markerProfile: MarkerProfile = MarkerConfiguration.defaultProfile
    @Published private(set) var poseMarkerSizeMillimeters: Double = PoseConfiguration.defaultMarkerSizeMillimeters
    @Published private(set) var dualMarkerDebugStates: [DualArucoMarkerDebugState] = []
    @Published private(set) var showDistanceGuide: Bool = true
    @Published private(set) var implantPoseResults: [ImplantPose] = []
    @Published private(set) var implantPoseResult: ImplantPose?
    @Published private(set) var implantOffsetDescription: String = ScannerViewModel.formatImplantOffset(
        ImplantConfiguration.transform
    )
    @Published private(set) var selectedImplantMarkerIds: [Int] = []
    @Published private(set) var selectedTagDistanceMm: Double?
    @Published private(set) var selectedImplantDistanceMm: Double?
    @Published private(set) var precisionValidationExpectedDistanceMm: Double?
    @Published private(set) var precisionValidationCurrentErrorMm: Double?
    @Published private(set) var precisionValidationAverageErrorMm: Double?
    @Published private(set) var precisionValidationSampleCount: Int = 0
    @Published private(set) var scanState: ScanState = .idle
    @Published private(set) var previousScanState: ScanState = .idle
    @Published private(set) var scanProgress: Double = 0
    @Published private(set) var scanQualityScore: Double = 0
    @Published private(set) var scanValidFrameCount: Int = 0
    @Published private(set) var scanAverageDistanceMm: Double?
    @Published private(set) var scanAverageReprojectionError: Double?
    @Published private(set) var scanPoseJitterMm: Double?
    @Published private(set) var scanPositionJitterMm: Double?
    @Published private(set) var scanRotationJitterDegrees: Double?
    @Published private(set) var scanStableReadinessDurationSeconds: Double = 0
    @Published private(set) var scanQualityStatus: String = "Aguardando inicio"
    @Published private(set) var scanReadinessMessage: String = "Aguardando inicio"
    @Published private(set) var scanReadinessBlockerSummary: String = "Aguardando inicio"
    @Published private(set) var scanCoverageReady: Bool = false
    @Published private(set) var scanGoodFramesReady: Bool = false
    @Published private(set) var scanDistanceReady: Bool = false
    @Published private(set) var scanReprojectionReady: Bool = false
    @Published private(set) var scanJitterReady: Bool = false
    @Published private(set) var scanStableReady: Bool = false
    @Published private(set) var scanCurrentFrameGood: Bool = false
    @Published private(set) var scanTagCoverages: [Int: ScanTagCoverage] = [:]
    @Published private(set) var scanTargetValidFrameCount: Int = ScanConfiguration.defaultTargetValidFrameCount
    @Published private(set) var scanRequiredAngularCoveragePercent: Double =
        ScanConfiguration.defaultRequiredAngularCoveragePercent
    @Published private(set) var scanDualTagReady: Bool = false
    @Published private(set) var scanMinimumDualTagFrameCount: Int =
        ScanConfiguration.defaultMinimumDualTagFramesPerMarker
    @Published private(set) var stlExportURL: URL?
    @Published private(set) var stlExportedImplantCount: Int = 0
    @Published private(set) var stlExportErrorMessage: String?
    @Published private(set) var isGeneratingSTL: Bool = false
    @Published private(set) var canExportSTL: Bool = false
    @Published private(set) var hasSTLExportFile: Bool = false
    @Published private(set) var hasSTLExportURL: Bool = false
    @Published private(set) var currentExportableTagPoseCount: Int = 0
    @Published private(set) var readyTransitionCount: Int = 0
    @Published private(set) var didCallHandleScanBecameReady: Bool = false
    @Published private(set) var didCallSaveCurrentScanIfNeeded: Bool = false
    @Published private(set) var didStartSTLExportForCurrentScan: Bool = false
    @Published private(set) var lastSTLExportTagPoseCount: Int = 0
    @Published private(set) var lastSTLExportEventMessage: String = "Aguardando"
    @Published private(set) var lastSTLReferenceModelFileName: String = "-"
    @Published private(set) var lastSTLExportMarkerIds: [Int] = []
    @Published private(set) var lastSTLExportMarkerProfile: MarkerProfile = MarkerConfiguration.defaultProfile
    @Published private(set) var lastSTLExportBottomTagSizeMillimeters: Double?
    @Published private(set) var lastSTLExportBottomCenterYMillimeters: Double?
    @Published private(set) var isTorchAvailable: Bool = false
    @Published private(set) var isTorchEnabled: Bool = false
    @Published private(set) var errorMessage: String?

    private let cameraService: CameraFrameService
    private let arUcoDetector: ArUcoDetector
    private let arUcoConsistencyFilter: ArUcoConsistencyFilter
    private let poseEstimator: PoseEstimator
    private let multiFramePoseAccumulator: MultiFramePoseAccumulator
    private let finalPoseRefiner: FinalPoseRefiner
    private let poseSmoother = PoseSmoother()
    private let scanReadinessConfiguration = ScanReadinessConfiguration.default
    private let stlExporter: STLExporter
    private let scanStorageManager: ScanStorageManager
    private var shouldRunCamera = false
    private var totalFramesCounter: Int = 0
    private var recentFrameTimestamps: [Double] = []
    private var lastValidOverlayMarkers: [MarkerOverlayResult] = []
    private var lastValidOverlayTimestamp: Double?
    private var lastValidOverlayMarkersByMarkerId: [Int: OverlayMarkerSample] = [:]
    private var filteredPoseResult: PoseResult?
    private var acceptedPoseFrameCount = 0
    private var consecutivePoseOutlierCount = 0
    private var desiredTorchEnabled = false
    private var scanReprojectionErrors: [Double] = []
    private var scanPoseHistoryByMarkerId: [Int: [ScanPoseSample]] = [:]
    private var scanCoverageBinsByMarkerId: [Int: Set<Int>] = [:]
    private var scanFrameCountsByMarkerId: [Int: Int] = [:]
    private var scanDualTagFrameCountsByMarkerId: [Int: Int] = [:]
    private var scanTopFallbackFrameCountsByMarkerId: [Int: Int] = [:]
    private var scanBottomFallbackFrameCountsByMarkerId: [Int: Int] = [:]
    private var scanReadinessStableStartTimestamp: Double?
    private var scanCurrentFrameIsGood = false
    private var scanCurrentFrameReadinessBlocker: String?
    private var precisionValidationErrorHistory: [Double] = []
    private var finalPoseObservations: [FinalPoseObservation] = []
    private var didApplyFinalPoseRefinement = false
    private var stlExportGenerationID = UUID()
    private var dualRawDetectionCountsByTagId: [Int: Int] = [:]
    private var dualAcceptedDetectionCountsByTagId: [Int: Int] = [:]
    private var dualRecentDetectionHistoryByTagId: [Int: [DualTagDetectionObservation]] = [:]
    private var dualRecentDualTagPoseHistoryByMarkerId: [Int: [DualMarkerPoseObservation]] = [:]

    var captureSession: AVCaptureSession {
        cameraService.captureSession
    }

    var markerSizeDebugRange: ClosedRange<Double> {
        PoseConfiguration.minimumMarkerSizeMillimeters...PoseConfiguration.maximumMarkerSizeMillimeters
    }

    var markerSizeDebugStepMillimeters: Double {
        PoseConfiguration.markerSizeStepMillimeters
    }

    var isMarkerSizeDebugEditingEnabled: Bool {
        markerProfile == .singleArucoV1 &&
            PoseConfiguration.isMarkerSizeDebugEditingEnabled
    }

    var markerProfiles: [MarkerProfile] {
        MarkerProfile.allCases
    }

    var scanTargetValidFrameRange: ClosedRange<Int> {
        ScanConfiguration.minimumTargetValidFrameCount...ScanConfiguration.maximumTargetValidFrameCount
    }

    var scanRequiredAngularCoverageRange: ClosedRange<Double> {
        return ScanConfiguration.minimumRequiredAngularCoveragePercent...ScanConfiguration.maximumRequiredAngularCoveragePercent
    }

    var scanAngularCoverageStepPercent: Double {
        ScanConfiguration.angularCoverageStepPercent
    }

    var scanMinimumDualTagFrameRange: ClosedRange<Int> {
        ScanConfiguration.minimumDualTagFramesPerMarkerRange
    }

    var dualMarkerRecentDetectionWindowFrameCount: Int {
        DualMarkerDebugConfiguration.recentDetectionWindowFrameCount
    }

    var scanMinimumGoodFrameCount: Int {
        scanReadinessConfiguration.minimumGoodFrames
    }

    var scanTargetGoodFrameCount: Int {
        scanTargetValidFrameCount
    }

    var scanGlobalCoveragePercent: Double {
        minimumTagCoverageProgress() * 100.0
    }

    var scanCurrentAngularCoveragePercent: Double {
        minimumObservedAngularCoveragePercent()
    }

    var scanNormalizedCoverageProgressPercent: Double {
        scanGlobalCoveragePercent
    }

    var scanCoverageMarkerIds: [Int] {
        activeTagCoverages.map(\.markerId).sorted()
    }

    var scanRequiredStableDurationSeconds: Double {
        scanReadinessConfiguration.requiredStableDurationSeconds
    }

    init(
        cameraService: CameraFrameService = CameraFrameService(),
        arUcoDetector: ArUcoDetector = ArUcoDetector(),
        arUcoConsistencyFilter: ArUcoConsistencyFilter = ArUcoConsistencyFilter(),
        poseEstimator: PoseEstimator = PoseEstimator(),
        multiFramePoseAccumulator: MultiFramePoseAccumulator = MultiFramePoseAccumulator(),
        finalPoseRefiner: FinalPoseRefiner = FinalPoseRefiner(),
        stlExporter: STLExporter = STLExporter(),
        scanStorageManager: ScanStorageManager = ScanStorageManager()
    ) {
        self.cameraService = cameraService
        self.arUcoDetector = arUcoDetector
        self.arUcoConsistencyFilter = arUcoConsistencyFilter
        self.poseEstimator = poseEstimator
        self.multiFramePoseAccumulator = multiFramePoseAccumulator
        self.finalPoseRefiner = finalPoseRefiner
        self.stlExporter = stlExporter
        self.scanStorageManager = scanStorageManager
        self.isOpenCVAvailable = arUcoDetector.isOpenCVAvailable
        bindCameraCallbacks()
    }

    func prepareCamera() async {
        let currentState = await MainActor.run { cameraState }
        guard currentState != .preparing else {
            return
        }

        await MainActor.run {
            errorMessage = nil
            cameraState = .preparing
        }

        do {
            try await cameraService.prepare()
            let torchState = await cameraService.fetchTorchState()
            await MainActor.run {
                cameraState = .ready
                isTorchAvailable = torchState.isAvailable

                if torchState.isAvailable {
                    desiredTorchEnabled = desiredTorchEnabled || torchState.isEnabled
                    isTorchEnabled = desiredTorchEnabled ? true : torchState.isEnabled
                } else {
                    desiredTorchEnabled = false
                    isTorchEnabled = false
                }
            }
        } catch {
            await MainActor.run {
                handleCameraError(error)
            }
        }
    }

    func startCamera() async {
        let currentState = await MainActor.run {
            shouldRunCamera = true
            return cameraState
        }
        if currentState == .idle || currentState == .failed {
            await prepareCamera()
        }

        let startContext = await MainActor.run { (cameraState, shouldRunCamera) }
        let preparedState = startContext.0
        let shouldContinueRunning = startContext.1

        guard shouldContinueRunning, !Task.isCancelled else {
            return
        }

        guard preparedState == .ready || preparedState == .running else {
            return
        }

        cameraService.startRunning()
        await MainActor.run {
            cameraState = .running
        }
    }

    @MainActor
    func stopCamera() {
        shouldRunCamera = false
        cameraService.stopRunning()
        turnOffTorchForInactiveCamera()
        guard cameraState != .failed else { return }
        cameraState = .ready
    }

    @MainActor
    func pauseCameraForExternalPresentation() {
        stopCamera()
    }

    @MainActor
    func resumeCameraAfterExternalPresentation() {
        Task { [weak self] in
            guard let self else { return }

            await self.startCamera()
            await self.reapplyDesiredTorchIfNeeded()
        }
    }

    @MainActor
    func toggleTorch() {
        guard isTorchAvailable else { return }

        let targetState = !isTorchEnabled
        desiredTorchEnabled = targetState

        Task { [weak self] in
            guard let self else { return }

            do {
                let torchState = try await self.cameraService.setTorchEnabled(
                    targetState,
                    requiresRunningSession: true
                )
                await MainActor.run {
                    self.isTorchAvailable = torchState.isAvailable
                    self.isTorchEnabled = torchState.isEnabled

                    if !torchState.isAvailable {
                        self.desiredTorchEnabled = false
                    }

                    self.errorMessage = nil
                }
            } catch {
                if self.isSessionNotPreparedError(error) {
                    return
                }

                await MainActor.run {
                    self.errorMessage = self.makeErrorMessage(from: error)
                }
            }
        }
    }

    @MainActor
    func handleAppBecameActive() {
        guard shouldRunCamera else {
            return
        }

        Task { [weak self] in
            guard let self else { return }
            await self.startCamera()
            await self.reapplyDesiredTorchIfNeeded()
        }
    }

    @MainActor
    func toggleImplantMarkerSelection(_ markerId: Int) {
        if let selectedIndex = selectedImplantMarkerIds.firstIndex(of: markerId) {
            selectedImplantMarkerIds.remove(at: selectedIndex)
        } else {
            if selectedImplantMarkerIds.count >= 2 {
                selectedImplantMarkerIds.removeFirst()
            }
            selectedImplantMarkerIds.append(markerId)
        }

        selectedTagDistanceMm = selectedTagDistance(in: consolidatedPoseResults())
        selectedImplantDistanceMm = selectedImplantDistance(in: implantPoseResults)
        resetPrecisionValidationHistory()
        updatePrecisionValidationCurrentError()
    }

    @MainActor
    func setPrecisionValidationExpectedDistanceMillimeters(_ expectedDistanceMm: Double?) {
        guard let expectedDistanceMm else {
            precisionValidationExpectedDistanceMm = nil
            resetPrecisionValidationHistory()
            updatePrecisionValidationCurrentError()
            return
        }

        guard expectedDistanceMm.isFinite, expectedDistanceMm > 0 else {
            return
        }

        precisionValidationExpectedDistanceMm = expectedDistanceMm
        resetPrecisionValidationHistory()
        updatePrecisionValidationCurrentError()
    }

    @MainActor
    func setMarkerSizeMillimeters(_ markerSizeMillimeters: Double) {
        guard markerSizeMillimeters.isFinite else {
            return
        }

        poseMarkerSizeMillimeters = min(
            max(markerSizeMillimeters, PoseConfiguration.minimumMarkerSizeMillimeters),
            PoseConfiguration.maximumMarkerSizeMillimeters
        )
        resetScanSession()
    }

    @MainActor
    func setMarkerProfile(_ markerProfile: MarkerProfile) {
        guard self.markerProfile != markerProfile else {
            return
        }

        self.markerProfile = markerProfile
        dualMarkerDebugStates = []
        overlayMarkers = []
        lastValidOverlayMarkers = []
        lastValidOverlayMarkersByMarkerId = [:]
        lastValidOverlayTimestamp = nil
        resetPoseFilter()
        resetScanSession()
    }

    @MainActor
    func setShowDistanceGuide(_ showDistanceGuide: Bool) {
        self.showDistanceGuide = showDistanceGuide
    }

    @MainActor
    func startScan() {
        resetScanSession()
        setScanState(.scanning)
        scanQualityStatus = "Capturando"
        scanReadinessMessage = "Capturando"
    }

    @MainActor
    func setScanTargetValidFrameCount(_ targetValidFrameCount: Int) {
        scanTargetValidFrameCount = min(
            max(targetValidFrameCount, ScanConfiguration.minimumTargetValidFrameCount),
            ScanConfiguration.maximumTargetValidFrameCount
        )

        if scanState != .idle {
            updateScanProgressAndState(
                timestamp: lastFrameTimestamp ?? Date().timeIntervalSinceReferenceDate
            )
        }
    }

    @MainActor
    func setScanRequiredAngularCoveragePercent(_ requiredAngularCoveragePercent: Double) {
        guard requiredAngularCoveragePercent.isFinite else {
            return
        }

        scanRequiredAngularCoveragePercent = min(
            max(
                requiredAngularCoveragePercent,
                ScanConfiguration.minimumRequiredAngularCoveragePercent
            ),
            ScanConfiguration.maximumRequiredAngularCoveragePercent
        )
        rebuildScanTagCoverages()

        if scanState != .idle {
            updateScanProgressAndState(
                timestamp: lastFrameTimestamp ?? Date().timeIntervalSinceReferenceDate
            )
        }
    }

    @MainActor
    func setScanMinimumDualTagFrameCount(_ minimumDualTagFrameCount: Int) {
        scanMinimumDualTagFrameCount = min(
            max(
                minimumDualTagFrameCount,
                ScanConfiguration.minimumDualTagFramesPerMarkerRange.lowerBound
            ),
            ScanConfiguration.minimumDualTagFramesPerMarkerRange.upperBound
        )

        if scanState != .idle {
            updateScanProgressAndState(
                timestamp: lastFrameTimestamp ?? Date().timeIntervalSinceReferenceDate
            )
        }
    }

    func setPreviewOrientation(_ orientation: CameraPreviewOrientation) {
        cameraService.setVideoOrientation(orientation.captureVideoOrientation)
    }

    func handleScannerOrientationChanged() {
        Task { [weak self] in
            await self?.reapplyDesiredTorchIfNeeded()
        }
    }

    @MainActor
    @discardableResult
    func exportCurrentImplantsAsSTL() -> URL? {
        updateExportDiagnostics()
        guard scanState == .ready else {
            stlExportURL = nil
            stlExportedImplantCount = 0
            stlExportErrorMessage = "Escaneamento ainda nao esta pronto."
            scanReadinessBlockerSummary = "Bloqueio principal: scan nao pronto"
            updateExportDiagnostics()
            return nil
        }

        applyFinalPoseRefinementIfNeeded()
        return saveCurrentScanIfNeeded()
    }

    @MainActor
    @discardableResult
    private func handleScanBecameReady() -> URL? {
        guard !didCallHandleScanBecameReady else {
            updateExportDiagnostics()
            return stlExportURL
        }

        didCallHandleScanBecameReady = true
        lastSTLExportEventMessage = "handleScanBecameReady called"
        applyFinalPoseRefinementIfNeeded()
        if scanState != .ready {
            setScanState(.ready)
        }
        scanProgress = 100

        let exportURL = saveCurrentScanIfNeeded()
        if isGeneratingSTL {
            scanReadinessMessage = "Gerando modelo..."
            scanQualityStatus = "Gerando modelo..."
            scanReadinessBlockerSummary = "Pronto: gerando STL"
        } else if stlExportErrorMessage != nil {
            scanReadinessMessage = "Erro ao gerar modelo"
            scanQualityStatus = "Erro ao gerar modelo"
            scanReadinessBlockerSummary = "Erro STL: \(stlExportErrorMessage ?? "desconhecido")"
        } else {
            scanReadinessMessage = "Pronto para gerar modelo"
            scanQualityStatus = "Pronto para exportar"
            scanReadinessBlockerSummary = hasSTLExportURL ? "Pronto: STL gerado" : "Pronto: aguardando STL"
        }

        return exportURL
    }

    @MainActor
    private func setScanState(_ newState: ScanState) {
        guard scanState != newState else {
            return
        }

        previousScanState = scanState
        scanState = newState

        if newState == .ready {
            readyTransitionCount += 1
            lastSTLExportEventMessage = "Ready transition detected"
        }

        updateExportDiagnostics()
    }

    private func bindCameraCallbacks() {
        cameraService.onFrame = { [weak self] frame in
            self?.handleFrame(frame)
        }

        cameraService.onError = { [weak self] error in
            Task { @MainActor [weak self] in
                self?.handleCameraError(error)
            }
        }

        cameraService.onSessionDidBecomeActive = { [weak self] in
            Task { [weak self] in
                await self?.reapplyDesiredTorchIfNeeded()
            }
        }
    }

    private func reapplyDesiredTorchIfNeeded() async {
        let shouldReapplyTorch = await MainActor.run {
            desiredTorchEnabled && isTorchAvailable && cameraState == .running
        }

        guard shouldReapplyTorch else {
            return
        }

        do {
            let torchState = try await cameraService.setTorchEnabled(
                true,
                requiresRunningSession: true
            )

            await MainActor.run {
                isTorchAvailable = torchState.isAvailable
                isTorchEnabled = torchState.isEnabled

                if !torchState.isAvailable {
                    desiredTorchEnabled = false
                }

                errorMessage = nil
            }
        } catch {
            if isSessionNotPreparedError(error) {
                return
            }

            await MainActor.run {
                if desiredTorchEnabled {
                    errorMessage = makeErrorMessage(from: error)
                }
            }
        }
    }

    @MainActor
    private func turnOffTorchForInactiveCamera() {
        isTorchEnabled = false

        Task { [weak self] in
            guard let self else { return }

            do {
                let torchState = try await self.cameraService.setTorchEnabled(
                    false,
                    requiresRunningSession: false
                )

                await MainActor.run {
                    self.isTorchAvailable = torchState.isAvailable
                    self.isTorchEnabled = torchState.isEnabled
                }
            } catch {
                print("Erro ao desligar lanterna ao pausar camera: \(error)")
            }
        }
    }

    private func isSessionNotPreparedError(_ error: Error) -> Bool {
        guard let serviceError = error as? CameraFrameService.ServiceError else {
            return false
        }

        switch serviceError {
        case .sessionNotPrepared:
            return true
        default:
            return false
        }
    }

    private func handleFrame(_ frame: CameraFrame) {
        let metrics = buildFrameMetrics(from: frame)
        let rawArucoMetrics = detectArucoMarkers(in: frame)
        let validatedDetections = arUcoConsistencyFilter.filterDetections(rawArucoMetrics.detections)
        let arucoMetrics = arucoMetrics(
            rawArucoMetrics,
            replacingDetectionsWith: validatedDetections
        )
        let markerSizeMillimeters = poseMarkerSizeMillimeters
        let activeMarkerProfile = markerProfile
        let dualMarkerDefinitions = MarkerConfiguration.dualMarkers
        let poseMetrics = estimatePose(
            from: arucoMetrics.detections,
            in: frame,
            markerSizeMillimeters: markerSizeMillimeters,
            markerProfile: activeMarkerProfile,
            dualMarkerDefinitions: dualMarkerDefinitions
        )
        recordDualMarkerDetectionDiagnostics(
            rawDetections: rawArucoMetrics.detections,
            acceptedDetections: arucoMetrics.detections,
            markerProfile: activeMarkerProfile,
            timestamp: metrics.lastFrameTimestamp,
            frameIndex: metrics.totalFramesReceived
        )
        recordDualMarkerPoseDiagnostics(
            poseResults: poseMetrics.rawPoseResults,
            markerProfile: activeMarkerProfile,
            dualMarkerDefinitions: dualMarkerDefinitions,
            timestamp: metrics.lastFrameTimestamp,
            frameIndex: metrics.totalFramesReceived
        )
        let dualMarkerDebugStates = makeDualMarkerDebugStates(
            rawDetections: rawArucoMetrics.detections,
            acceptedDetections: arucoMetrics.detections,
            poseResults: poseMetrics.rawPoseResults,
            markerProfile: activeMarkerProfile,
            dualMarkerDefinitions: dualMarkerDefinitions,
            timestamp: metrics.lastFrameTimestamp,
            frameIndex: metrics.totalFramesReceived
        )
        let overlayMarkers = stabilizedOverlayMarkers(
            from: makeOverlayMarkers(
                detections: arucoMetrics.detections,
                poseResults: poseMetrics.rawPoseResults,
                markerProfile: activeMarkerProfile,
                dualMarkerDefinitions: dualMarkerDefinitions,
                timestamp: metrics.lastFrameTimestamp,
                frameIndex: metrics.totalFramesReceived
            ),
            timestamp: metrics.lastFrameTimestamp,
            markerProfile: activeMarkerProfile
        )
        let scanStateForFrame = scanState
        let shouldCollectScanFrame = scanStateForFrame.isCollectingFrames
        let fusedPoseResults = shouldCollectScanFrame
            ? multiFramePoseAccumulator.update(with: poseMetrics.rawPoseResults)
            : self.fusedPoseResults
        let consolidatedPoseResults = shouldCollectScanFrame
            ? (fusedPoseResults.isEmpty ? poseMetrics.rawPoseResults : fusedPoseResults)
            : []
        let implantMetrics = shouldCollectScanFrame
            ? estimateImplantPoses(from: consolidatedPoseResults)
            : ImplantMetrics(implantPoseResults: [])
        let frameFinalPoseObservations = shouldCollectScanFrame
            ? makeFinalPoseObservations(
                from: arucoMetrics.detections,
                poseResults: poseMetrics.rawPoseResults,
                in: frame,
                markerSizeMillimeters: markerSizeMillimeters,
                markerProfile: activeMarkerProfile,
                dualMarkerDefinitions: dualMarkerDefinitions
            )
            : []

        Task { @MainActor [weak self] in
            guard let self else { return }
            self.totalFramesReceived = metrics.totalFramesReceived
            self.estimatedFPS = metrics.estimatedFPS
            self.lastFrameTimestamp = metrics.lastFrameTimestamp
            self.frameResolution = metrics.frameResolution
            self.isIntrinsicMatrixAvailable = metrics.isIntrinsicMatrixAvailable
            self.isOpenCVAvailable = arucoMetrics.isOpenCVAvailable
            self.detectedMarkerCount = arucoMetrics.detectedMarkerCount
            self.detectedMarkerIds = arucoMetrics.detectedMarkerIds
            self.detectedMarkers = arucoMetrics.detections
            self.overlayMarkers = overlayMarkers
            self.arucoErrorMessage = arucoMetrics.errorMessage
            self.hasFrameReachedArucoDetector = arucoMetrics.hasFrameReachedDetector
            self.arucoDetectionCallCount = arucoMetrics.detectionCallCount
            self.arucoFrameResolution = arucoMetrics.frameResolution
            self.arucoFramePixelFormat = arucoMetrics.pixelFormat
            self.arucoBytesPerRow = arucoMetrics.bytesPerRow
            self.arucoDictionaryName = arucoMetrics.dictionaryName
            self.arucoPreprocessingDescription = arucoMetrics.preprocessingDescription
            self.arucoInputChannelCount = arucoMetrics.inputChannelCount
            self.arucoGrayscaleChannelCount = arucoMetrics.grayscaleChannelCount
            self.arucoRejectedCandidateCount = arucoMetrics.rejectedCandidateCount
            self.rawPoseResults = poseMetrics.rawPoseResults
            self.rawPoseResult = poseMetrics.rawPoseResult
            self.stablePoseResult = poseMetrics.stablePoseResult
            self.poseStabilityStatus = poseMetrics.stabilityStatus
            self.poseMarkerId = poseMetrics.stablePoseResult?.markerId ?? poseMetrics.rawPoseResult?.markerId
            self.poseDistanceMm = poseMetrics.stablePoseResult?.distanceMm
            self.poseReprojectionError = poseMetrics.rawPoseResult?.reprojectionError
            self.poseErrorMessage = poseMetrics.errorMessage
            self.dualMarkerDebugStates = dualMarkerDebugStates

            if shouldCollectScanFrame && self.scanState.isCollectingFrames {
                self.fusedPoseResults = fusedPoseResults
                self.implantPoseResults = implantMetrics.implantPoseResults
                self.implantPoseResult = implantMetrics.implantPoseResults.first
                self.selectedTagDistanceMm = self.selectedTagDistance(in: consolidatedPoseResults)
                self.selectedImplantDistanceMm = self.selectedImplantDistance(
                    in: implantMetrics.implantPoseResults
                )
                self.updatePrecisionValidationCurrentError()
                self.recordScanFrame(
                    rawPoseResults: poseMetrics.rawPoseResults,
                    consolidatedPoseResults: consolidatedPoseResults,
                    finalPoseObservations: frameFinalPoseObservations,
                    timestamp: metrics.lastFrameTimestamp,
                    frameIndex: metrics.totalFramesReceived
                )
            }
        }
    }

    @MainActor
    private func resetScanSession() {
        arUcoConsistencyFilter.reset()
        multiFramePoseAccumulator.reset()
        fusedPoseResults = []
        implantPoseResults = []
        implantPoseResult = nil
        dualMarkerDebugStates = []
        selectedTagDistanceMm = nil
        selectedImplantDistanceMm = nil
        stlExportURL = nil
        stlExportedImplantCount = 0
        stlExportErrorMessage = nil
        isGeneratingSTL = false
        canExportSTL = false
        hasSTLExportFile = false
        hasSTLExportURL = false
        currentExportableTagPoseCount = 0
        stlExportGenerationID = UUID()
        setScanState(.idle)
        scanProgress = 0
        scanQualityScore = 0
        scanValidFrameCount = 0
        scanAverageDistanceMm = nil
        scanAverageReprojectionError = nil
        scanPoseJitterMm = nil
        scanPositionJitterMm = nil
        scanRotationJitterDegrees = nil
        scanStableReadinessDurationSeconds = 0
        scanQualityStatus = "Aguardando inicio"
        scanReadinessMessage = "Aguardando inicio"
        scanReadinessBlockerSummary = "Aguardando inicio"
        scanCoverageReady = false
        scanGoodFramesReady = false
        scanDistanceReady = false
        scanReprojectionReady = false
        scanJitterReady = false
        scanStableReady = false
        scanCurrentFrameGood = false
        scanDualTagReady = false
        scanTagCoverages = [:]
        scanReprojectionErrors = []
        scanPoseHistoryByMarkerId = [:]
        scanCoverageBinsByMarkerId = [:]
        scanFrameCountsByMarkerId = [:]
        scanDualTagFrameCountsByMarkerId = [:]
        scanTopFallbackFrameCountsByMarkerId = [:]
        scanBottomFallbackFrameCountsByMarkerId = [:]
        scanReadinessStableStartTimestamp = nil
        scanCurrentFrameIsGood = false
        scanCurrentFrameReadinessBlocker = nil
        resetPrecisionValidationHistory()
        finalPoseObservations = []
        dualRawDetectionCountsByTagId = [:]
        dualAcceptedDetectionCountsByTagId = [:]
        dualRecentDetectionHistoryByTagId = [:]
        dualRecentDualTagPoseHistoryByMarkerId = [:]
        lastValidOverlayMarkers = []
        lastValidOverlayMarkersByMarkerId = [:]
        lastValidOverlayTimestamp = nil
        didApplyFinalPoseRefinement = false
        readyTransitionCount = 0
        didCallHandleScanBecameReady = false
        didCallSaveCurrentScanIfNeeded = false
        didStartSTLExportForCurrentScan = false
        lastSTLExportTagPoseCount = 0
        lastSTLExportEventMessage = "Aguardando"
        lastSTLReferenceModelFileName = "-"
        lastSTLExportMarkerIds = []
        lastSTLExportMarkerProfile = markerProfile
        lastSTLExportBottomTagSizeMillimeters = nil
        lastSTLExportBottomCenterYMillimeters = nil
    }

    @MainActor
    private func recordScanFrame(
        rawPoseResults: [PoseResult],
        consolidatedPoseResults: [PoseResult],
        finalPoseObservations: [FinalPoseObservation],
        timestamp: Double,
        frameIndex: Int
    ) {
        guard scanState.isCollectingFrames else {
            return
        }

        scanAverageDistanceMm = averageDistance(in: rawPoseResults)

        let frameReprojectionError = averageReprojectionError(in: rawPoseResults)
        let goodPoseResults = rawPoseResults.filter {
            isGoodFrame($0, timestamp: timestamp, frameIndex: frameIndex)
        }
        let goodMarkerIds = Set(goodPoseResults.map(\.markerId))

        guard !goodPoseResults.isEmpty,
              let goodFrameReprojectionError = averageReprojectionError(in: goodPoseResults)
        else {
            rebuildScanTagCoverages()
            scanCurrentFrameIsGood = false
            scanCurrentFrameReadinessBlocker = scanReadinessBlockerMessage(
                rawPoseResults: rawPoseResults,
                averageDistanceMm: scanAverageDistanceMm,
                averageReprojectionError: frameReprojectionError
            )
            updateScanProgressAndState(
                timestamp: timestamp
            )
            return
        }

        scanCurrentFrameIsGood = true
        scanCurrentFrameReadinessBlocker = nil
        scanAverageDistanceMm = averageDistance(in: goodPoseResults) ?? scanAverageDistanceMm

        scanValidFrameCount += 1
        self.finalPoseObservations.append(
            contentsOf: finalPoseObservations.filter { goodMarkerIds.contains($0.markerId) }
        )
        scanReprojectionErrors.append(goodFrameReprojectionError)
        trimRecentValues(&scanReprojectionErrors, to: scanTargetValidFrameCount)

        recordAngularCoverage(from: goodPoseResults)
        recordDualArucoV2PoseSourceFrames(from: goodPoseResults)

        let goodConsolidatedPoseResults = consolidatedPoseResults.filter {
            goodMarkerIds.contains($0.markerId)
        }
        recordPrecisionValidationSample(
            from: goodConsolidatedPoseResults.isEmpty ? goodPoseResults : goodConsolidatedPoseResults
        )
        recordPoseStability(from: goodPoseResults)

        scanAverageReprojectionError = average(scanReprojectionErrors)
        scanPositionJitterMm = positionJitterMillimeters()
        scanPoseJitterMm = scanPositionJitterMm
        scanRotationJitterDegrees = rotationJitterDegrees()
        updateScanProgressAndState(
            timestamp: timestamp
        )
        updateExportDiagnostics()
    }

    @MainActor
    private func updateScanProgressAndState(
        timestamp: Double
    ) {
        let tagCoverageScore = minimumTagCoverageProgress()
        let globalFrameScore = min(
            Double(scanValidFrameCount) / Double(scanTargetValidFrameCount),
            1.0
        )
        let perTagFrameScore = minimumTagGoodFrameProgress()
        let frameScore = min(globalFrameScore, perTagFrameScore)
        let errorScore = qualityScoreForReprojectionError(scanAverageReprojectionError)
        let positionStabilityScore = qualityScoreForPoseJitter(scanPositionJitterMm)
        let rotationStabilityScore = qualityScoreForRotationJitter(scanRotationJitterDegrees)
        let distanceScore = qualityScoreForDistance(scanAverageDistanceMm)
        let combinedQualityScore = tagCoverageScore * 0.35 +
            frameScore * 0.20 +
            errorScore * 0.15 +
            positionStabilityScore * 0.15 +
            rotationStabilityScore * 0.10 +
            distanceScore * 0.05
        updateExportDiagnostics()
        let evaluation = scanReadinessEvaluation()
        let currentTimestamp = timestamp.isFinite ? timestamp : Date().timeIntervalSinceReferenceDate

        updateStableReadinessDuration(
            isReadyCandidate: evaluation.isReadyCandidate,
            timestamp: currentTimestamp
        )

        let hasStableDuration = scanStableReadinessDurationSeconds >=
            scanReadinessConfiguration.requiredStableDurationSeconds
        let isReady = evaluation.isReadyCandidate && hasStableDuration
        publishReadinessDiagnostics(
            evaluation,
            hasStableDuration: hasStableDuration
        )
        scanReadinessBlockerSummary = readinessBlockerSummary(
            for: evaluation,
            hasStableDuration: hasStableDuration
        )

        scanQualityScore = combinedQualityScore * 100.0

        if isReady {
            setScanState(.ready)
            scanProgress = 100
            handleScanBecameReady()
            return
        }

        let nextScanState: ScanState = scanValidFrameCount >= minimumStabilizingFrameCount
            ? .stabilizing
            : .scanning
        setScanState(nextScanState)
        scanProgress = min(min(tagCoverageScore, frameScore) * 100.0, 99)
        scanReadinessMessage = readinessMessage(
            for: evaluation,
            hasStableDuration: hasStableDuration
        )
        scanQualityStatus = scanReadinessMessage
        updateExportDiagnostics()
    }

    private func publishReadinessDiagnostics(
        _ evaluation: ScanReadinessEvaluation,
        hasStableDuration: Bool
    ) {
        scanCoverageReady = evaluation.hasCompleteTagCoverage
        scanGoodFramesReady = evaluation.hasEnoughGoodFrames && evaluation.hasPerTagGoodFrames
        scanDistanceReady = evaluation.hasAcceptableDistance
        scanReprojectionReady = evaluation.hasAcceptableReprojectionError
        scanJitterReady = evaluation.hasStablePosition && evaluation.hasStableRotation
        scanStableReady = hasStableDuration
        scanCurrentFrameGood = evaluation.hasCurrentGoodFrame
        scanDualTagReady = evaluation.hasMinimumDualTagFrames
    }

    @MainActor
    private func applyFinalPoseRefinementIfNeeded() {
        guard !didApplyFinalPoseRefinement,
              !finalPoseObservations.isEmpty
        else {
            return
        }

        didApplyFinalPoseRefinement = true

        let currentPoseResults = consolidatedPoseResults()
        let refinedPoseResults = finalPoseRefiner.refine(
            observations: finalPoseObservations,
            currentPoseResults: currentPoseResults
        )
        guard !refinedPoseResults.isEmpty,
              refinedPoseResults != currentPoseResults
        else {
            return
        }

        fusedPoseResults = refinedPoseResults

        let implantMetrics = estimateImplantPoses(from: refinedPoseResults)
        implantPoseResults = implantMetrics.implantPoseResults
        implantPoseResult = implantMetrics.implantPoseResults.first
        selectedTagDistanceMm = selectedTagDistance(in: refinedPoseResults)
        selectedImplantDistanceMm = selectedImplantDistance(
            in: implantMetrics.implantPoseResults
        )
        updatePrecisionValidationCurrentError()
    }

    private var minimumStabilizingFrameCount: Int {
        max(3, scanTargetValidFrameCount / 2)
    }

    private var hasCompleteTagCoverage: Bool {
        !activeTagCoverages.isEmpty &&
            activeTagCoverages.allSatisfy {
                $0.rawAngularCoveragePercent + 0.0001 >= $0.requiredAngularCoveragePercent
            }
    }

    private func minimumTagCoverageProgress() -> Double {
        guard !activeTagCoverages.isEmpty else {
            return 0
        }

        let minimumProgress = activeTagCoverages
            .map { normalizedCoverage($0.progress / 100.0) }
            .min() ?? 0

        return minimumProgress
    }

    private func minimumObservedAngularCoveragePercent() -> Double {
        guard !activeTagCoverages.isEmpty else {
            return 0
        }

        return activeTagCoverages
            .map { normalizedCoverage($0.rawAngularCoveragePercent / 100.0) * 100.0 }
            .min() ?? 0
    }

    private func minimumTagGoodFrameProgress() -> Double {
        guard !activeTagCoverages.isEmpty else {
            return 0
        }

        return activeTagCoverages
            .map {
                normalizedCoverage(
                    Double($0.observedFrameCount) /
                        Double(scanReadinessConfiguration.minimumGoodFrames)
                )
            }
            .min() ?? 0
    }

    private var activeTagCoverages: [ScanTagCoverage] {
        if markerProfile == .dualArucoV2 {
            return MarkerConfiguration.dualMarkers
                .map(\.physicalMarkerId)
                .sorted()
                .map { coverage(forPhysicalMarkerId: $0) }
        }

        return observedTagCoverages
    }

    private var observedTagCoverages: [ScanTagCoverage] {
        scanTagCoverages.values
            .filter { $0.coveredBinCount > 0 || $0.observedFrameCount > 0 }
            .sorted { $0.markerId < $1.markerId }
    }

    private func normalizedCoverage(_ value: Double) -> Double {
        let clamped = clampedCoverage(value)
        return clamped >= ScanConfiguration.completedCoverageThreshold ? 1.0 : clamped
    }

    private func clampedCoverage(_ value: Double) -> Double {
        guard value.isFinite else {
            return 0
        }

        return min(max(value, 0.0), 1.0)
    }

    private func scanReadinessEvaluation() -> ScanReadinessEvaluation {
        let hasTags = !observedTagCoverages.isEmpty
        let hasEnoughGoodFrames = scanValidFrameCount >= scanReadinessConfiguration.minimumGoodFrames
        let hasPerTagGoodFrames = hasTags && activeTagCoverages.allSatisfy {
            $0.observedFrameCount >= scanReadinessConfiguration.minimumGoodFrames
        }
        let hasAcceptableDistance = isAcceptableScanDistance(scanAverageDistanceMm)
        let hasAcceptableReprojectionError = (scanAverageReprojectionError ?? .infinity) <=
            scanReadinessConfiguration.maximumAverageReprojectionError
        let hasStablePosition = (scanPositionJitterMm ?? .infinity) <=
            scanReadinessConfiguration.maximumPositionJitterMm
        let hasStableRotation = (scanRotationJitterDegrees ?? .infinity) <=
            scanReadinessConfiguration.maximumRotationJitterDegrees
        let hasExportableTagPoses = currentExportableTagPoseCount > 0
        let hasMinimumDualTagFrames = hasMinimumDualTagFramesPerMarker()

        return ScanReadinessEvaluation(
            hasCurrentGoodFrame: scanCurrentFrameIsGood,
            hasTags: hasTags,
            hasCompleteTagCoverage: hasCompleteTagCoverage,
            hasEnoughGoodFrames: hasEnoughGoodFrames,
            hasPerTagGoodFrames: hasPerTagGoodFrames,
            hasMinimumDualTagFrames: hasMinimumDualTagFrames,
            hasAcceptableDistance: hasAcceptableDistance,
            hasAcceptableReprojectionError: hasAcceptableReprojectionError,
            hasStablePosition: hasStablePosition,
            hasStableRotation: hasStableRotation,
            hasExportableTagPoses: hasExportableTagPoses
        )
    }

    private func hasMinimumDualTagFramesPerMarker() -> Bool {
        guard markerProfile == .dualArucoV2,
              scanMinimumDualTagFrameCount > 0
        else {
            return true
        }

        let physicalMarkerIds = MarkerConfiguration.dualMarkers.map(\.physicalMarkerId)
        guard !physicalMarkerIds.isEmpty else {
            return false
        }

        return physicalMarkerIds.allSatisfy {
            (scanDualTagFrameCountsByMarkerId[$0] ?? 0) >= scanMinimumDualTagFrameCount
        }
    }

    private func readinessMessage(
        for evaluation: ScanReadinessEvaluation,
        hasStableDuration: Bool
    ) -> String {
        if !evaluation.hasTags {
            return "Procurando pose"
        }

        if !evaluation.hasCompleteTagCoverage {
            return "Colete mais angulos"
        }

        if !evaluation.hasMinimumDualTagFrames {
            return "Capture melhor as duas tags"
        }

        if !evaluation.hasEnoughGoodFrames || !evaluation.hasPerTagGoodFrames {
            return "Colete mais frames bons"
        }

        if !evaluation.hasAcceptableReprojectionError {
            return "Melhorando precisao..."
        }

        if !evaluation.hasExportableTagPoses {
            return "Preparando poses"
        }

        if !hasStableDuration {
            return "Aguardando estabilidade"
        }

        if !evaluation.hasCurrentGoodFrame {
            return scanCurrentFrameReadinessBlocker ?? "Aguardando frame bom"
        }

        if !evaluation.hasAcceptableDistance {
            guard let scanAverageDistanceMm else {
                return "Procurando pose"
            }

            return scanAverageDistanceMm < scanReadinessConfiguration.minimumDistanceMm
                ? "Afaste um pouco"
                : "Aproxime um pouco"
        }

        if !evaluation.hasStablePosition || !evaluation.hasStableRotation {
            return "Mantenha estavel"
        }

        return "Preparando finalizacao"
    }

    private func readinessBlockerSummary(
        for evaluation: ScanReadinessEvaluation,
        hasStableDuration: Bool
    ) -> String {
        if scanState == .ready {
            if isGeneratingSTL {
                return "Pronto: gerando STL"
            }

            if let stlExportErrorMessage {
                return "Erro STL: \(stlExportErrorMessage)"
            }

            return hasSTLExportURL ? "Pronto: STL gerado" : "Pronto: aguardando STL"
        }

        if !evaluation.hasTags {
            return "Bloqueio principal: tags"
        }

        if !evaluation.hasCompleteTagCoverage {
            return "Bloqueio principal: cobertura"
        }

        if !evaluation.hasMinimumDualTagFrames {
            return "Bloqueio principal: dual-tag"
        }

        if !evaluation.hasEnoughGoodFrames || !evaluation.hasPerTagGoodFrames {
            return "Bloqueio principal: frames bons"
        }

        if !evaluation.hasAcceptableReprojectionError {
            return "Bloqueio principal: reprojection"
        }

        if !evaluation.hasExportableTagPoses {
            return "Bloqueio principal: poses exportaveis"
        }

        if !hasStableDuration {
            return "Bloqueio principal: aguardando estabilidade"
        }

        if !evaluation.hasAcceptableDistance {
            return "Aviso: distancia fora ideal"
        }

        if !evaluation.hasStablePosition || !evaluation.hasStableRotation {
            return "Aviso: jitter alto"
        }

        if !evaluation.hasCurrentGoodFrame {
            return "Aviso: frame atual ruim"
        }

        return "Pronto: gerando STL"
    }

    private func scanReadinessBlockerMessage(
        rawPoseResults: [PoseResult],
        averageDistanceMm: Double?,
        averageReprojectionError: Double?
    ) -> String {
        guard !rawPoseResults.isEmpty else {
            return "Procurando pose"
        }

        if let averageDistanceMm {
            if averageDistanceMm < scanReadinessConfiguration.minimumDistanceMm {
                return "Afaste um pouco"
            }

            if averageDistanceMm > scanReadinessConfiguration.maximumDistanceMm {
                return "Aproxime um pouco"
            }
        }

        if let averageReprojectionError,
           averageReprojectionError > scanReadinessConfiguration.maximumAverageReprojectionError {
            return "Melhorando precisao..."
        }

        return "Capturando"
    }

    private func updateStableReadinessDuration(
        isReadyCandidate: Bool,
        timestamp: Double
    ) {
        guard isReadyCandidate else {
            scanReadinessStableStartTimestamp = nil
            scanStableReadinessDurationSeconds = 0
            return
        }

        guard let scanReadinessStableStartTimestamp else {
            self.scanReadinessStableStartTimestamp = timestamp
            scanStableReadinessDurationSeconds = 0
            return
        }

        scanStableReadinessDurationSeconds = max(timestamp - scanReadinessStableStartTimestamp, 0)
    }

    private func isGoodFrame(
        _ pose: PoseResult,
        timestamp: Double,
        frameIndex: Int
    ) -> Bool {
        let distanceMm = simd_length(pose.translationVector)

        let hasValidGeometry = pose.markerId >= 0 &&
            pose.reprojectionError.isFinite &&
            pose.reprojectionError <= scanReadinessConfiguration.maximumAverageReprojectionError &&
            distanceMm.isFinite &&
            distanceMm >= scanReadinessConfiguration.minimumDistanceMm &&
            distanceMm <= scanReadinessConfiguration.maximumDistanceMm &&
            pose.markerAreaPixels.isFinite &&
            PoseMath.isFinite(pose.rotationVector) &&
            PoseMath.isFinite(pose.rotationMatrix) &&
            PoseMath.isFinite(pose.translationVector)

        guard hasValidGeometry else {
            return false
        }

        guard markerProfile == .dualArucoV2 else {
            return true
        }

        switch pose.poseSource {
        case .dualTag:
            return true
        case let .singleFallback(_, role):
            switch role {
            case .top:
                return true
            case .bottom:
                return hasRecentDualTagPose(
                    forPhysicalMarkerId: pose.markerId,
                    currentTimestamp: timestamp,
                    currentFrameIndex: frameIndex
                )
            }
        case .singleArucoV1:
            return false
        }
    }

    private func isAcceptableScanDistance(_ distanceMm: Double?) -> Bool {
        guard let distanceMm, distanceMm.isFinite else {
            return false
        }

        return distanceMm >= scanReadinessConfiguration.minimumDistanceMm &&
            distanceMm <= scanReadinessConfiguration.maximumDistanceMm
    }

    @MainActor
    private func recordAngularCoverage(from poseResults: [PoseResult]) {
        for poseResult in poseResults {
            guard let coverageBin = angularCoverageBin(for: poseResult) else {
                continue
            }

            scanCoverageBinsByMarkerId[poseResult.markerId, default: []].insert(coverageBin)
            scanFrameCountsByMarkerId[poseResult.markerId, default: 0] += 1
        }

        rebuildScanTagCoverages()
    }

    @MainActor
    private func recordDualArucoV2PoseSourceFrames(from poseResults: [PoseResult]) {
        guard markerProfile == .dualArucoV2 else {
            return
        }

        for poseResult in poseResults {
            switch poseResult.poseSource {
            case .dualTag:
                scanDualTagFrameCountsByMarkerId[poseResult.markerId, default: 0] += 1
            case let .singleFallback(_, role):
                switch role {
                case .top:
                    scanTopFallbackFrameCountsByMarkerId[poseResult.markerId, default: 0] += 1
                case .bottom:
                    scanBottomFallbackFrameCountsByMarkerId[poseResult.markerId, default: 0] += 1
                }
            case .singleArucoV1:
                continue
            }
        }
    }

    @MainActor
    private func rebuildScanTagCoverages() {
        let requiredBinCount = scanRequiredAngularCoverageBinCount()
        var markerIds = Set(scanCoverageBinsByMarkerId.keys).union(scanFrameCountsByMarkerId.keys)
        if markerProfile == .dualArucoV2 {
            markerIds.formUnion(MarkerConfiguration.dualMarkers.map(\.physicalMarkerId))
        }

        scanTagCoverages = markerIds.reduce(into: [:]) { partialResult, markerId in
            let coveredBinCount = scanCoverageBinsByMarkerId[markerId]?.count ?? 0
            let rawActualCoverage = Double(coveredBinCount) / Double(totalAngularCoverageBinCount)
            let rawAngularCoveragePercent = clampedCoverage(rawActualCoverage) * 100.0
            let requiredCoverage = max(scanRequiredAngularCoveragePercent / 100.0, 0.01)
            let progress = normalizedCoverage(rawActualCoverage / requiredCoverage) * 100.0

            partialResult[markerId] = ScanTagCoverage(
                markerId: markerId,
                rawAngularCoveragePercent: rawAngularCoveragePercent,
                requiredAngularCoveragePercent: scanRequiredAngularCoveragePercent,
                normalizedCoverageProgress: progress,
                coveredBinCount: coveredBinCount,
                requiredBinCount: requiredBinCount,
                observedFrameCount: scanFrameCountsByMarkerId[markerId] ?? 0
            )
        }
    }

    private func coverage(forPhysicalMarkerId markerId: Int) -> ScanTagCoverage {
        if let coverage = scanTagCoverages[markerId] {
            return coverage
        }

        return ScanTagCoverage(
            markerId: markerId,
            rawAngularCoveragePercent: 0,
            requiredAngularCoveragePercent: scanRequiredAngularCoveragePercent,
            normalizedCoverageProgress: 0,
            coveredBinCount: 0,
            requiredBinCount: scanRequiredAngularCoverageBinCount(),
            observedFrameCount: 0
        )
    }

    private func scanRequiredAngularCoverageBinCount() -> Int {
        max(
            1,
            Int(
                ceil(
                    Double(totalAngularCoverageBinCount) *
                        scanRequiredAngularCoveragePercent / 100.0
                )
            )
        )
    }

    private var totalAngularCoverageBinCount: Int {
        ScanConfiguration.azimuthBinCount * ScanConfiguration.elevationBinCount
    }

    private func angularCoverageBin(for poseResult: PoseResult) -> Int? {
        guard let direction = cameraToTagDirectionInMarkerSpace(for: poseResult) else {
            return nil
        }

        let azimuth = atan2(direction.y, direction.x)
        let normalizedAzimuth = (azimuth + Double.pi) / (2.0 * Double.pi)
        let azimuthBin = min(
            max(Int(normalizedAzimuth * Double(ScanConfiguration.azimuthBinCount)), 0),
            ScanConfiguration.azimuthBinCount - 1
        )
        let elevation = asin(min(max(direction.z, -1.0), 1.0))
        let normalizedElevation = (elevation + Double.pi / 2.0) / Double.pi
        let elevationBin = min(
            max(Int(normalizedElevation * Double(ScanConfiguration.elevationBinCount)), 0),
            ScanConfiguration.elevationBinCount - 1
        )

        return elevationBin * ScanConfiguration.azimuthBinCount + azimuthBin
    }

    private func cameraToTagDirectionInMarkerSpace(for poseResult: PoseResult) -> SIMD3<Double>? {
        let cameraToTagLength = simd_length(poseResult.translationVector)
        guard cameraToTagLength.isFinite, cameraToTagLength > 1e-9 else {
            return nil
        }

        let cameraToTagDirectionInCameraSpace = poseResult.translationVector / cameraToTagLength
        let markerRotation = poseResult.rotationMatrix
        let cameraToTagDirectionInMarkerSpace = simd_transpose(markerRotation) *
            cameraToTagDirectionInCameraSpace
        let directionLength = simd_length(cameraToTagDirectionInMarkerSpace)

        guard directionLength.isFinite, directionLength > 1e-9 else {
            return nil
        }

        return cameraToTagDirectionInMarkerSpace / directionLength
    }

    private func averageReprojectionError(in poseResults: [PoseResult]) -> Double? {
        let errors = poseResults
            .map(\.reprojectionError)
            .filter { $0.isFinite }

        return average(errors)
    }

    private func averageDistance(in poseResults: [PoseResult]) -> Double? {
        let distances = poseResults
            .map { simd_length($0.translationVector) }
            .filter { $0.isFinite }

        return average(distances)
    }

    private func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else {
            return nil
        }

        return values.reduce(0.0, +) / Double(values.count)
    }

    private func trimRecentValues<T>(_ values: inout [T], to limit: Int) {
        guard values.count > limit else {
            return
        }

        values.removeFirst(values.count - limit)
    }

    private func qualityScoreForReprojectionError(_ reprojectionError: Double?) -> Double {
        guard let reprojectionError, reprojectionError.isFinite else {
            return 0
        }

        if reprojectionError <= ScanConfiguration.targetAverageReprojectionError {
            return 1
        }

        if reprojectionError >= ScanConfiguration.maximumAverageReprojectionError {
            return 0
        }

        return (
            ScanConfiguration.maximumAverageReprojectionError - reprojectionError
        ) / (
            ScanConfiguration.maximumAverageReprojectionError -
                ScanConfiguration.targetAverageReprojectionError
        )
    }

    private func qualityScoreForPoseJitter(_ poseJitterMm: Double?) -> Double {
        guard let poseJitterMm, poseJitterMm.isFinite else {
            return scanValidFrameCount > 0 ? 0.25 : 0
        }

        if poseJitterMm <= ScanConfiguration.targetPoseJitterMm {
            return 1
        }

        if poseJitterMm >= ScanConfiguration.maximumPoseJitterMm {
            return 0
        }

        return (
            ScanConfiguration.maximumPoseJitterMm - poseJitterMm
        ) / (
            ScanConfiguration.maximumPoseJitterMm - ScanConfiguration.targetPoseJitterMm
        )
    }

    private func qualityScoreForRotationJitter(_ rotationJitterDegrees: Double?) -> Double {
        guard let rotationJitterDegrees, rotationJitterDegrees.isFinite else {
            return scanValidFrameCount > 0 ? 0.25 : 0
        }

        if rotationJitterDegrees <= ScanConfiguration.targetRotationJitterDegrees {
            return 1
        }

        if rotationJitterDegrees >= ScanConfiguration.maximumRotationJitterDegrees {
            return 0
        }

        return (
            ScanConfiguration.maximumRotationJitterDegrees - rotationJitterDegrees
        ) / (
            ScanConfiguration.maximumRotationJitterDegrees -
                ScanConfiguration.targetRotationJitterDegrees
        )
    }

    private func qualityScoreForDistance(_ distanceMm: Double?) -> Double {
        guard let distanceMm, distanceMm.isFinite else {
            return 0
        }

        if distanceMm >= scanReadinessConfiguration.idealMinimumDistanceMm &&
            distanceMm <= scanReadinessConfiguration.idealMaximumDistanceMm {
            return 1
        }

        if distanceMm < scanReadinessConfiguration.minimumDistanceMm ||
            distanceMm > scanReadinessConfiguration.maximumDistanceMm {
            return 0
        }

        if distanceMm < scanReadinessConfiguration.idealMinimumDistanceMm {
            let range = scanReadinessConfiguration.idealMinimumDistanceMm -
                scanReadinessConfiguration.minimumDistanceMm
            return (distanceMm - scanReadinessConfiguration.minimumDistanceMm) / max(range, 1)
        }

        let range = scanReadinessConfiguration.maximumDistanceMm -
            scanReadinessConfiguration.idealMaximumDistanceMm
        return (scanReadinessConfiguration.maximumDistanceMm - distanceMm) / max(range, 1)
    }

    private func recordPoseStability(from poseResults: [PoseResult]) {
        for poseResult in poseResults {
            guard let rotation = PoseMath.quaternion(fromRotationMatrix: poseResult.rotationMatrix) else {
                continue
            }

            var samples = scanPoseHistoryByMarkerId[poseResult.markerId, default: []]
            samples.append(
                ScanPoseSample(
                    translationVector: poseResult.translationVector,
                    rotation: rotation
                )
            )
            trimRecentValues(&samples, to: ScanConfiguration.poseStabilityWindowCount)
            scanPoseHistoryByMarkerId[poseResult.markerId] = samples
        }
    }

    private func positionJitterMillimeters() -> Double? {
        let jitters = scanPoseHistoryByMarkerId.values.compactMap { samples -> Double? in
            guard samples.count >= 3 else {
                return nil
            }

            let count = Double(samples.count)
            let meanTranslation = samples.reduce(SIMD3<Double>.zero) {
                $0 + $1.translationVector
            } / count
            let totalDistanceFromMean = samples.reduce(0.0) {
                $0 + simd_distance($1.translationVector, meanTranslation)
            }

            return totalDistanceFromMean / count
        }

        return jitters.max()
    }

    private func rotationJitterDegrees() -> Double? {
        let jitters = scanPoseHistoryByMarkerId.values.compactMap { samples -> Double? in
            guard samples.count >= 3,
                  let latestRotation = samples.last?.rotation
            else {
                return nil
            }

            let totalAngularDistance = samples.reduce(0.0) {
                $0 + angularDistanceDegrees(between: $1.rotation, and: latestRotation)
            }

            return totalAngularDistance / Double(samples.count)
        }

        return jitters.max()
    }

    private func angularDistanceDegrees(
        between firstRotation: simd_quatd,
        and secondRotation: simd_quatd
    ) -> Double {
        let firstVector = firstRotation.vector
        let secondVector = secondRotation.vector
        let firstLength = sqrt(
            firstVector.x * firstVector.x +
                firstVector.y * firstVector.y +
                firstVector.z * firstVector.z +
                firstVector.w * firstVector.w
        )
        let secondLength = sqrt(
            secondVector.x * secondVector.x +
                secondVector.y * secondVector.y +
                secondVector.z * secondVector.z +
                secondVector.w * secondVector.w
        )
        guard firstLength.isFinite, firstLength > 1e-12,
              secondLength.isFinite, secondLength > 1e-12
        else {
            return .infinity
        }

        let dot = abs((
            firstVector.x * secondVector.x +
                firstVector.y * secondVector.y +
                firstVector.z * secondVector.z +
                firstVector.w * secondVector.w
        ) / (firstLength * secondLength))
        let radians = 2.0 * acos(min(max(dot, 0.0), 1.0))

        return radians * 180.0 / Double.pi
    }

    private func buildFrameMetrics(from frame: CameraFrame) -> FrameMetrics {
        totalFramesCounter += 1
        let timestamp = frame.timestampSeconds
        let estimatedFPS = updateEstimatedFPS(with: timestamp)

        return FrameMetrics(
            totalFramesReceived: totalFramesCounter,
            estimatedFPS: estimatedFPS,
            lastFrameTimestamp: timestamp,
            frameResolution: FrameResolution(width: frame.width, height: frame.height),
            isIntrinsicMatrixAvailable: frame.metadata.intrinsicMatrix != nil
        )
    }

    private func stabilizedOverlayMarkers(
        from markers: [MarkerOverlayResult],
        timestamp: Double,
        markerProfile: MarkerProfile
    ) -> [MarkerOverlayResult] {
        guard timestamp.isFinite else {
            return markers
        }

        guard markerProfile == .dualArucoV2 else {
            if !markers.isEmpty {
                lastValidOverlayMarkers = markers
                lastValidOverlayTimestamp = timestamp
                return markers
            }

            guard let lastValidOverlayTimestamp else {
                lastValidOverlayMarkers = []
                return []
            }

            if timestamp - lastValidOverlayTimestamp <= OverlayStabilization.timeout {
                return lastValidOverlayMarkers
            }

            lastValidOverlayMarkers = []
            self.lastValidOverlayTimestamp = nil
            return []
        }

        if !markers.isEmpty {
            for marker in markers {
                lastValidOverlayMarkersByMarkerId[marker.markerId] = OverlayMarkerSample(
                    marker: marker,
                    timestamp: timestamp
                )
            }
        }

        pruneStaleOverlayMarkers(timestamp: timestamp)

        var markersById = Dictionary(uniqueKeysWithValues: markers.map { ($0.markerId, $0) })
        for (markerId, sample) in lastValidOverlayMarkersByMarkerId
        where markersById[markerId] == nil {
            markersById[markerId] = sample.marker
        }

        return markersById.keys.sorted().compactMap { markersById[$0] }
    }

    private func pruneStaleOverlayMarkers(timestamp: Double) {
        for markerId in Array(lastValidOverlayMarkersByMarkerId.keys) {
            guard let sample = lastValidOverlayMarkersByMarkerId[markerId] else {
                continue
            }

            if timestamp - sample.timestamp > OverlayStabilization.timeout {
                lastValidOverlayMarkersByMarkerId.removeValue(forKey: markerId)
            }
        }
    }

    private func detectArucoMarkers(in frame: CameraFrame) -> ArucoMetrics {
        do {
            let detections = try arUcoDetector.detectMarkers(in: frame)
            let markerIds = detections.map(\.markerId).sorted()

            return ArucoMetrics(
                isOpenCVAvailable: arUcoDetector.isOpenCVAvailable,
                detectedMarkerCount: detections.count,
                detectedMarkerIds: markerIds,
                detections: detections,
                errorMessage: arUcoDetector.lastErrorMessage,
                hasFrameReachedDetector: arUcoDetector.hasReceivedFrame,
                detectionCallCount: arUcoDetector.detectionCallCount,
                frameResolution: makeArucoFrameResolution(),
                pixelFormat: formatPixelFormat(arUcoDetector.lastPixelFormat),
                bytesPerRow: arUcoDetector.lastBytesPerRow,
                dictionaryName: ArUcoDetector.dictionaryName,
                preprocessingDescription: formatArucoPreprocessing(),
                inputChannelCount: arUcoDetector.lastInputChannelCount,
                grayscaleChannelCount: arUcoDetector.lastGrayscaleChannelCount,
                rejectedCandidateCount: arUcoDetector.lastRejectedCandidateCount
            )
        } catch {
            let errorDescription = error.localizedDescription
            let detectorErrorMessage = errorDescription.isEmpty ? arUcoDetector.lastErrorMessage : errorDescription

            return ArucoMetrics(
                isOpenCVAvailable: arUcoDetector.isOpenCVAvailable,
                detectedMarkerCount: arUcoDetector.lastDetectedMarkerCount,
                detectedMarkerIds: [],
                detections: [],
                errorMessage: detectorErrorMessage,
                hasFrameReachedDetector: arUcoDetector.hasReceivedFrame,
                detectionCallCount: arUcoDetector.detectionCallCount,
                frameResolution: makeArucoFrameResolution(),
                pixelFormat: formatPixelFormat(arUcoDetector.lastPixelFormat),
                bytesPerRow: arUcoDetector.lastBytesPerRow,
                dictionaryName: ArUcoDetector.dictionaryName,
                preprocessingDescription: formatArucoPreprocessing(),
                inputChannelCount: arUcoDetector.lastInputChannelCount,
                grayscaleChannelCount: arUcoDetector.lastGrayscaleChannelCount,
                rejectedCandidateCount: arUcoDetector.lastRejectedCandidateCount
            )
        }
    }

    private func arucoMetrics(
        _ metrics: ArucoMetrics,
        replacingDetectionsWith detections: [ArUcoDetectionResult]
    ) -> ArucoMetrics {
        ArucoMetrics(
            isOpenCVAvailable: metrics.isOpenCVAvailable,
            detectedMarkerCount: detections.count,
            detectedMarkerIds: detections.map(\.markerId).sorted(),
            detections: detections,
            errorMessage: metrics.errorMessage,
            hasFrameReachedDetector: metrics.hasFrameReachedDetector,
            detectionCallCount: metrics.detectionCallCount,
            frameResolution: metrics.frameResolution,
            pixelFormat: metrics.pixelFormat,
            bytesPerRow: metrics.bytesPerRow,
            dictionaryName: metrics.dictionaryName,
            preprocessingDescription: metrics.preprocessingDescription,
            inputChannelCount: metrics.inputChannelCount,
            grayscaleChannelCount: metrics.grayscaleChannelCount,
            rejectedCandidateCount: metrics.rejectedCandidateCount
        )
    }

    private func makeOverlayMarkers(
        detections: [ArUcoDetectionResult],
        poseResults: [PoseResult],
        markerProfile: MarkerProfile,
        dualMarkerDefinitions: [DualArucoMarkerDefinition],
        timestamp: Double,
        frameIndex: Int
    ) -> [MarkerOverlayResult] {
        switch markerProfile {
        case .singleArucoV1:
            return detections.compactMap { detection in
                guard detection.corners.count == 4 else {
                    return nil
                }

                return MarkerOverlayResult(
                    markerId: detection.markerId,
                    corners: detection.corners,
                    markerProfile: .singleArucoV1,
                    poseSource: .singleArucoV1
                )
            }
        case .dualArucoV2:
            let detectionsByTagId = bestDetectionsByMarkerId(detections)
            var poseSourcesByPhysicalMarkerId: [Int: MarkerPoseSource] = [:]
            for poseResult in poseResults {
                poseSourcesByPhysicalMarkerId[poseResult.markerId] = poseResult.poseSource
            }

            return dualMarkerDefinitions.compactMap { definition in
                let topDetection = detectionsByTagId[definition.topTagId]
                let bottomDetection = detectionsByTagId[definition.bottomTagId]
                let topRecentSummary = recentDetectionSummary(
                    for: definition.topTagId,
                    currentTimestamp: timestamp,
                    currentFrameIndex: frameIndex
                )
                let bottomRecentSummary = recentDetectionSummary(
                    for: definition.bottomTagId,
                    currentTimestamp: timestamp,
                    currentFrameIndex: frameIndex
                )

                guard topDetection != nil || bottomDetection != nil else {
                    return nil
                }

                let corners: [CGPoint]
                let fallbackPoseSource: MarkerPoseSource
                if let topDetection,
                   let bottomDetection {
                    corners = Self.boundingBoxCorners(for: topDetection.corners + bottomDetection.corners)
                    fallbackPoseSource = .dualTag
                } else if let topDetection {
                    corners = topDetection.corners
                    fallbackPoseSource = .singleFallback(tagId: definition.topTagId, role: .top)
                } else if let bottomDetection {
                    corners = bottomDetection.corners
                    fallbackPoseSource = .singleFallback(tagId: definition.bottomTagId, role: .bottom)
                } else {
                    return nil
                }

                guard corners.count == 4 else {
                    return nil
                }

                return MarkerOverlayResult(
                    markerId: definition.physicalMarkerId,
                    corners: corners,
                    markerProfile: .dualArucoV2,
                    poseSource: poseSourcesByPhysicalMarkerId[definition.physicalMarkerId] ??
                        fallbackPoseSource,
                    topTagRecentlySeen: topRecentSummary.recentlySeen,
                    bottomTagRecentlySeen: bottomRecentSummary.recentlySeen
                )
            }
        }
    }

    private func recordDualMarkerDetectionDiagnostics(
        rawDetections: [ArUcoDetectionResult],
        acceptedDetections: [ArUcoDetectionResult],
        markerProfile: MarkerProfile,
        timestamp: Double,
        frameIndex: Int
    ) {
        guard markerProfile == .dualArucoV2 else {
            return
        }

        let dualTagIds = Set(MarkerConfiguration.dualMarkers.flatMap {
            [$0.topTagId, $0.bottomTagId]
        })
        let rawDetectionsByTagId = bestDetectionsByMarkerId(rawDetections)
        let acceptedDetectionsByTagId = bestDetectionsByMarkerId(acceptedDetections)

        for tagId in dualTagIds {
            let rawDetection = rawDetectionsByTagId[tagId]
            let acceptedDetection = acceptedDetectionsByTagId[tagId]
            let rawDetected = rawDetection != nil
            let acceptedDetected = acceptedDetection != nil

            if rawDetected {
                dualRawDetectionCountsByTagId[tagId, default: 0] += 1
            }

            if acceptedDetected {
                dualAcceptedDetectionCountsByTagId[tagId, default: 0] += 1
            }

            var history = dualRecentDetectionHistoryByTagId[tagId, default: []]
            history.append(DualTagDetectionObservation(
                frameIndex: frameIndex,
                timestamp: timestamp,
                rawDetected: rawDetected,
                acceptedDetected: acceptedDetected,
                areaPixels: rawDetection?.markerAreaPixels ?? acceptedDetection?.markerAreaPixels
            ))
            pruneDualTagDetectionHistory(&history, currentTimestamp: timestamp, currentFrameIndex: frameIndex)
            dualRecentDetectionHistoryByTagId[tagId] = history
        }
    }

    private func pruneDualTagDetectionHistory(
        _ history: inout [DualTagDetectionObservation],
        currentTimestamp: Double,
        currentFrameIndex: Int
    ) {
        history.removeAll { observation in
            let frameExpired = currentFrameIndex - observation.frameIndex >=
                DualMarkerDebugConfiguration.recentDetectionWindowFrameCount
            let timeExpired: Bool
            if currentTimestamp.isFinite, observation.timestamp.isFinite {
                timeExpired = currentTimestamp - observation.timestamp >
                    DualMarkerDebugConfiguration.recentDetectionTimeoutSeconds
            } else {
                timeExpired = true
            }

            return frameExpired && timeExpired
        }
    }

    private func recordDualMarkerPoseDiagnostics(
        poseResults: [PoseResult],
        markerProfile: MarkerProfile,
        dualMarkerDefinitions: [DualArucoMarkerDefinition],
        timestamp: Double,
        frameIndex: Int
    ) {
        guard markerProfile == .dualArucoV2 else {
            return
        }

        let dualTagPoseMarkerIds = Set(
            poseResults.compactMap { poseResult -> Int? in
                guard case .dualTag = poseResult.poseSource else {
                    return nil
                }

                return poseResult.markerId
            }
        )

        for definition in dualMarkerDefinitions {
            var history = dualRecentDualTagPoseHistoryByMarkerId[
                definition.physicalMarkerId,
                default: []
            ]

            if dualTagPoseMarkerIds.contains(definition.physicalMarkerId) {
                history.append(DualMarkerPoseObservation(
                    frameIndex: frameIndex,
                    timestamp: timestamp
                ))
            }

            pruneDualMarkerPoseHistory(
                &history,
                currentTimestamp: timestamp,
                currentFrameIndex: frameIndex
            )

            if history.isEmpty {
                dualRecentDualTagPoseHistoryByMarkerId.removeValue(
                    forKey: definition.physicalMarkerId
                )
            } else {
                dualRecentDualTagPoseHistoryByMarkerId[definition.physicalMarkerId] = history
            }
        }
    }

    private func pruneDualMarkerPoseHistory(
        _ history: inout [DualMarkerPoseObservation],
        currentTimestamp: Double,
        currentFrameIndex: Int
    ) {
        history.removeAll { observation in
            let frameExpired = currentFrameIndex - observation.frameIndex >=
                DualMarkerDebugConfiguration.recentDetectionWindowFrameCount
            let timeExpired: Bool
            if currentTimestamp.isFinite, observation.timestamp.isFinite {
                timeExpired = currentTimestamp - observation.timestamp >
                    DualMarkerDebugConfiguration.recentDetectionTimeoutSeconds
            } else {
                timeExpired = true
            }

            return frameExpired && timeExpired
        }
    }

    private func hasRecentDualTagPose(
        forPhysicalMarkerId markerId: Int,
        currentTimestamp: Double,
        currentFrameIndex: Int
    ) -> Bool {
        let history = dualRecentDualTagPoseHistoryByMarkerId[markerId] ?? []

        return history.contains { observation in
            let frameRecent = currentFrameIndex - observation.frameIndex <
                DualMarkerDebugConfiguration.recentDetectionWindowFrameCount
            let timeRecent = currentTimestamp.isFinite &&
                observation.timestamp.isFinite &&
                currentTimestamp - observation.timestamp <=
                    DualMarkerDebugConfiguration.recentDetectionTimeoutSeconds

            return frameRecent || timeRecent
        }
    }

    private func recentDetectionSummary(
        for tagId: Int,
        currentTimestamp: Double,
        currentFrameIndex: Int
    ) -> DualTagRecentDetectionSummary {
        let history = dualRecentDetectionHistoryByTagId[tagId] ?? []
        let recentFrameHistory = history.filter {
            currentFrameIndex - $0.frameIndex <
                DualMarkerDebugConfiguration.recentDetectionWindowFrameCount
        }
        let rawDetectionCount = recentFrameHistory.filter { $0.rawDetected }.count
        let acceptedDetectionCount = recentFrameHistory.filter { $0.acceptedDetected }.count
        let recentlySeen = history.contains { observation in
            let frameRecent = currentFrameIndex - observation.frameIndex <
                DualMarkerDebugConfiguration.recentDetectionWindowFrameCount
            let timeRecent = currentTimestamp.isFinite &&
                observation.timestamp.isFinite &&
                currentTimestamp - observation.timestamp <=
                    DualMarkerDebugConfiguration.recentDetectionTimeoutSeconds

            return (observation.rawDetected || observation.acceptedDetected) &&
                (frameRecent || timeRecent)
        }

        return DualTagRecentDetectionSummary(
            rawDetectionCount: rawDetectionCount,
            acceptedDetectionCount: acceptedDetectionCount,
            recentlySeen: recentlySeen,
            latestAreaPixels: history.last(where: { $0.areaPixels?.isFinite == true })?.areaPixels
        )
    }

    private func dualMarkerDetectionWarning(
        topArea: Double?,
        bottomArea: Double?
    ) -> String? {
        let topAreaBelowMinimum = (topArea ?? .infinity) <
            DualMarkerDebugConfiguration.minimumMarkerAreaPixels
        let bottomAreaBelowMinimum = (bottomArea ?? .infinity) <
            DualMarkerDebugConfiguration.minimumMarkerAreaPixels

        if bottomAreaBelowMinimum {
            return "Bottom tag instavel: aproxime ou melhore iluminacao"
        }

        if topAreaBelowMinimum {
            return "Aproxime a camera"
        }

        return nil
    }

    private func dominantPoseSource(
        for definition: DualArucoMarkerDefinition,
        dualTagFrameCount: Int,
        topFallbackFrameCount: Int,
        bottomFallbackFrameCount: Int
    ) -> MarkerPoseSource? {
        let dualTag = MarkerPoseSource.dualTag
        let topFallback = MarkerPoseSource.singleFallback(
            tagId: definition.topTagId,
            role: .top
        )
        let bottomFallback = MarkerPoseSource.singleFallback(
            tagId: definition.bottomTagId,
            role: .bottom
        )
        let weightedSources: [(source: MarkerPoseSource, weight: Double)] = [
            (dualTag, Double(dualTagFrameCount) * dualTag.qualityWeight),
            (topFallback, Double(topFallbackFrameCount) * topFallback.qualityWeight),
            (bottomFallback, Double(bottomFallbackFrameCount) * bottomFallback.qualityWeight)
        ]

        guard let dominantSource = weightedSources.max(by: { $0.weight < $1.weight }),
              dominantSource.weight > 0
        else {
            return nil
        }

        return dominantSource.source
    }

    private func dualTagPosePercent(
        dualTagFrameCount: Int,
        topFallbackFrameCount: Int,
        bottomFallbackFrameCount: Int
    ) -> Double {
        let totalCount = dualTagFrameCount + topFallbackFrameCount + bottomFallbackFrameCount
        guard totalCount > 0 else {
            return 0
        }

        return Double(dualTagFrameCount) / Double(totalCount) * 100.0
    }

    private func dualMarkerConsistencyWarning(dualTagFrameCount: Int) -> String? {
        guard markerProfile == .dualArucoV2,
              scanMinimumDualTagFrameCount > 0,
              dualTagFrameCount < scanMinimumDualTagFrameCount
        else {
            return nil
        }

        return "Poucos frames dual-tag: aproxime ou melhore iluminacao"
    }

    private func makeDualMarkerDebugStates(
        rawDetections: [ArUcoDetectionResult],
        acceptedDetections: [ArUcoDetectionResult],
        poseResults: [PoseResult],
        markerProfile: MarkerProfile,
        dualMarkerDefinitions: [DualArucoMarkerDefinition],
        timestamp: Double,
        frameIndex: Int
    ) -> [DualArucoMarkerDebugState] {
        guard markerProfile == .dualArucoV2 else {
            return []
        }

        let rawDetectionsByTagId = bestDetectionsByMarkerId(rawDetections)
        let acceptedDetectionsByTagId = bestDetectionsByMarkerId(acceptedDetections)
        let rawDetectedTagIds = Set(rawDetectionsByTagId.keys)
        let acceptedDetectedTagIds = Set(acceptedDetectionsByTagId.keys)
        var posesByPhysicalMarkerId: [Int: PoseResult] = [:]
        for poseResult in poseResults {
            posesByPhysicalMarkerId[poseResult.markerId] = poseResult
        }

        return dualMarkerDefinitions.map { definition in
            let poseResult = posesByPhysicalMarkerId[definition.physicalMarkerId]
            let topRawArea = rawDetectionsByTagId[definition.topTagId]?.markerAreaPixels
            let bottomRawArea = rawDetectionsByTagId[definition.bottomTagId]?.markerAreaPixels
            let topRecentSummary = recentDetectionSummary(
                for: definition.topTagId,
                currentTimestamp: timestamp,
                currentFrameIndex: frameIndex
            )
            let bottomRecentSummary = recentDetectionSummary(
                for: definition.bottomTagId,
                currentTimestamp: timestamp,
                currentFrameIndex: frameIndex
            )
            let topArea = topRawArea ?? topRecentSummary.latestAreaPixels
            let bottomArea = bottomRawArea ?? bottomRecentSummary.latestAreaPixels
            let dualTagFrameCount = scanDualTagFrameCountsByMarkerId[
                definition.physicalMarkerId
            ] ?? 0
            let topFallbackFrameCount = scanTopFallbackFrameCountsByMarkerId[
                definition.physicalMarkerId
            ] ?? 0
            let bottomFallbackFrameCount = scanBottomFallbackFrameCountsByMarkerId[
                definition.physicalMarkerId
            ] ?? 0

            return DualArucoMarkerDebugState(
                physicalMarkerId: definition.physicalMarkerId,
                topTagId: definition.topTagId,
                bottomTagId: definition.bottomTagId,
                topTagRawDetected: rawDetectedTagIds.contains(definition.topTagId),
                bottomTagRawDetected: rawDetectedTagIds.contains(definition.bottomTagId),
                topTagDetected: acceptedDetectedTagIds.contains(definition.topTagId),
                bottomTagDetected: acceptedDetectedTagIds.contains(definition.bottomTagId),
                topTagRecentlySeen: topRecentSummary.recentlySeen,
                bottomTagRecentlySeen: bottomRecentSummary.recentlySeen,
                topDetectionCount: dualRawDetectionCountsByTagId[definition.topTagId] ?? 0,
                bottomDetectionCount: dualRawDetectionCountsByTagId[definition.bottomTagId] ?? 0,
                topAcceptedDetectionCount: dualAcceptedDetectionCountsByTagId[definition.topTagId] ?? 0,
                bottomAcceptedDetectionCount: dualAcceptedDetectionCountsByTagId[definition.bottomTagId] ?? 0,
                topRecentDetectionCount: topRecentSummary.rawDetectionCount,
                bottomRecentDetectionCount: bottomRecentSummary.rawDetectionCount,
                topRecentAcceptedDetectionCount: topRecentSummary.acceptedDetectionCount,
                bottomRecentAcceptedDetectionCount: bottomRecentSummary.acceptedDetectionCount,
                topAreaPixels: topArea,
                bottomAreaPixels: bottomArea,
                topAreaBelowMinimum: (topArea ?? .infinity) <
                    DualMarkerDebugConfiguration.minimumMarkerAreaPixels,
                bottomAreaBelowMinimum: (bottomArea ?? .infinity) <
                    DualMarkerDebugConfiguration.minimumMarkerAreaPixels,
                detectionWarning: dualMarkerDetectionWarning(
                    topArea: topArea,
                    bottomArea: bottomArea
                ),
                poseSource: poseResult?.poseSource,
                reprojectionError: poseResult?.reprojectionError,
                usedPointCount: poseResult?.usedPointCount,
                scanDualTagFrameCount: dualTagFrameCount,
                scanTopFallbackFrameCount: topFallbackFrameCount,
                scanBottomFallbackFrameCount: bottomFallbackFrameCount,
                scanDualTagPosePercent: dualTagPosePercent(
                    dualTagFrameCount: dualTagFrameCount,
                    topFallbackFrameCount: topFallbackFrameCount,
                    bottomFallbackFrameCount: bottomFallbackFrameCount
                ),
                scanDominantPoseSource: dominantPoseSource(
                    for: definition,
                    dualTagFrameCount: dualTagFrameCount,
                    topFallbackFrameCount: topFallbackFrameCount,
                    bottomFallbackFrameCount: bottomFallbackFrameCount
                ),
                scanConsistencyWarning: dualMarkerConsistencyWarning(
                    dualTagFrameCount: dualTagFrameCount
                )
            )
        }
    }

    private func bestDetectionsByMarkerId(
        _ detections: [ArUcoDetectionResult]
    ) -> [Int: ArUcoDetectionResult] {
        var bestDetectionsByMarkerId: [Int: ArUcoDetectionResult] = [:]
        var bestAreaByMarkerId: [Int: Double] = [:]

        for detection in detections {
            let area = detection.markerAreaPixels
            if area > (bestAreaByMarkerId[detection.markerId] ?? -Double.infinity) {
                bestAreaByMarkerId[detection.markerId] = area
                bestDetectionsByMarkerId[detection.markerId] = detection
            }
        }

        return bestDetectionsByMarkerId
    }

    private static func boundingBoxCorners(for points: [CGPoint]) -> [CGPoint] {
        guard let firstPoint = points.first else {
            return []
        }

        var minX = firstPoint.x
        var minY = firstPoint.y
        var maxX = firstPoint.x
        var maxY = firstPoint.y

        for point in points.dropFirst() {
            minX = min(minX, point.x)
            minY = min(minY, point.y)
            maxX = max(maxX, point.x)
            maxY = max(maxY, point.y)
        }

        return [
            CGPoint(x: minX, y: minY),
            CGPoint(x: maxX, y: minY),
            CGPoint(x: maxX, y: maxY),
            CGPoint(x: minX, y: maxY)
        ]
    }

    private func estimatePose(
        from detections: [ArUcoDetectionResult],
        in frame: CameraFrame,
        markerSizeMillimeters: Double,
        markerProfile: MarkerProfile,
        dualMarkerDefinitions: [DualArucoMarkerDefinition]
    ) -> PoseMetrics {
        guard !detections.isEmpty else {
            resetPoseFilter()
            return PoseMetrics(
                rawPoseResults: [],
                rawPoseResult: nil,
                stablePoseResult: nil,
                stabilityStatus: "Sem pose",
                errorMessage: nil
            )
        }

        do {
            let poses = try poseEstimator.estimatePoses(
                for: detections,
                in: frame,
                markerSizeMillimeters: markerSizeMillimeters,
                markerProfile: markerProfile,
                dualMarkers: dualMarkerDefinitions
            )
            let sortedPoses = arUcoConsistencyFilter
                .filterPoses(poses)
                .sorted { $0.markerId < $1.markerId }
            guard let pose = sortedPoses.first else {
                resetPoseFilter()
                return PoseMetrics(
                    rawPoseResults: [],
                    rawPoseResult: nil,
                    stablePoseResult: nil,
                    stabilityStatus: "Sem pose",
                    errorMessage: nil
                )
            }

            let filterResult = stabilizePose(pose)

            return PoseMetrics(
                rawPoseResults: sortedPoses,
                rawPoseResult: pose,
                stablePoseResult: filterResult.pose,
                stabilityStatus: filterResult.stabilityStatus,
                errorMessage: nil
            )
        } catch {
            resetPoseFilter()
            return PoseMetrics(
                rawPoseResults: [],
                rawPoseResult: nil,
                stablePoseResult: nil,
                stabilityStatus: "Instavel",
                errorMessage: error.localizedDescription
            )
        }
    }

    private func estimateImplantPoses(from rawPoseResults: [PoseResult]) -> ImplantMetrics {
        return ImplantMetrics(
            implantPoseResults: rawPoseResults.map { rawPoseResult in
                MarkerToImplantTransform.applyOffset(
                    tagPose: rawPoseResult,
                    offset: ImplantConfiguration.transform
                )
            }
        )
    }

    private func makeFinalPoseObservations(
        from detections: [ArUcoDetectionResult],
        poseResults: [PoseResult],
        in frame: CameraFrame,
        markerSizeMillimeters: Double,
        markerProfile: MarkerProfile,
        dualMarkerDefinitions: [DualArucoMarkerDefinition]
    ) -> [FinalPoseObservation] {
        guard let cameraMatrix = frame.metadata.intrinsicMatrix else {
            return []
        }

        var detectionsByMarkerId: [Int: ArUcoDetectionResult] = [:]
        for detection in detections {
            detectionsByMarkerId[detection.markerId] = detection
        }

        switch markerProfile {
        case .singleArucoV1:
            guard markerSizeMillimeters.isFinite,
                  markerSizeMillimeters > 0
            else {
                return []
            }

            let objectPoints = FinalPoseObservation.markerObjectPoints(
                markerSizeMillimeters: markerSizeMillimeters
            )

            return poseResults.compactMap { poseResult in
                guard poseResult.reprojectionError.isFinite,
                      poseResult.reprojectionError <= ScanConfiguration.maximumAverageReprojectionError,
                      let detection = detectionsByMarkerId[poseResult.markerId],
                      detection.corners.count == objectPoints.count
                else {
                    return nil
                }

                return FinalPoseObservation(
                    markerId: poseResult.markerId,
                    poseSource: poseResult.poseSource,
                    objectPoints: objectPoints,
                    imagePoints: detection.corners,
                    cameraMatrix: cameraMatrix,
                    reprojectionError: poseResult.reprojectionError,
                    markerAreaPixels: poseResult.markerAreaPixels
                )
            }
        case .dualArucoV2:
            let definitionsByPhysicalMarkerId = Dictionary(
                uniqueKeysWithValues: dualMarkerDefinitions.map {
                    ($0.physicalMarkerId, $0)
                }
            )

            return poseResults.compactMap { poseResult in
                guard poseResult.reprojectionError.isFinite,
                      poseResult.reprojectionError <= ScanConfiguration.maximumAverageReprojectionError,
                      let definition = definitionsByPhysicalMarkerId[poseResult.markerId],
                      let observationPoints = dualMarkerObservationPoints(
                        for: poseResult,
                        definition: definition,
                        detectionsByTagId: detectionsByMarkerId
                      ),
                      observationPoints.imagePoints.count == observationPoints.objectPoints.count
                else {
                    return nil
                }

                return FinalPoseObservation(
                    markerId: poseResult.markerId,
                    poseSource: poseResult.poseSource,
                    objectPoints: observationPoints.objectPoints,
                    imagePoints: observationPoints.imagePoints,
                    cameraMatrix: cameraMatrix,
                    reprojectionError: poseResult.reprojectionError,
                    markerAreaPixels: poseResult.markerAreaPixels
                )
            }
        }
    }

    private func dualMarkerObservationPoints(
        for poseResult: PoseResult,
        definition: DualArucoMarkerDefinition,
        detectionsByTagId: [Int: ArUcoDetectionResult]
    ) -> (objectPoints: [SIMD3<Double>], imagePoints: [CGPoint])? {
        switch poseResult.poseSource {
        case .dualTag:
            guard let topDetection = detectionsByTagId[definition.topTagId],
                  let bottomDetection = detectionsByTagId[definition.bottomTagId]
            else {
                return nil
            }

            return (
                objectPoints: definition.dualObjectPoints,
                imagePoints: topDetection.corners + bottomDetection.corners
            )
        case let .singleFallback(_, role):
            let tagId = definition.tagId(for: role)
            guard let detection = detectionsByTagId[tagId] else {
                return nil
            }

            return (
                objectPoints: definition.objectPoints(for: role),
                imagePoints: detection.corners
            )
        case .singleArucoV1:
            return nil
        }
    }

    private func selectedTagDistance(in rawPoseResults: [PoseResult]) -> Double? {
        markerDistance(in: rawPoseResults)
    }

    private func markerDistance(in poseResults: [PoseResult]) -> Double? {
        guard selectedImplantMarkerIds.count == 2 else {
            return nil
        }

        var posesByMarkerId: [Int: PoseResult] = [:]
        for poseResult in poseResults {
            posesByMarkerId[poseResult.markerId] = poseResult
        }

        guard let firstPose = posesByMarkerId[selectedImplantMarkerIds[0]],
              let secondPose = posesByMarkerId[selectedImplantMarkerIds[1]]
        else {
            return nil
        }

        return Self.distance(between: firstPose, and: secondPose)
    }

    private static func distance(between firstPose: PoseResult, and secondPose: PoseResult) -> Double {
        distance(between: firstPose.translationVector, and: secondPose.translationVector)
    }

    private static func distance(
        between firstPosition: SIMD3<Double>,
        and secondPosition: SIMD3<Double>
    ) -> Double {
        simd_length(firstPosition - secondPosition)
    }

    private func recordPrecisionValidationSample(from poseResults: [PoseResult]) {
        guard let expectedDistanceMm = precisionValidationExpectedDistanceMm,
              let measuredDistanceMm = markerDistance(in: poseResults)
        else {
            updatePrecisionValidationCurrentError()
            return
        }

        let errorMm = abs(measuredDistanceMm - expectedDistanceMm)
        guard errorMm.isFinite else {
            updatePrecisionValidationCurrentError()
            return
        }

        precisionValidationErrorHistory.append(errorMm)

        if precisionValidationErrorHistory.count > ScanConfiguration.precisionErrorHistoryLimit {
            precisionValidationErrorHistory.removeFirst(
                precisionValidationErrorHistory.count - ScanConfiguration.precisionErrorHistoryLimit
            )
        }

        precisionValidationCurrentErrorMm = errorMm
        precisionValidationAverageErrorMm = average(precisionValidationErrorHistory)
        precisionValidationSampleCount = precisionValidationErrorHistory.count
    }

    private func updatePrecisionValidationCurrentError() {
        guard let expectedDistanceMm = precisionValidationExpectedDistanceMm,
              let measuredDistanceMm = selectedTagDistanceMm
        else {
            precisionValidationCurrentErrorMm = nil
            return
        }

        let errorMm = abs(measuredDistanceMm - expectedDistanceMm)
        precisionValidationCurrentErrorMm = errorMm.isFinite ? errorMm : nil
    }

    private func resetPrecisionValidationHistory() {
        precisionValidationErrorHistory = []
        precisionValidationAverageErrorMm = nil
        precisionValidationSampleCount = 0
    }

    private func consolidatedPoseResults() -> [PoseResult] {
        fusedPoseResults.isEmpty ? rawPoseResults : fusedPoseResults
    }

    private func updateExportDiagnostics() {
        let exportablePoseCount = tagPosesForSTLExport().count
        currentExportableTagPoseCount = exportablePoseCount
        hasSTLExportURL = stlExportURL != nil

        if let stlExportURL {
            hasSTLExportFile = FileManager.default.fileExists(atPath: stlExportURL.path)
        } else {
            hasSTLExportFile = false
        }

        canExportSTL = scanState == .ready &&
            (hasSTLExportURL || exportablePoseCount > 0)
    }

    private func tagPosesForSTLExport() -> [PoseResult] {
        let consolidatedPoses = exportablePoseResults(consolidatedPoseResults())
        if !consolidatedPoses.isEmpty {
            return consolidatedPoses
        }

        let fusedPoses = exportablePoseResults(fusedPoseResults)
        if !fusedPoses.isEmpty {
            return fusedPoses
        }

        return exportablePoseResults(rawPoseResults)
    }

    private func exportablePoseResults(_ poseResults: [PoseResult]) -> [PoseResult] {
        var posesByMarkerId: [Int: PoseResult] = [:]

        for poseResult in poseResults where isExportablePose(poseResult) {
            posesByMarkerId[poseResult.markerId] = poseResult
        }

        return posesByMarkerId.keys
            .sorted()
            .compactMap { posesByMarkerId[$0] }
    }

    private func isExportablePose(_ poseResult: PoseResult) -> Bool {
        guard poseResult.markerProfile == markerProfile else {
            return false
        }

        if markerProfile == .dualArucoV2 {
            let physicalMarkerIds = Set(MarkerConfiguration.dualMarkers.map(\.physicalMarkerId))
            guard physicalMarkerIds.contains(poseResult.markerId) else {
                return false
            }
        }

        return poseResult.markerId >= 0 &&
            poseResult.distanceMm.isFinite &&
            poseResult.reprojectionError.isFinite &&
            poseResult.markerAreaPixels.isFinite &&
            PoseMath.isFinite(poseResult.rotationVector) &&
            PoseMath.isFinite(poseResult.rotationMatrix) &&
            PoseMath.isFinite(poseResult.translationVector)
    }

    private func selectedImplantDistance(in implantPoseResults: [ImplantPose]) -> Double? {
        guard selectedImplantMarkerIds.count == 2 else {
            return nil
        }

        var posesByMarkerId: [Int: ImplantPose] = [:]
        for implantPose in implantPoseResults {
            posesByMarkerId[implantPose.markerId] = implantPose
        }

        guard let firstPose = posesByMarkerId[selectedImplantMarkerIds[0]],
              let secondPose = posesByMarkerId[selectedImplantMarkerIds[1]]
        else {
            return nil
        }

        return ImplantPose.distance(between: firstPose, and: secondPose)
    }

    private func stabilizePose(_ rawPose: PoseResult) -> (pose: PoseResult, stabilityStatus: String) {
        guard let filteredPoseResult else {
            self.filteredPoseResult = rawPose
            poseSmoother.seed(with: rawPose)
            acceptedPoseFrameCount = 1
            consecutivePoseOutlierCount = 0
            return (rawPose, "Instavel")
        }

        guard filteredPoseResult.markerId == rawPose.markerId else {
            self.filteredPoseResult = rawPose
            poseSmoother.seed(with: rawPose)
            acceptedPoseFrameCount = 1
            consecutivePoseOutlierCount = 0
            return (rawPose, "Instavel")
        }

        let distanceDelta = abs(rawPose.distanceMm - filteredPoseResult.distanceMm)
        if distanceDelta > PoseFilterConfiguration.outlierDistanceDeltaMm {
            consecutivePoseOutlierCount += 1
            acceptedPoseFrameCount = 0

            if consecutivePoseOutlierCount >= PoseFilterConfiguration.outlierResetFrameCount {
                self.filteredPoseResult = rawPose
                poseSmoother.seed(with: rawPose)
                acceptedPoseFrameCount = 1
                consecutivePoseOutlierCount = 0
                return (rawPose, "Instavel")
            }

            return (filteredPoseResult, "Instavel")
        }

        consecutivePoseOutlierCount = 0
        acceptedPoseFrameCount += 1

        let smoothedPose = blendPose(previous: filteredPoseResult, current: rawPose)
        self.filteredPoseResult = smoothedPose

        let isStable = acceptedPoseFrameCount >= PoseFilterConfiguration.stableFrameCount &&
            rawPose.reprojectionError <= PoseFilterConfiguration.stableReprojectionError
        return (smoothedPose, isStable ? "Estavel" : "Instavel")
    }

    private func blendPose(previous: PoseResult, current: PoseResult) -> PoseResult {
        poseSmoother.smooth(
            previous: previous,
            current: current,
            alpha: PoseFilterConfiguration.smoothingAlpha
        )
    }

    private func resetPoseFilter() {
        filteredPoseResult = nil
        poseSmoother.reset()
        acceptedPoseFrameCount = 0
        consecutivePoseOutlierCount = 0
    }

    private func makeArucoFrameResolution() -> FrameResolution? {
        guard let width = arUcoDetector.lastFrameWidth,
              let height = arUcoDetector.lastFrameHeight
        else {
            return nil
        }

        return FrameResolution(width: width, height: height)
    }

    private func formatPixelFormat(_ pixelFormat: OSType?) -> String {
        guard let pixelFormat else {
            return "-"
        }

        switch pixelFormat {
        case kCVPixelFormatType_32BGRA:
            return "32BGRA"
        default:
            return "\(pixelFormat)"
        }
    }

    private func formatArucoPreprocessing() -> String {
        guard arUcoDetector.lastConvertedToGrayscale else {
            return "Nao aplicada"
        }

        guard let inputChannelCount = arUcoDetector.lastInputChannelCount,
              let grayscaleChannelCount = arUcoDetector.lastGrayscaleChannelCount
        else {
            return ArUcoDetector.preprocessingDescription
        }

        return "\(ArUcoDetector.preprocessingDescription) (\(inputChannelCount) -> \(grayscaleChannelCount) canais)"
    }

    private func updateEstimatedFPS(with timestamp: Double) -> Double {
        guard timestamp.isFinite else {
            recentFrameTimestamps.removeAll()
            return 0
        }

        recentFrameTimestamps.append(timestamp)

        let oneSecondAgo = timestamp - 1.0
        recentFrameTimestamps.removeAll { $0 < oneSecondAgo }

        guard recentFrameTimestamps.count >= 2,
              let firstTimestamp = recentFrameTimestamps.first,
              let lastTimestamp = recentFrameTimestamps.last
        else {
            return 0
        }

        let elapsed = lastTimestamp - firstTimestamp
        guard elapsed > 0 else {
            return 0
        }

        return Double(recentFrameTimestamps.count - 1) / elapsed
    }

    private func handleCameraError(_ error: Error) {
        cameraState = .failed
        errorMessage = makeErrorMessage(from: error)
    }

    @MainActor
    private func saveCurrentScanIfNeeded() -> URL? {
        didCallSaveCurrentScanIfNeeded = true
        lastSTLExportEventMessage = "saveCurrentScanIfNeeded called"

        if let stlExportURL,
           FileManager.default.fileExists(atPath: stlExportURL.path) {
            lastSTLExportEventMessage = "STL ja existe"
            updateExportDiagnostics()
            return stlExportURL
        }

        guard !isGeneratingSTL else {
            lastSTLExportEventMessage = "Export ja em andamento"
            updateExportDiagnostics()
            return nil
        }

        let currentTagPoses = tagPosesForSTLExport()
        let currentMarkerProfile = markerProfile
        let exportConfiguration = STLExporter.Configuration.referenceMarker(for: currentMarkerProfile)
        let exportSTLExporter = stlExporter.reconfigured(with: exportConfiguration)
        let exportReferenceModelFileName = exportSTLExporter.referenceModelFileName
        let exportMarkerIds = currentTagPoses.map(\.markerId).sorted()

        lastSTLExportTagPoseCount = currentTagPoses.count
        lastSTLReferenceModelFileName = exportReferenceModelFileName
        lastSTLExportMarkerIds = exportMarkerIds
        lastSTLExportMarkerProfile = currentMarkerProfile
        lastSTLExportBottomTagSizeMillimeters = exportSTLExporter.bottomTagSizeMillimeters
        lastSTLExportBottomCenterYMillimeters = exportSTLExporter.bottomTagCenterYMillimeters

        guard !currentTagPoses.isEmpty else {
            stlExportURL = nil
            stlExportedImplantCount = 0
            stlExportErrorMessage = STLExporter.ExportError.emptyTagPoseList.localizedDescription
            lastSTLExportEventMessage = "Export sem poses"
            if scanState == .ready {
                scanReadinessMessage = "Erro ao gerar modelo"
                scanQualityStatus = "Erro ao gerar modelo"
                scanReadinessBlockerSummary = "Erro STL: sem poses exportaveis"
            }
            updateExportDiagnostics()
            return nil
        }

        let scanStorageManager = self.scanStorageManager
        let scanName = ScanStorageManager.automaticScanFileName()
        let exportedTagCount = currentTagPoses.count
        let exportGenerationID = UUID()

        stlExportGenerationID = exportGenerationID
        isGeneratingSTL = true
        didStartSTLExportForCurrentScan = true
        stlExportErrorMessage = nil
        lastSTLExportEventMessage = makeSTLExportEventMessage(
            event: "Export iniciado",
            markerProfile: currentMarkerProfile,
            referenceModelFileName: exportReferenceModelFileName,
            markerIds: exportMarkerIds
        )
        scanReadinessMessage = "Gerando modelo..."
        scanQualityStatus = "Gerando modelo..."
        scanReadinessBlockerSummary = "Pronto: gerando STL"
        updateExportDiagnostics()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result: Result<ScanItem, Error>

            do {
                let stl = try exportSTLExporter.exportReferenceMarkersAsSTL(tagPoses: currentTagPoses)
                guard let stlData = stl.data(using: .utf8) else {
                    throw ScanStorageManager.StorageError.unableToEncodeSTL
                }

                let scan = try scanStorageManager.saveScan(stlData: stlData, name: scanName)
                result = .success(scan)
            } catch {
                result = .failure(error)
            }

            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.stlExportGenerationID == exportGenerationID
                else {
                    return
                }

                defer {
                    self.isGeneratingSTL = false
                    self.updateExportDiagnostics()
                }

                switch result {
                case .success(let scan):
                    self.stlExportURL = scan.fileURL
                    self.stlExportedImplantCount = exportedTagCount
                    self.stlExportErrorMessage = nil
                    self.lastSTLExportEventMessage = self.makeSTLExportEventMessage(
                        event: "Export concluido",
                        markerProfile: currentMarkerProfile,
                        referenceModelFileName: exportReferenceModelFileName,
                        markerIds: exportMarkerIds
                    )
                    if self.scanState == .ready {
                        self.scanReadinessMessage = "Pronto para gerar modelo"
                        self.scanQualityStatus = "Pronto para exportar"
                        self.scanReadinessBlockerSummary = "Pronto: STL gerado"
                    }
                case .failure(let error):
                    self.stlExportURL = nil
                    self.stlExportedImplantCount = 0
                    self.stlExportErrorMessage = error.localizedDescription
                    self.lastSTLExportEventMessage = self.makeSTLExportEventMessage(
                        event: "Export falhou",
                        markerProfile: currentMarkerProfile,
                        referenceModelFileName: exportReferenceModelFileName,
                        markerIds: exportMarkerIds
                    )
                    if self.scanState == .ready {
                        self.scanReadinessMessage = "Erro ao gerar modelo"
                        self.scanQualityStatus = "Erro ao gerar modelo"
                        self.scanReadinessBlockerSummary = "Erro STL: \(error.localizedDescription)"
                    }
                }
            }
        }

        return nil
    }

    private func makeSTLExportEventMessage(
        event: String,
        markerProfile: MarkerProfile,
        referenceModelFileName: String,
        markerIds: [Int]
    ) -> String {
        let markerIdSummary = markerIds.isEmpty
            ? "-"
            : markerIds.map(String.init).joined(separator: ",")

        return "\(event): \(markerProfile.rawValue), \(referenceModelFileName), IDs \(markerIdSummary)"
    }

    private struct ScanReadinessEvaluation {
        let hasCurrentGoodFrame: Bool
        let hasTags: Bool
        let hasCompleteTagCoverage: Bool
        let hasEnoughGoodFrames: Bool
        let hasPerTagGoodFrames: Bool
        let hasMinimumDualTagFrames: Bool
        let hasAcceptableDistance: Bool
        let hasAcceptableReprojectionError: Bool
        let hasStablePosition: Bool
        let hasStableRotation: Bool
        let hasExportableTagPoses: Bool

        var isReadyCandidate: Bool {
            hasTags &&
                hasCompleteTagCoverage &&
                hasEnoughGoodFrames &&
                hasPerTagGoodFrames &&
                hasMinimumDualTagFrames &&
                hasAcceptableReprojectionError &&
                hasExportableTagPoses
        }
    }

    private struct ScanPoseSample {
        let translationVector: SIMD3<Double>
        let rotation: simd_quatd
    }

    private struct FrameMetrics {
        let totalFramesReceived: Int
        let estimatedFPS: Double
        let lastFrameTimestamp: Double
        let frameResolution: FrameResolution
        let isIntrinsicMatrixAvailable: Bool
    }

    private struct ArucoMetrics {
        let isOpenCVAvailable: Bool
        let detectedMarkerCount: Int
        let detectedMarkerIds: [Int]
        let detections: [ArUcoDetectionResult]
        let errorMessage: String?
        let hasFrameReachedDetector: Bool
        let detectionCallCount: Int
        let frameResolution: FrameResolution?
        let pixelFormat: String
        let bytesPerRow: Int?
        let dictionaryName: String
        let preprocessingDescription: String
        let inputChannelCount: Int?
        let grayscaleChannelCount: Int?
        let rejectedCandidateCount: Int?
    }

    private struct PoseMetrics {
        let rawPoseResults: [PoseResult]
        let rawPoseResult: PoseResult?
        let stablePoseResult: PoseResult?
        let stabilityStatus: String
        let errorMessage: String?
    }

    private struct ImplantMetrics {
        let implantPoseResults: [ImplantPose]
    }

    private static func rotationMatrix(fromRodrigues vector: SIMD3<Double>) -> simd_double3x3 {
        let theta = simd_length(vector)
        guard theta.isFinite, theta > 1e-9 else {
            return matrix_identity_double3x3
        }

        let axis = vector / theta
        let cosine = cos(theta)
        let sine = sin(theta)
        let oneMinusCosine = 1.0 - cosine

        return matrixFromRows(
            SIMD3(
                cosine + axis.x * axis.x * oneMinusCosine,
                axis.x * axis.y * oneMinusCosine - axis.z * sine,
                axis.x * axis.z * oneMinusCosine + axis.y * sine
            ),
            SIMD3(
                axis.y * axis.x * oneMinusCosine + axis.z * sine,
                cosine + axis.y * axis.y * oneMinusCosine,
                axis.y * axis.z * oneMinusCosine - axis.x * sine
            ),
            SIMD3(
                axis.z * axis.x * oneMinusCosine - axis.y * sine,
                axis.z * axis.y * oneMinusCosine + axis.x * sine,
                cosine + axis.z * axis.z * oneMinusCosine
            )
        )
    }

    private static func matrixFromRows(
        _ row0: SIMD3<Double>,
        _ row1: SIMD3<Double>,
        _ row2: SIMD3<Double>
    ) -> simd_double3x3 {
        simd_double3x3(columns: (
            SIMD3(row0.x, row1.x, row2.x),
            SIMD3(row0.y, row1.y, row2.y),
            SIMD3(row0.z, row1.z, row2.z)
        ))
    }

    private static func formatImplantOffset(_ offset: MarkerToImplantTransform) -> String {
        String(
            format: "t(%.1f, %.1f, %.1f) mm, r(%.2f, %.2f, %.2f) rad",
            offset.translationMm.x,
            offset.translationMm.y,
            offset.translationMm.z,
            offset.rotationVector.x,
            offset.rotationVector.y,
            offset.rotationVector.z
        )
    }

    private func makeErrorMessage(from error: Error) -> String {
        guard let serviceError = error as? CameraFrameService.ServiceError else {
            return error.localizedDescription
        }

        switch serviceError {
        case .cameraPermissionDenied:
            return "Camera access was denied."
        case .restrictedAuthorization:
            return "Camera access is restricted on this device."
        case .cameraUnavailable:
            return "Back camera is unavailable."
        case .torchUnavailable:
            return "Torch is unavailable on this device."
        case .unableToCreateInput:
            return "Unable to create camera input."
        case .unableToAddInput:
            return "Unable to add camera input to the session."
        case .unableToAddOutput:
            return "Unable to add video output to the session."
        case .deviceConfigurationFailed:
            return "Unable to configure camera device."
        case .sessionNotPrepared:
            return "Camera session is not prepared."
        case .missingPixelBuffer:
            return "Captured frame is missing its pixel buffer."
        }
    }
}
