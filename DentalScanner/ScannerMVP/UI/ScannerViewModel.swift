import AVFoundation
import Combine
import CoreVideo
import Foundation
import simd

final class ScannerViewModel: ObservableObject {
    private enum OverlayStabilization {
        static let timeout: Double = 0.2
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
        static let smoothingAlpha: Double = 0.35
        static let outlierDistanceDeltaMm: Double = 80.0
        static let outlierResetFrameCount: Int = 3
        static let stableFrameCount: Int = 3
        static let stableReprojectionError: Double = 2.0
    }

    private enum ScanConfiguration {
        static let defaultTargetValidFrameCount: Int = 45
        static let minimumTargetValidFrameCount: Int = 10
        static let maximumTargetValidFrameCount: Int = 120
        static let poseStabilityWindowCount: Int = 12
        static let targetAverageReprojectionError: Double = 1.2
        static let maximumAverageReprojectionError: Double = 2.0
        static let maximumReadyAverageReprojectionError: Double = 1.5
        static let targetPoseJitterMm: Double = 2.0
        static let maximumPoseJitterMm: Double = 8.0
        static let maximumReadyPoseJitterMm: Double = 4.0
        static let azimuthBinCount: Int = 8
        static let elevationBinCount: Int = 2
        static let defaultRequiredAngularCoveragePercent: Double = 50.0
        static let minimumRequiredAngularCoveragePercent: Double = 25.0
        static let maximumRequiredAngularCoveragePercent: Double = 100.0
        static let angularCoverageStepPercent: Double = 5.0
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
        let progress: Double
        let coveredBinCount: Int
        let requiredBinCount: Int
        let observedFrameCount: Int
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
    @Published private(set) var overlayMarkers: [ArUcoDetectionResult] = []
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
    @Published private(set) var poseMarkerSizeMillimeters: Double = PoseConfiguration.defaultMarkerSizeMillimeters
    @Published private(set) var implantPoseResults: [ImplantPose] = []
    @Published private(set) var implantPoseResult: ImplantPose?
    @Published private(set) var implantOffsetDescription: String = ScannerViewModel.formatImplantOffset(
        ImplantConfiguration.transform
    )
    @Published private(set) var selectedImplantMarkerIds: [Int] = []
    @Published private(set) var selectedTagDistanceMm: Double?
    @Published private(set) var selectedImplantDistanceMm: Double?
    @Published private(set) var scanState: ScanState = .idle
    @Published private(set) var scanProgress: Double = 0
    @Published private(set) var scanQualityScore: Double = 0
    @Published private(set) var scanValidFrameCount: Int = 0
    @Published private(set) var scanAverageReprojectionError: Double?
    @Published private(set) var scanPoseJitterMm: Double?
    @Published private(set) var scanQualityStatus: String = "Aguardando inicio"
    @Published private(set) var scanTagCoverages: [Int: ScanTagCoverage] = [:]
    @Published private(set) var scanTargetValidFrameCount: Int = ScanConfiguration.defaultTargetValidFrameCount
    @Published private(set) var scanRequiredAngularCoveragePercent: Double =
        ScanConfiguration.defaultRequiredAngularCoveragePercent
    @Published private(set) var stlExportURL: URL?
    @Published private(set) var stlExportedImplantCount: Int = 0
    @Published private(set) var stlExportErrorMessage: String?
    @Published private(set) var isTorchAvailable: Bool = false
    @Published private(set) var isTorchEnabled: Bool = false
    @Published private(set) var errorMessage: String?

    private let cameraService: CameraFrameService
    private let arUcoDetector: ArUcoDetector
    private let arUcoConsistencyFilter: ArUcoConsistencyFilter
    private let poseEstimator: PoseEstimator
    private let multiFramePoseAccumulator: MultiFramePoseAccumulator
    private let stlExporter: STLExporter
    private var shouldRunCamera = false
    private var totalFramesCounter: Int = 0
    private var recentFrameTimestamps: [Double] = []
    private var lastValidOverlayDetections: [ArUcoDetectionResult] = []
    private var lastValidOverlayTimestamp: Double?
    private var filteredPoseResult: PoseResult?
    private var acceptedPoseFrameCount = 0
    private var consecutivePoseOutlierCount = 0
    private var desiredTorchEnabled = false
    private var scanReprojectionErrors: [Double] = []
    private var scanPoseTranslationHistory: [SIMD3<Double>] = []
    private var scanCoverageBinsByMarkerId: [Int: Set<Int>] = [:]
    private var scanFrameCountsByMarkerId: [Int: Int] = [:]

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
        PoseConfiguration.isMarkerSizeDebugEditingEnabled
    }

    var canExportSTL: Bool {
        scanState == .ready && !implantPoseResults.isEmpty
    }

    var scanTargetValidFrameRange: ClosedRange<Int> {
        ScanConfiguration.minimumTargetValidFrameCount...ScanConfiguration.maximumTargetValidFrameCount
    }

    var scanRequiredAngularCoverageRange: ClosedRange<Double> {
        ScanConfiguration.minimumRequiredAngularCoveragePercent...
            ScanConfiguration.maximumRequiredAngularCoveragePercent
    }

    var scanAngularCoverageStepPercent: Double {
        ScanConfiguration.angularCoverageStepPercent
    }

    init(
        cameraService: CameraFrameService = CameraFrameService(),
        arUcoDetector: ArUcoDetector = ArUcoDetector(),
        arUcoConsistencyFilter: ArUcoConsistencyFilter = ArUcoConsistencyFilter(),
        poseEstimator: PoseEstimator = PoseEstimator(),
        multiFramePoseAccumulator: MultiFramePoseAccumulator = MultiFramePoseAccumulator(),
        stlExporter: STLExporter = STLExporter()
    ) {
        self.cameraService = cameraService
        self.arUcoDetector = arUcoDetector
        self.arUcoConsistencyFilter = arUcoConsistencyFilter
        self.poseEstimator = poseEstimator
        self.multiFramePoseAccumulator = multiFramePoseAccumulator
        self.stlExporter = stlExporter
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
        guard cameraState != .failed else { return }
        cameraState = .ready
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
    func startScan() {
        resetScanSession()
        scanState = .scanning
        scanQualityStatus = "Capturando"
    }

    @MainActor
    func setScanTargetValidFrameCount(_ targetValidFrameCount: Int) {
        scanTargetValidFrameCount = min(
            max(targetValidFrameCount, ScanConfiguration.minimumTargetValidFrameCount),
            ScanConfiguration.maximumTargetValidFrameCount
        )

        if scanState != .idle {
            updateScanProgressAndState(hasImplants: !implantPoseResults.isEmpty)
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
            updateScanProgressAndState(hasImplants: !implantPoseResults.isEmpty)
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
        guard canExportSTL else {
            stlExportURL = nil
            stlExportedImplantCount = 0
            stlExportErrorMessage = "Escaneamento ainda nao esta pronto."
            return nil
        }

        let currentImplantPoses = implantPoseResults
        guard !currentImplantPoses.isEmpty else {
            stlExportURL = nil
            stlExportedImplantCount = 0
            stlExportErrorMessage = STLExporter.ExportError.emptyImplantList.localizedDescription
            return nil
        }

        do {
            let fileURL = makeTemporarySTLFileURL()
            try stlExporter.writeASCIISTL(for: currentImplantPoses, to: fileURL)
            stlExportURL = fileURL
            stlExportedImplantCount = currentImplantPoses.count
            stlExportErrorMessage = nil
            return fileURL
        } catch {
            stlExportURL = nil
            stlExportedImplantCount = 0
            stlExportErrorMessage = error.localizedDescription
            return nil
        }
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
        let overlayMarkers = stabilizedOverlayDetections(
            from: arucoMetrics.detections,
            timestamp: metrics.lastFrameTimestamp
        )
        let markerSizeMillimeters = poseMarkerSizeMillimeters
        let poseMetrics = estimatePose(
            from: arucoMetrics.detections,
            in: frame,
            markerSizeMillimeters: markerSizeMillimeters
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

            if shouldCollectScanFrame && self.scanState.isCollectingFrames {
                self.fusedPoseResults = fusedPoseResults
                self.implantPoseResults = implantMetrics.implantPoseResults
                self.implantPoseResult = implantMetrics.implantPoseResults.first
                self.selectedTagDistanceMm = self.selectedTagDistance(in: consolidatedPoseResults)
                self.selectedImplantDistanceMm = self.selectedImplantDistance(
                    in: implantMetrics.implantPoseResults
                )
                self.recordScanFrame(
                    rawPoseResults: poseMetrics.rawPoseResults,
                    consolidatedPoseResults: consolidatedPoseResults,
                    implantPoseResults: implantMetrics.implantPoseResults
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
        selectedTagDistanceMm = nil
        selectedImplantDistanceMm = nil
        stlExportURL = nil
        stlExportedImplantCount = 0
        stlExportErrorMessage = nil
        scanState = .idle
        scanProgress = 0
        scanQualityScore = 0
        scanValidFrameCount = 0
        scanAverageReprojectionError = nil
        scanPoseJitterMm = nil
        scanQualityStatus = "Aguardando inicio"
        scanTagCoverages = [:]
        scanReprojectionErrors = []
        scanPoseTranslationHistory = []
        scanCoverageBinsByMarkerId = [:]
        scanFrameCountsByMarkerId = [:]
    }

    @MainActor
    private func recordScanFrame(
        rawPoseResults: [PoseResult],
        consolidatedPoseResults: [PoseResult],
        implantPoseResults: [ImplantPose]
    ) {
        guard scanState.isCollectingFrames else {
            return
        }

        guard !rawPoseResults.isEmpty,
              !consolidatedPoseResults.isEmpty,
              !implantPoseResults.isEmpty,
              let frameReprojectionError = averageReprojectionError(in: rawPoseResults)
        else {
            updateScanQualityStatusForMissingPose()
            return
        }

        scanValidFrameCount += 1
        scanReprojectionErrors.append(frameReprojectionError)
        recordAngularCoverage(from: rawPoseResults)

        if let representativePose = consolidatedPoseResults.sorted(by: { $0.markerId < $1.markerId }).first {
            scanPoseTranslationHistory.append(representativePose.translationVector)

            if scanPoseTranslationHistory.count > ScanConfiguration.poseStabilityWindowCount {
                scanPoseTranslationHistory.removeFirst(
                    scanPoseTranslationHistory.count - ScanConfiguration.poseStabilityWindowCount
                )
            }
        }

        scanAverageReprojectionError = average(scanReprojectionErrors)
        scanPoseJitterMm = poseJitterMillimeters()
        updateScanProgressAndState(hasImplants: !implantPoseResults.isEmpty)
    }

    @MainActor
    private func updateScanQualityStatusForMissingPose() {
        if scanValidFrameCount == 0 {
            scanQualityStatus = "Procurando pose"
        } else if scanState == .stabilizing {
            scanQualityStatus = "Estabilizando"
        } else {
            scanQualityStatus = "Capturando"
        }
    }

    @MainActor
    private func updateScanProgressAndState(hasImplants: Bool) {
        let tagCoverageScore = minimumTagCoverageProgress()
        let frameScore = min(
            Double(scanValidFrameCount) / Double(scanTargetValidFrameCount),
            1.0
        )
        let errorScore = qualityScoreForReprojectionError(scanAverageReprojectionError)
        let stabilityScore = qualityScoreForPoseJitter(scanPoseJitterMm)
        let combinedQualityScore = tagCoverageScore * 0.65 +
            frameScore * 0.15 +
            errorScore * 0.10 +
            stabilityScore * 0.10
        let isReady = hasCompleteTagCoverage &&
            (scanAverageReprojectionError ?? .infinity) <= ScanConfiguration.maximumReadyAverageReprojectionError &&
            (scanPoseJitterMm ?? .infinity) <= ScanConfiguration.maximumReadyPoseJitterMm &&
            hasImplants

        scanQualityScore = combinedQualityScore * 100.0

        if isReady {
            scanState = .ready
            scanProgress = 100
            scanQualityStatus = "Pronto para exportar"
            return
        }

        scanState = scanValidFrameCount >= minimumStabilizingFrameCount
            ? .stabilizing
            : .scanning
        scanProgress = min(tagCoverageScore * 100.0, 99)

        if tagCoverageScore < 0.5 {
            scanQualityStatus = "Varie os angulos"
        } else if errorScore < 0.5 {
            scanQualityStatus = "Melhore o enquadramento"
        } else if stabilityScore < 0.5 {
            scanQualityStatus = "Estabilizando"
        } else {
            scanQualityStatus = scanState == .stabilizing ? "Estabilizando" : "Capturando"
        }
    }

    private var minimumStabilizingFrameCount: Int {
        max(3, scanTargetValidFrameCount / 2)
    }

    private var hasCompleteTagCoverage: Bool {
        !scanTagCoverages.isEmpty &&
            scanTagCoverages.values.allSatisfy { $0.progress >= 100.0 }
    }

    private func minimumTagCoverageProgress() -> Double {
        guard !scanTagCoverages.isEmpty else {
            return 0
        }

        let minimumProgress = scanTagCoverages.values
            .map { min(max($0.progress / 100.0, 0.0), 1.0) }
            .min() ?? 0

        return minimumProgress
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
    private func rebuildScanTagCoverages() {
        let requiredBinCount = scanRequiredAngularCoverageBinCount()

        scanTagCoverages = scanCoverageBinsByMarkerId.reduce(into: [:]) { partialResult, item in
            let markerId = item.key
            let coveredBinCount = item.value.count
            let progress = min(Double(coveredBinCount) / Double(requiredBinCount), 1.0) * 100.0

            partialResult[markerId] = ScanTagCoverage(
                markerId: markerId,
                progress: progress,
                coveredBinCount: coveredBinCount,
                requiredBinCount: requiredBinCount,
                observedFrameCount: scanFrameCountsByMarkerId[markerId] ?? 0
            )
        }
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
        let markerRotation = Self.rotationMatrix(fromRodrigues: poseResult.rotationVector)
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

    private func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else {
            return nil
        }

        return values.reduce(0.0, +) / Double(values.count)
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

    private func poseJitterMillimeters() -> Double? {
        guard scanPoseTranslationHistory.count >= 3 else {
            return nil
        }

        let count = Double(scanPoseTranslationHistory.count)
        let meanTranslation = scanPoseTranslationHistory.reduce(SIMD3<Double>.zero) {
            $0 + $1
        } / count
        let totalDistanceFromMean = scanPoseTranslationHistory.reduce(0.0) {
            $0 + simd_distance($1, meanTranslation)
        }

        return totalDistanceFromMean / count
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

    private func stabilizedOverlayDetections(
        from detections: [ArUcoDetectionResult],
        timestamp: Double
    ) -> [ArUcoDetectionResult] {
        guard timestamp.isFinite else {
            return detections
        }

        if !detections.isEmpty {
            lastValidOverlayDetections = detections
            lastValidOverlayTimestamp = timestamp
            return detections
        }

        guard let lastValidOverlayTimestamp else {
            lastValidOverlayDetections = []
            return []
        }

        if timestamp - lastValidOverlayTimestamp <= OverlayStabilization.timeout {
            return lastValidOverlayDetections
        }

        lastValidOverlayDetections = []
        self.lastValidOverlayTimestamp = nil
        return []
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

    private func estimatePose(
        from detections: [ArUcoDetectionResult],
        in frame: CameraFrame,
        markerSizeMillimeters: Double
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
                markerSizeMillimeters: markerSizeMillimeters
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

    private func selectedTagDistance(in rawPoseResults: [PoseResult]) -> Double? {
        guard selectedImplantMarkerIds.count == 2 else {
            return nil
        }

        var posesByMarkerId: [Int: PoseResult] = [:]
        for rawPoseResult in rawPoseResults {
            posesByMarkerId[rawPoseResult.markerId] = rawPoseResult
        }

        guard let firstPose = posesByMarkerId[selectedImplantMarkerIds[0]],
              let secondPose = posesByMarkerId[selectedImplantMarkerIds[1]]
        else {
            return nil
        }

        return simd_distance(firstPose.translationVector, secondPose.translationVector)
    }

    private func consolidatedPoseResults() -> [PoseResult] {
        fusedPoseResults.isEmpty ? rawPoseResults : fusedPoseResults
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
            acceptedPoseFrameCount = 1
            consecutivePoseOutlierCount = 0
            return (rawPose, "Instavel")
        }

        guard filteredPoseResult.markerId == rawPose.markerId else {
            self.filteredPoseResult = rawPose
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
        let alpha = PoseFilterConfiguration.smoothingAlpha
        let retained = 1.0 - alpha

        return PoseResult(
            markerId: current.markerId,
            rotationVector: previous.rotationVector * retained + current.rotationVector * alpha,
            translationVector: previous.translationVector * retained + current.translationVector * alpha,
            distanceMm: previous.distanceMm * retained + current.distanceMm * alpha,
            reprojectionError: previous.reprojectionError * retained + current.reprojectionError * alpha
        )
    }

    private func resetPoseFilter() {
        filteredPoseResult = nil
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

    private func makeTemporarySTLFileURL() -> URL {
        let timestamp = Int(Date().timeIntervalSince1970)
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("dental-implants-\(timestamp).stl")
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
