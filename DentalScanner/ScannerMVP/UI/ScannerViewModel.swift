import AVFoundation
import Combine
import CoreGraphics
import CoreVideo
import Foundation
import simd

final class ScannerViewModel: ObservableObject {
    private enum OverlayStabilization {
        static let timeout: Double = 0.35
        static let dualModeHysteresisSeconds: Double = 0.40
        static let minimumPersistedConfidence: Double = 0.45
    }

    private enum DualMarkerDebugConfiguration {
        static let minimumMarkerAreaPixels: Double = 80.0
        static let recentDetectionWindowFrameCount: Int = 6
        static let recentDetectionTimeoutSeconds: Double = 0.25
        static let bottomRecentDetectionTimeoutSeconds: Double = 0.45
        static let recentDualPoseTimeoutSeconds: Double = 0.25
    }

    private enum ImageEdgeDiagnosticsConfiguration {
        static let minimumPreferredNormalizedMargin: Double = 0.15
        static let frequentEdgeFrameRatio: Double = 0.35
        static let minimumFramesForWarning: Int = 5
    }

    private enum StaticPoseStabilityConfiguration {
        static let windowSeconds: Double = 5.0
        static let unstablePositionStdDevMm: Double = 0.35
        static let unstablePositionPeakToPeakMm: Double = 1.0
        static let unstableRotationStdDevDegrees: Double = 1.5
        static let unstableNormalStdDevDegrees: Double = 1.0
        static let unstableDistancePeakToPeakMm: Double = 1.0
        static let highEdgeFrameRatio: Double = 0.35
        static let highBottomSmallRatio: Double = 0.30
        static let lowDualTagRatio: Double = 0.45
        static let highFallbackRatio: Double = 0.55
        static let minimumBottomTagAreaForHighConfidenceDual: Double = 120.0
    }

    private struct MarkerImagePositionDiagnostics {
        let normalizedX: Double
        let normalizedY: Double
        let edgeMargin: Double
        let nearestEdge: String

        var isNearPreferredEdge: Bool {
            edgeMargin < ImageEdgeDiagnosticsConfiguration.minimumPreferredNormalizedMargin
        }
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
        static let minimumGoodFrameCountRange: ClosedRange<Int> = 30...180
        static let minimumGoodFrameStep: Int = 5
        static let minimumTargetValidFrameCount: Int = 45
        static let maximumTargetValidFrameCount: Int = readiness.targetGoodFrames * 2
        static let targetValidFrameStep: Int = 5
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
        static let minimumRequiredAngularCoveragePercent: Double = 20.0
        static let maximumRequiredAngularCoveragePercent: Double = 100.0
        static let angularCoverageStepPercent: Double = 5.0
        static let precisionErrorHistoryLimit: Int = 30
        static let defaultMinimumDualTagFramesPerMarker: Int = 10
        static let minimumDualTagFramesPerMarkerRange: ClosedRange<Int> = 0...40
        static let defaultMinimumDualAngularCoveragePercent: Double = 25.0
        static let minimumDualAngularCoveragePercentRange: ClosedRange<Double> = 0.0...80.0
        static let defaultMaximumFinalNormalOutlierDegrees: Double = 3.0
        static let maximumFinalNormalOutlierDegreesRange: ClosedRange<Double> = 1.0...10.0
        static let maximumFinalNormalOutlierDegreesStep: Double = 0.5
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

    struct MarkerPairDistance: Equatable, Identifiable {
        let firstMarkerId: Int
        let secondMarkerId: Int
        let distanceMm: Double

        var id: String {
            "\(firstMarkerId)-\(secondMarkerId)"
        }
    }

    struct StaticPoseMarkerDiagnostics: Equatable, Identifiable {
        let markerId: Int
        let sampleCount: Int
        let positionStdDevMm: Double?
        let positionPeakToPeakMm: Double?
        let rotationStdDevDegrees: Double?
        let rotationPeakToPeakDegrees: Double?
        let normalStdDevDegrees: Double?
        let normalPeakToPeakDegrees: Double?
        let reprojectionMean: Double?
        let reprojectionStdDev: Double?
        let dualTagRatio: Double
        let topFallbackRatio: Double
        let bottomFallbackRatio: Double
        let edgeFrameRatio: Double
        let bottomSmallRatio: Double
        let referencePositionDeltaMm: Double?
        let referenceRotationDeltaDegrees: Double?

        var id: Int {
            markerId
        }
    }

    struct StaticPosePairDistanceDiagnostics: Equatable, Identifiable {
        let firstMarkerId: Int
        let secondMarkerId: Int
        let sampleCount: Int
        let meanDistanceMm: Double?
        let standardDeviationMm: Double?
        let minimumDistanceMm: Double?
        let maximumDistanceMm: Double?
        let peakToPeakMm: Double?

        var id: String {
            "\(firstMarkerId)-\(secondMarkerId)"
        }
    }

    struct StaticPosePlaneDiagnostics: Equatable {
        let sampleCount: Int
        let planeAverageErrorMeanMm: Double?
        let planeAverageErrorStdDevMm: Double?
        let planeMaximumErrorMeanMm: Double?
        let planeMaximumErrorWorstMm: Double?
    }

    private struct StaticPoseSample {
        let timestamp: Double
        let markerId: Int
        let poseSource: MarkerPoseSource
        let translationVector: SIMD3<Double>
        let rotationMatrix: simd_double3x3
        let reprojectionError: Double
        let nearImageEdge: Bool
        let bottomSmall: Bool
    }

    private struct StaticPosePairDistanceSample {
        let timestamp: Double
        let firstMarkerId: Int
        let secondMarkerId: Int
        let distanceMm: Double
    }

    private struct StaticPosePlaneSample {
        let timestamp: Double
        let averageErrorMm: Double
        let maximumErrorMm: Double
    }

    private struct StaticPoseReference {
        let markerId: Int
        let translationVector: SIMD3<Double>
        let rotationMatrix: simd_double3x3
    }

    private struct VisualTrackedMarker {
        let markerId: Int
        var marker: MarkerOverlayResult
        var lastSeenTimestamp: Double
        var lastDualSeenTimestamp: Double?
        var lastMode: MarkerPoseSource
        var confidence: Double
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

    private struct PlanarDiagnostics {
        let averageErrorMm: Double
        let maximumErrorMm: Double
        let signedDistancesByMarkerId: [Int: Double]
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
    @Published private(set) var scanMinimumGoodFrameCount: Int =
        ScanConfiguration.readiness.minimumGoodFrames
    @Published private(set) var scanTargetValidFrameCount: Int = ScanConfiguration.defaultTargetValidFrameCount
    @Published private(set) var scanRequiredAngularCoveragePercent: Double =
        ScanConfiguration.defaultRequiredAngularCoveragePercent
    @Published private(set) var scanDualTagReady: Bool = false
    @Published private(set) var scanMinimumDualTagFrameCount: Int =
        ScanConfiguration.defaultMinimumDualTagFramesPerMarker
    @Published private(set) var scanDualAngularCoverageReady: Bool = false
    @Published private(set) var scanRequiredDualAngularCoveragePercent: Double =
        ScanConfiguration.defaultMinimumDualAngularCoveragePercent
    @Published private(set) var precisionModeV2: Bool = true
    @Published private(set) var preferDualTagForFinalExport: Bool = true
    @Published private(set) var scanMaximumFinalNormalOutlierDegrees: Double =
        ScanConfiguration.defaultMaximumFinalNormalOutlierDegrees
    @Published private(set) var scanPlanarAverageErrorMm: Double?
    @Published private(set) var scanPlanarMaximumErrorMm: Double?
    @Published private(set) var scanMarkerPlanarDistancesMm: [Int: Double] = [:]
    @Published private(set) var scanMarkerPairDistances: [MarkerPairDistance] = []
    @Published private(set) var scanFinalConfidenceSummary: String = "-"
    @Published private(set) var scanFinalWorstMarkerSummary: String = "-"
    @Published private(set) var scanFinalMainIssueSummary: String = "-"
    @Published private(set) var currentMotionFrameQuality: MotionFrameQuality = .neutral
    @Published private(set) var scanMotionPenalizedFrameCount: Int = 0
    @Published private(set) var scanMotionDiscardedObservationCount: Int = 0
    @Published private(set) var staticPoseStabilityMode: Bool = false
    @Published private(set) var staticPoseStabilityWindowSeconds: Double =
        StaticPoseStabilityConfiguration.windowSeconds
    @Published private(set) var staticPoseMarkerDiagnostics: [StaticPoseMarkerDiagnostics] = []
    @Published private(set) var staticPosePairDistanceDiagnostics: [StaticPosePairDistanceDiagnostics] = []
    @Published private(set) var staticPosePlaneDiagnostics: StaticPosePlaneDiagnostics?
    @Published private(set) var staticPoseGlobalDiagnosis: String = "Teste estatico desligado"
    @Published private(set) var staticPoseReferenceCaptured: Bool = false
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
    private let motionFrameQualityService: MotionFrameQualityService
    private let poseSmoother = PoseSmoother()
    private let scanReadinessConfiguration = ScanReadinessConfiguration.default
    private let stlExporter: STLExporter
    private let scanStorageManager: ScanStorageManager
    private var shouldRunCamera = false
    private var totalFramesCounter: Int = 0
    private var recentFrameTimestamps: [Double] = []
    private var lastValidOverlayMarkers: [MarkerOverlayResult] = []
    private var lastValidOverlayTimestamp: Double?
    private var visualTrackedMarkersByMarkerId: [Int: VisualTrackedMarker] = [:]
    private var filteredPoseResult: PoseResult?
    private var acceptedPoseFrameCount = 0
    private var consecutivePoseOutlierCount = 0
    private var desiredTorchEnabled = false
    private var scanReprojectionErrors: [Double] = []
    private var scanPoseHistoryByMarkerId: [Int: [ScanPoseSample]] = [:]
    private var scanCoverageBinsByMarkerId: [Int: Set<Int>] = [:]
    private var scanDualCoverageBinsByMarkerId: [Int: Set<Int>] = [:]
    private var scanFrameCountsByMarkerId: [Int: Int] = [:]
    private var scanDualTagFrameCountsByMarkerId: [Int: Int] = [:]
    private var scanTopFallbackFrameCountsByMarkerId: [Int: Int] = [:]
    private var scanBottomFallbackFrameCountsByMarkerId: [Int: Int] = [:]
    private var scanNearImageEdgeFrameCountsByMarkerId: [Int: Int] = [:]
    private var scanNearImageEdgeDualTagFrameCountsByMarkerId: [Int: Int] = [:]
    private var scanNearImageEdgeTopFallbackFrameCountsByMarkerId: [Int: Int] = [:]
    private var scanNearImageEdgeBottomFallbackFrameCountsByMarkerId: [Int: Int] = [:]
    private var scanNearImageEdgeNameCountsByMarkerId: [Int: [String: Int]] = [:]
    private var scanDualTagRejectionReasonCountsByMarkerId: [Int: [String: Int]] = [:]
    private var scanReadinessStableStartTimestamp: Double?
    private var scanCurrentFrameIsGood = false
    private var scanCurrentFrameReadinessBlocker: String?
    private var precisionValidationErrorHistory: [Double] = []
    private var finalPoseObservations: [FinalPoseObservation] = []
    private var finalObservationDiagnosticsByMarkerId: [Int: FinalPoseObservationSelectionDiagnostics] = [:]
    private var staticPoseSamples: [StaticPoseSample] = []
    private var staticPosePairDistanceSamples: [StaticPosePairDistanceSample] = []
    private var staticPosePlaneSamples: [StaticPosePlaneSample] = []
    private var staticPoseReferencesByMarkerId: [Int: StaticPoseReference] = [:]
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

    var scanRequiredDualAngularCoverageRange: ClosedRange<Double> {
        ScanConfiguration.minimumDualAngularCoveragePercentRange
    }

    var scanMaximumFinalNormalOutlierDegreesRange: ClosedRange<Double> {
        ScanConfiguration.maximumFinalNormalOutlierDegreesRange
    }

    var scanMaximumFinalNormalOutlierDegreesStep: Double {
        ScanConfiguration.maximumFinalNormalOutlierDegreesStep
    }

    var dualMarkerRecentDetectionWindowFrameCount: Int {
        DualMarkerDebugConfiguration.recentDetectionWindowFrameCount
    }

    var scanMinimumGoodFrameRange: ClosedRange<Int> {
        ScanConfiguration.minimumGoodFrameCountRange
    }

    var scanMinimumGoodFrameStep: Int {
        ScanConfiguration.minimumGoodFrameStep
    }

    var scanTargetValidFrameStep: Int {
        ScanConfiguration.targetValidFrameStep
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
        motionFrameQualityService: MotionFrameQualityService = MotionFrameQualityService(),
        stlExporter: STLExporter = STLExporter(),
        scanStorageManager: ScanStorageManager = ScanStorageManager()
    ) {
        self.cameraService = cameraService
        self.arUcoDetector = arUcoDetector
        self.arUcoConsistencyFilter = arUcoConsistencyFilter
        self.poseEstimator = poseEstimator
        self.multiFramePoseAccumulator = multiFramePoseAccumulator
        self.finalPoseRefiner = finalPoseRefiner
        self.motionFrameQualityService = motionFrameQualityService
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
        motionFrameQualityService.start()
        await MainActor.run {
            cameraState = .running
        }
    }

    @MainActor
    func stopCamera() {
        shouldRunCamera = false
        cameraService.stopRunning()
        motionFrameQualityService.stop()
        currentMotionFrameQuality = .neutral
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
        precisionModeV2 = markerProfile == .dualArucoV2
        preferDualTagForFinalExport = precisionModeV2
        dualMarkerDebugStates = []
        overlayMarkers = []
        lastValidOverlayMarkers = []
        visualTrackedMarkersByMarkerId = [:]
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
    func setScanMinimumGoodFrameCount(_ minimumGoodFrameCount: Int) {
        scanMinimumGoodFrameCount = min(
            max(
                minimumGoodFrameCount,
                ScanConfiguration.minimumGoodFrameCountRange.lowerBound
            ),
            ScanConfiguration.minimumGoodFrameCountRange.upperBound
        )

        if scanTargetValidFrameCount < scanMinimumGoodFrameCount {
            scanTargetValidFrameCount = scanMinimumGoodFrameCount
        }

        if scanState != .idle {
            updateScanProgressAndState(
                timestamp: lastFrameTimestamp ?? Date().timeIntervalSinceReferenceDate
            )
        }
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

    @MainActor
    func setScanRequiredDualAngularCoveragePercent(_ requiredCoveragePercent: Double) {
        guard requiredCoveragePercent.isFinite else {
            return
        }

        scanRequiredDualAngularCoveragePercent = min(
            max(
                requiredCoveragePercent,
                ScanConfiguration.minimumDualAngularCoveragePercentRange.lowerBound
            ),
            ScanConfiguration.minimumDualAngularCoveragePercentRange.upperBound
        )

        if scanState != .idle {
            updateScanProgressAndState(
                timestamp: lastFrameTimestamp ?? Date().timeIntervalSinceReferenceDate
            )
        }
    }

    @MainActor
    func setScanMaximumFinalNormalOutlierDegrees(_ maximumDegrees: Double) {
        guard maximumDegrees.isFinite else {
            return
        }

        scanMaximumFinalNormalOutlierDegrees = min(
            max(
                maximumDegrees,
                ScanConfiguration.maximumFinalNormalOutlierDegreesRange.lowerBound
            ),
            ScanConfiguration.maximumFinalNormalOutlierDegreesRange.upperBound
        )
        didApplyFinalPoseRefinement = false
        stlExportURL = nil
        stlExportedImplantCount = 0
        stlExportErrorMessage = nil
        finalObservationDiagnosticsByMarkerId = finalPoseRefiner.selectionDiagnostics(
            observations: finalPoseObservations,
            preferDualTagForFinalExport: preferDualTagForFinalExport,
            maximumFinalNormalOutlierDegrees: scanMaximumFinalNormalOutlierDegrees
        )
        updateExportDiagnostics()
    }

    @MainActor
    func setPreferDualTagForFinalExport(_ preferDualTagForFinalExport: Bool) {
        guard self.preferDualTagForFinalExport != preferDualTagForFinalExport else {
            return
        }

        self.preferDualTagForFinalExport = preferDualTagForFinalExport
        didApplyFinalPoseRefinement = false
        stlExportURL = nil
        stlExportedImplantCount = 0
        stlExportErrorMessage = nil
        finalObservationDiagnosticsByMarkerId = finalPoseRefiner.selectionDiagnostics(
            observations: finalPoseObservations,
            preferDualTagForFinalExport: preferDualTagForFinalExport,
            maximumFinalNormalOutlierDegrees: scanMaximumFinalNormalOutlierDegrees
        )
        updateExportDiagnostics()
    }

    @MainActor
    func setStaticPoseStabilityMode(_ staticPoseStabilityMode: Bool) {
        guard self.staticPoseStabilityMode != staticPoseStabilityMode else {
            return
        }

        self.staticPoseStabilityMode = staticPoseStabilityMode
        resetStaticPoseStabilityDiagnostics(clearReference: true)
        if staticPoseStabilityMode {
            scanReadinessMessage = "Teste estatico coletando"
            scanQualityStatus = "Teste estatico coletando"
        }
        updateExportDiagnostics()
    }

    @MainActor
    func captureStaticPoseReference() {
        let references = rawPoseResults.reduce(into: [Int: StaticPoseReference]()) { partialResult, poseResult in
            guard markerProfile == .dualArucoV2,
                  PoseMath.isFinite(poseResult.translationVector),
                  PoseMath.isFinite(poseResult.rotationMatrix)
            else {
                return
            }

            partialResult[poseResult.markerId] = StaticPoseReference(
                markerId: poseResult.markerId,
                translationVector: poseResult.translationVector,
                rotationMatrix: poseResult.rotationMatrix
            )
        }

        staticPoseReferencesByMarkerId = references
        staticPoseReferenceCaptured = !references.isEmpty
        rebuildStaticPoseStabilityDiagnostics()
    }

    @MainActor
    func setPrecisionModeV2(_ precisionModeV2: Bool) {
        guard self.precisionModeV2 != precisionModeV2 else {
            return
        }

        self.precisionModeV2 = precisionModeV2
        preferDualTagForFinalExport = precisionModeV2
        didApplyFinalPoseRefinement = false
        stlExportURL = nil
        stlExportedImplantCount = 0
        stlExportErrorMessage = nil
        finalObservationDiagnosticsByMarkerId = finalPoseRefiner.selectionDiagnostics(
            observations: finalPoseObservations,
            preferDualTagForFinalExport: precisionModeV2,
            maximumFinalNormalOutlierDegrees: scanMaximumFinalNormalOutlierDegrees
        )
        updateExportDiagnostics()
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
        let motionQuality = motionFrameQualityService.quality(near: metrics.lastFrameTimestamp)
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
        let dualMarkerDebugStates = makeDualMarkerDebugStates(
            rawDetections: rawArucoMetrics.detections,
            acceptedDetections: arucoMetrics.detections,
            poseResults: poseMetrics.rawPoseResults,
            markerProfile: activeMarkerProfile,
            dualMarkerDefinitions: dualMarkerDefinitions,
            frameSizePixels: CGSize(
                width: CGFloat(frame.width),
                height: CGFloat(frame.height)
            ),
            timestamp: metrics.lastFrameTimestamp,
            frameIndex: metrics.totalFramesReceived
        )
        let scanStateForFrame = scanState
        let shouldCollectScanFrame = scanStateForFrame.isCollectingFrames
        let shouldCollectStaticPoseFrame = staticPoseStabilityMode &&
            activeMarkerProfile == .dualArucoV2
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
                dualMarkerDefinitions: dualMarkerDefinitions,
                motionQuality: motionQuality
            )
            : []
        let staticPoseObservations = shouldCollectStaticPoseFrame
            ? makeFinalPoseObservations(
                from: arucoMetrics.detections,
                poseResults: poseMetrics.rawPoseResults,
                in: frame,
                markerSizeMillimeters: markerSizeMillimeters,
                markerProfile: activeMarkerProfile,
                dualMarkerDefinitions: dualMarkerDefinitions,
                motionQuality: motionQuality
            )
            : []

        Task { @MainActor [weak self] in
            guard let self else { return }
            self.totalFramesReceived = metrics.totalFramesReceived
            self.estimatedFPS = metrics.estimatedFPS
            self.lastFrameTimestamp = metrics.lastFrameTimestamp
            self.currentMotionFrameQuality = motionQuality
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
            if shouldCollectStaticPoseFrame {
                self.recordStaticPoseStabilityFrame(
                    poseResults: poseMetrics.rawPoseResults,
                    finalPoseObservations: staticPoseObservations,
                    timestamp: metrics.lastFrameTimestamp
                )
            } else if self.staticPoseStabilityMode {
                self.staticPoseGlobalDiagnosis = "Use dualArucoV2 para o teste estatico"
            }

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
                    dualTagRejectionReasons: poseMetrics.dualTagRejectionReasons,
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
        scanDualAngularCoverageReady = false
        scanPlanarAverageErrorMm = nil
        scanPlanarMaximumErrorMm = nil
        scanMarkerPlanarDistancesMm = [:]
        scanMarkerPairDistances = []
        scanFinalConfidenceSummary = "-"
        scanFinalWorstMarkerSummary = "-"
        scanFinalMainIssueSummary = "-"
        scanMotionPenalizedFrameCount = 0
        scanMotionDiscardedObservationCount = 0
        scanTagCoverages = [:]
        scanReprojectionErrors = []
        scanPoseHistoryByMarkerId = [:]
        scanCoverageBinsByMarkerId = [:]
        scanDualCoverageBinsByMarkerId = [:]
        scanFrameCountsByMarkerId = [:]
        scanDualTagFrameCountsByMarkerId = [:]
        scanTopFallbackFrameCountsByMarkerId = [:]
        scanBottomFallbackFrameCountsByMarkerId = [:]
        scanNearImageEdgeFrameCountsByMarkerId = [:]
        scanNearImageEdgeDualTagFrameCountsByMarkerId = [:]
        scanNearImageEdgeTopFallbackFrameCountsByMarkerId = [:]
        scanNearImageEdgeBottomFallbackFrameCountsByMarkerId = [:]
        scanNearImageEdgeNameCountsByMarkerId = [:]
        scanDualTagRejectionReasonCountsByMarkerId = [:]
        scanReadinessStableStartTimestamp = nil
        scanCurrentFrameIsGood = false
        scanCurrentFrameReadinessBlocker = nil
        resetPrecisionValidationHistory()
        finalPoseObservations = []
        finalObservationDiagnosticsByMarkerId = [:]
        resetStaticPoseStabilityDiagnostics(clearReference: true)
        dualRawDetectionCountsByTagId = [:]
        dualAcceptedDetectionCountsByTagId = [:]
        dualRecentDetectionHistoryByTagId = [:]
        dualRecentDualTagPoseHistoryByMarkerId = [:]
        lastValidOverlayMarkers = []
        visualTrackedMarkersByMarkerId = [:]
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
        dualTagRejectionReasons: [Int: String],
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

        let goodFinalPoseObservations = finalPoseObservations.filter {
            goodMarkerIds.contains($0.markerId)
        }
        if goodFinalPoseObservations.contains(where: {
            ($0.motionQuality?.stabilityScore ?? 1.0) < 0.999
        }) {
            scanMotionPenalizedFrameCount += 1
        }
        scanValidFrameCount += 1
        self.finalPoseObservations.append(contentsOf: goodFinalPoseObservations)
        recordDualArucoV2RejectionReasons(dualTagRejectionReasons)
        finalObservationDiagnosticsByMarkerId = finalPoseRefiner.selectionDiagnostics(
            observations: self.finalPoseObservations,
            preferDualTagForFinalExport: preferDualTagForFinalExport,
            maximumFinalNormalOutlierDegrees: scanMaximumFinalNormalOutlierDegrees
        )
        scanReprojectionErrors.append(goodFrameReprojectionError)
        trimRecentValues(&scanReprojectionErrors, to: scanTargetValidFrameCount)

        recordAngularCoverage(from: goodPoseResults)
        recordDualArucoV2PoseSourceFrames(from: goodPoseResults)
        recordDualArucoV2ImageEdgeFrames(from: goodFinalPoseObservations)

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

        if staticPoseStabilityMode {
            let nextScanState: ScanState = scanValidFrameCount >= minimumStabilizingFrameCount
                ? .stabilizing
                : .scanning
            setScanState(nextScanState)
            scanProgress = min(min(tagCoverageScore, frameScore) * 100.0, 99)
            scanReadinessMessage = "Teste estatico coletando"
            scanQualityStatus = scanReadinessMessage
            scanReadinessBlockerSummary = "Teste estatico: export desativado"
            updateExportDiagnostics()
            return
        }

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
        scanDualAngularCoverageReady = evaluation.hasMinimumDualAngularCoverage
    }

    @MainActor
    private func applyFinalPoseRefinementIfNeeded() {
        guard !didApplyFinalPoseRefinement,
              !finalPoseObservations.isEmpty
        else {
            return
        }

        didApplyFinalPoseRefinement = true

        finalObservationDiagnosticsByMarkerId = finalPoseRefiner.selectionDiagnostics(
            observations: finalPoseObservations,
            preferDualTagForFinalExport: preferDualTagForFinalExport,
            maximumFinalNormalOutlierDegrees: scanMaximumFinalNormalOutlierDegrees
        )
        let currentPoseResults = consolidatedPoseResults()
        let refinedPoseResults = finalPoseRefiner.refine(
            observations: finalPoseObservations,
            currentPoseResults: currentPoseResults,
            preferDualTagForFinalExport: preferDualTagForFinalExport,
            maximumFinalNormalOutlierDegrees: scanMaximumFinalNormalOutlierDegrees
        )
        guard !refinedPoseResults.isEmpty,
              refinedPoseResults != currentPoseResults
        else {
            updateExportDiagnostics()
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
        updateExportDiagnostics()
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
                        Double(scanMinimumGoodFrameCount)
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
        let hasEnoughGoodFrames = scanValidFrameCount >= scanMinimumGoodFrameCount
        let hasPerTagGoodFrames = hasTags && activeTagCoverages.allSatisfy {
            $0.observedFrameCount >= scanMinimumGoodFrameCount
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
        let hasMinimumDualAngularCoverage = hasMinimumDualAngularCoveragePerMarker()

        return ScanReadinessEvaluation(
            hasCurrentGoodFrame: scanCurrentFrameIsGood,
            hasTags: hasTags,
            hasCompleteTagCoverage: hasCompleteTagCoverage,
            hasEnoughGoodFrames: hasEnoughGoodFrames,
            hasPerTagGoodFrames: hasPerTagGoodFrames,
            hasMinimumDualTagFrames: hasMinimumDualTagFrames,
            hasMinimumDualAngularCoverage: hasMinimumDualAngularCoverage,
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

    private func hasMinimumDualAngularCoveragePerMarker() -> Bool {
        guard markerProfile == .dualArucoV2,
              scanRequiredDualAngularCoveragePercent > 0
        else {
            return true
        }

        let physicalMarkerIds = MarkerConfiguration.dualMarkers.map(\.physicalMarkerId)
        guard !physicalMarkerIds.isEmpty else {
            return false
        }

        return physicalMarkerIds.allSatisfy {
            dualAngularCoveragePercent(forPhysicalMarkerId: $0) + 0.0001 >=
                scanRequiredDualAngularCoveragePercent
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

        if !evaluation.hasEnoughGoodFrames || !evaluation.hasPerTagGoodFrames {
            return "Colete mais frames bons"
        }

        if !evaluation.hasAcceptableReprojectionError {
            return "Melhorando precisao..."
        }

        if !evaluation.hasExportableTagPoses {
            return "Preparando poses"
        }

        if !evaluation.hasMinimumDualTagFrames {
            return "Capture melhor as duas tags"
        }

        if !evaluation.hasMinimumDualAngularCoverage {
            return "Aproxime para detectar a tag inferior"
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

        if let imageEdgeFramingWarning = imageEdgeFramingWarning() {
            return imageEdgeFramingWarning
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

        if !evaluation.hasMinimumDualTagFrames {
            return "Aviso: dual-tag"
        }

        if !evaluation.hasMinimumDualAngularCoverage {
            return "Aviso: cobertura dual-tag"
        }

        if !evaluation.hasAcceptableDistance {
            return "Aviso: distancia fora ideal"
        }

        if !evaluation.hasStablePosition || !evaluation.hasStableRotation {
            return "Aviso: jitter alto"
        }

        if imageEdgeFramingWarning() != nil {
            return "Aviso: enquadramento"
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

            if markerProfile == .dualArucoV2,
               case .dualTag = poseResult.poseSource {
                scanDualCoverageBinsByMarkerId[poseResult.markerId, default: []].insert(coverageBin)
            }
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
    private func recordDualArucoV2ImageEdgeFrames(from observations: [FinalPoseObservation]) {
        guard markerProfile == .dualArucoV2 else {
            return
        }

        for observation in observations {
            guard let diagnostics = imagePositionDiagnostics(
                for: observation.imagePoints,
                frameSizePixels: observation.frameSizePixels
            ),
                  diagnostics.isNearPreferredEdge
            else {
                continue
            }

            scanNearImageEdgeFrameCountsByMarkerId[observation.markerId, default: 0] += 1
            scanNearImageEdgeNameCountsByMarkerId[
                observation.markerId,
                default: [:]
            ][diagnostics.nearestEdge, default: 0] += 1

            switch observation.poseSource {
            case .dualTag:
                scanNearImageEdgeDualTagFrameCountsByMarkerId[observation.markerId, default: 0] += 1
            case let .singleFallback(_, role):
                switch role {
                case .top:
                    scanNearImageEdgeTopFallbackFrameCountsByMarkerId[
                        observation.markerId,
                        default: 0
                    ] += 1
                case .bottom:
                    scanNearImageEdgeBottomFallbackFrameCountsByMarkerId[
                        observation.markerId,
                        default: 0
                    ] += 1
                }
            case .singleArucoV1:
                continue
            }
        }
    }

    @MainActor
    private func recordStaticPoseStabilityFrame(
        poseResults: [PoseResult],
        finalPoseObservations: [FinalPoseObservation],
        timestamp: Double
    ) {
        guard staticPoseStabilityMode,
              markerProfile == .dualArucoV2,
              timestamp.isFinite
        else {
            return
        }

        let physicalMarkerIds = Set(MarkerConfiguration.dualMarkers.map(\.physicalMarkerId))
        let observationsByMarkerId = finalPoseObservations.reduce(
            into: [Int: FinalPoseObservation]()
        ) { partialResult, observation in
            partialResult[observation.markerId] = observation
        }
        let validPoseResults = poseResults
            .filter { physicalMarkerIds.contains($0.markerId) }
            .filter {
                PoseMath.isFinite($0.translationVector) &&
                    PoseMath.isFinite($0.rotationMatrix) &&
                    $0.reprojectionError.isFinite
            }
            .sorted { $0.markerId < $1.markerId }

        for poseResult in validPoseResults {
            let observation = observationsByMarkerId[poseResult.markerId]
            let edgeDiagnostics = observation.flatMap {
                imagePositionDiagnostics(
                    for: $0.imagePoints,
                    frameSizePixels: $0.frameSizePixels
                )
            }
            staticPoseSamples.append(
                StaticPoseSample(
                    timestamp: timestamp,
                    markerId: poseResult.markerId,
                    poseSource: poseResult.poseSource,
                    translationVector: poseResult.translationVector,
                    rotationMatrix: poseResult.rotationMatrix,
                    reprojectionError: poseResult.reprojectionError,
                    nearImageEdge: edgeDiagnostics?.isNearPreferredEdge ?? false,
                    bottomSmall: staticPoseBottomSmall(
                        poseSource: poseResult.poseSource,
                        observation: observation
                    )
                )
            )
        }

        recordStaticPosePairDistances(
            from: validPoseResults,
            timestamp: timestamp
        )
        recordStaticPosePlaneSample(
            from: validPoseResults,
            timestamp: timestamp
        )
        trimStaticPoseStabilitySamples(currentTimestamp: timestamp)
        rebuildStaticPoseStabilityDiagnostics()
    }

    private func staticPoseBottomSmall(
        poseSource: MarkerPoseSource,
        observation: FinalPoseObservation?
    ) -> Bool {
        guard case .dualTag = poseSource else {
            return false
        }

        guard let bottomArea = observation?.bottomTagAreaPixels,
              bottomArea.isFinite
        else {
            return true
        }

        return bottomArea < StaticPoseStabilityConfiguration.minimumBottomTagAreaForHighConfidenceDual
    }

    private func recordStaticPosePairDistances(
        from poseResults: [PoseResult],
        timestamp: Double
    ) {
        guard poseResults.count >= 2 else {
            return
        }

        for firstIndex in poseResults.indices.dropLast() {
            for secondIndex in poseResults.indices where secondIndex > firstIndex {
                let firstPose = poseResults[firstIndex]
                let secondPose = poseResults[secondIndex]
                let distance = simd_distance(
                    firstPose.translationVector,
                    secondPose.translationVector
                )
                guard distance.isFinite else {
                    continue
                }

                staticPosePairDistanceSamples.append(
                    StaticPosePairDistanceSample(
                        timestamp: timestamp,
                        firstMarkerId: firstPose.markerId,
                        secondMarkerId: secondPose.markerId,
                        distanceMm: distance
                    )
                )
            }
        }
    }

    private func recordStaticPosePlaneSample(
        from poseResults: [PoseResult],
        timestamp: Double
    ) {
        guard let diagnostics = planarDiagnostics(from: poseResults) else {
            return
        }

        staticPosePlaneSamples.append(
            StaticPosePlaneSample(
                timestamp: timestamp,
                averageErrorMm: diagnostics.averageErrorMm,
                maximumErrorMm: diagnostics.maximumErrorMm
            )
        )
    }

    private func trimStaticPoseStabilitySamples(currentTimestamp: Double) {
        let earliestTimestamp = currentTimestamp - StaticPoseStabilityConfiguration.windowSeconds
        staticPoseSamples.removeAll { $0.timestamp < earliestTimestamp }
        staticPosePairDistanceSamples.removeAll { $0.timestamp < earliestTimestamp }
        staticPosePlaneSamples.removeAll { $0.timestamp < earliestTimestamp }
    }

    private func resetStaticPoseStabilityDiagnostics(clearReference: Bool) {
        staticPoseSamples = []
        staticPosePairDistanceSamples = []
        staticPosePlaneSamples = []
        staticPoseMarkerDiagnostics = []
        staticPosePairDistanceDiagnostics = []
        staticPosePlaneDiagnostics = nil
        staticPoseGlobalDiagnosis = staticPoseStabilityMode
            ? "Aguardando poses estaticas"
            : "Teste estatico desligado"

        if clearReference {
            staticPoseReferencesByMarkerId = [:]
            staticPoseReferenceCaptured = false
        }
    }

    private func rebuildStaticPoseStabilityDiagnostics() {
        let markerDiagnostics = makeStaticPoseMarkerDiagnostics(from: staticPoseSamples)
        let pairDiagnostics = makeStaticPosePairDiagnostics(from: staticPosePairDistanceSamples)

        staticPoseMarkerDiagnostics = markerDiagnostics
        staticPosePairDistanceDiagnostics = pairDiagnostics
        staticPosePlaneDiagnostics = makeStaticPosePlaneDiagnostics(from: staticPosePlaneSamples)
        staticPoseGlobalDiagnosis = makeStaticPoseGlobalDiagnosis(
            markerDiagnostics: markerDiagnostics,
            pairDiagnostics: pairDiagnostics
        )
    }

    private func makeStaticPoseMarkerDiagnostics(
        from samples: [StaticPoseSample]
    ) -> [StaticPoseMarkerDiagnostics] {
        let samplesByMarkerId = Dictionary(grouping: samples, by: \.markerId)
        let markerIds = Set(samplesByMarkerId.keys)
            .union(MarkerConfiguration.dualMarkers.map(\.physicalMarkerId))

        return markerIds.sorted().map { markerId in
            let markerSamples = samplesByMarkerId[markerId] ?? []
            let sampleCount = markerSamples.count
            let reprojectionErrors = markerSamples.map(\.reprojectionError)
            let sourceCounts = staticPoseSourceCounts(in: markerSamples)
            let referenceDelta = staticPoseReferenceDelta(
                markerId: markerId,
                samples: markerSamples
            )

            return StaticPoseMarkerDiagnostics(
                markerId: markerId,
                sampleCount: sampleCount,
                positionStdDevMm: staticPosePositionStdDevMm(in: markerSamples),
                positionPeakToPeakMm: staticPosePositionPeakToPeakMm(in: markerSamples),
                rotationStdDevDegrees: staticPoseRotationStdDevDegrees(in: markerSamples),
                rotationPeakToPeakDegrees: staticPoseRotationPeakToPeakDegrees(in: markerSamples),
                normalStdDevDegrees: staticPoseNormalStdDevDegrees(in: markerSamples),
                normalPeakToPeakDegrees: staticPoseNormalPeakToPeakDegrees(in: markerSamples),
                reprojectionMean: average(reprojectionErrors),
                reprojectionStdDev: standardDeviation(reprojectionErrors),
                dualTagRatio: ratio(sourceCounts.dualTag, sampleCount),
                topFallbackRatio: ratio(sourceCounts.topFallback, sampleCount),
                bottomFallbackRatio: ratio(sourceCounts.bottomFallback, sampleCount),
                edgeFrameRatio: ratio(
                    markerSamples.filter { $0.nearImageEdge }.count,
                    sampleCount
                ),
                bottomSmallRatio: ratio(
                    markerSamples.filter { $0.bottomSmall }.count,
                    sampleCount
                ),
                referencePositionDeltaMm: referenceDelta.positionMm,
                referenceRotationDeltaDegrees: referenceDelta.rotationDegrees
            )
        }
    }

    private func makeStaticPosePairDiagnostics(
        from samples: [StaticPosePairDistanceSample]
    ) -> [StaticPosePairDistanceDiagnostics] {
        let samplesByPair = Dictionary(grouping: samples) {
            "\($0.firstMarkerId)-\($0.secondMarkerId)"
        }

        return samplesByPair.values.compactMap { pairSamples -> StaticPosePairDistanceDiagnostics? in
            guard let firstSample = pairSamples.first else {
                return nil
            }

            let distances = pairSamples.map(\.distanceMm).filter { $0.isFinite }
            return StaticPosePairDistanceDiagnostics(
                firstMarkerId: firstSample.firstMarkerId,
                secondMarkerId: firstSample.secondMarkerId,
                sampleCount: distances.count,
                meanDistanceMm: average(distances),
                standardDeviationMm: standardDeviation(distances),
                minimumDistanceMm: distances.min(),
                maximumDistanceMm: distances.max(),
                peakToPeakMm: peakToPeak(distances)
            )
        }
        .sorted {
            if $0.firstMarkerId == $1.firstMarkerId {
                return $0.secondMarkerId < $1.secondMarkerId
            }

            return $0.firstMarkerId < $1.firstMarkerId
        }
    }

    private func makeStaticPosePlaneDiagnostics(
        from samples: [StaticPosePlaneSample]
    ) -> StaticPosePlaneDiagnostics? {
        let averageErrors = samples.map(\.averageErrorMm).filter { $0.isFinite }
        let maximumErrors = samples.map(\.maximumErrorMm).filter { $0.isFinite }
        guard !averageErrors.isEmpty,
              !maximumErrors.isEmpty
        else {
            return nil
        }

        return StaticPosePlaneDiagnostics(
            sampleCount: min(averageErrors.count, maximumErrors.count),
            planeAverageErrorMeanMm: average(averageErrors),
            planeAverageErrorStdDevMm: standardDeviation(averageErrors),
            planeMaximumErrorMeanMm: average(maximumErrors),
            planeMaximumErrorWorstMm: maximumErrors.max()
        )
    }

    private func makeStaticPoseGlobalDiagnosis(
        markerDiagnostics: [StaticPoseMarkerDiagnostics],
        pairDiagnostics: [StaticPosePairDistanceDiagnostics]
    ) -> String {
        let populatedMarkers = markerDiagnostics.filter { $0.sampleCount >= 3 }
        guard !populatedMarkers.isEmpty else {
            return staticPoseStabilityMode
                ? "Aguardando poses estaticas"
                : "Teste estatico desligado"
        }

        let maximumEdgeRatio = populatedMarkers.map(\.edgeFrameRatio).max() ?? 0
        let maximumBottomSmallRatio = populatedMarkers.map(\.bottomSmallRatio).max() ?? 0
        let minimumDualRatio = populatedMarkers.map(\.dualTagRatio).min() ?? 0
        let maximumFallbackRatio = populatedMarkers.map {
            $0.topFallbackRatio + $0.bottomFallbackRatio
        }.max() ?? 0
        let maximumPositionStdDev = populatedMarkers.compactMap(\.positionStdDevMm).max() ?? 0
        let maximumPositionPeakToPeak = populatedMarkers.compactMap(\.positionPeakToPeakMm).max() ?? 0
        let maximumRotationStdDev = populatedMarkers.compactMap(\.rotationStdDevDegrees).max() ?? 0
        let maximumNormalStdDev = populatedMarkers.compactMap(\.normalStdDevDegrees).max() ?? 0
        let maximumPairPeakToPeak = pairDiagnostics.compactMap(\.peakToPeakMm).max() ?? 0

        if maximumEdgeRatio >= StaticPoseStabilityConfiguration.highEdgeFrameRatio {
            return "Instabilidade vem da captura: muitos frames de borda"
        }

        if maximumBottomSmallRatio >= StaticPoseStabilityConfiguration.highBottomSmallRatio ||
            minimumDualRatio < StaticPoseStabilityConfiguration.lowDualTagRatio {
            return "Instabilidade vem da bottom tag: dual % baixo / bottom small alto"
        }

        if maximumFallbackRatio >= StaticPoseStabilityConfiguration.highFallbackRatio {
            return "Instabilidade vem de fallback: fallback domina"
        }

        let markerPoseUnstable = maximumPositionStdDev >=
            StaticPoseStabilityConfiguration.unstablePositionStdDevMm ||
            maximumPositionPeakToPeak >=
                StaticPoseStabilityConfiguration.unstablePositionPeakToPeakMm ||
            maximumRotationStdDev >=
                StaticPoseStabilityConfiguration.unstableRotationStdDevDegrees ||
            maximumNormalStdDev >=
                StaticPoseStabilityConfiguration.unstableNormalStdDevDegrees
        let markerDistancesUnstable = maximumPairPeakToPeak >=
            StaticPoseStabilityConfiguration.unstableDistancePeakToPeakMm

        if markerPoseUnstable && markerDistancesUnstable {
            return "Instabilidade vem da deteccao: pose varia mesmo com camera parada"
        }

        if maximumNormalStdDev >= StaticPoseStabilityConfiguration.unstableNormalStdDevDegrees {
            return "Instabilidade vem da inclinacao: normal varia com camera parada"
        }

        if markerPoseUnstable {
            return "Instabilidade vem do movimento/captura: poses movem mas distancias ficam mais estaveis"
        }

        return "Estavel parado: problema provavel e selecao de frames durante movimento"
    }

    private func staticPoseSourceCounts(
        in samples: [StaticPoseSample]
    ) -> (dualTag: Int, topFallback: Int, bottomFallback: Int) {
        samples.reduce(into: (dualTag: 0, topFallback: 0, bottomFallback: 0)) { partialResult, sample in
            switch sample.poseSource {
            case .dualTag:
                partialResult.dualTag += 1
            case let .singleFallback(_, role):
                switch role {
                case .top:
                    partialResult.topFallback += 1
                case .bottom:
                    partialResult.bottomFallback += 1
                }
            case .singleArucoV1:
                break
            }
        }
    }

    private func staticPoseReferenceDelta(
        markerId: Int,
        samples: [StaticPoseSample]
    ) -> (positionMm: Double?, rotationDegrees: Double?) {
        guard let reference = staticPoseReferencesByMarkerId[markerId],
              let latestSample = samples.last
        else {
            return (nil, nil)
        }

        return (
            positionMm: simd_distance(
                latestSample.translationVector,
                reference.translationVector
            ),
            rotationDegrees: rotationAngularDistanceDegrees(
                latestSample.rotationMatrix,
                reference.rotationMatrix
            )
        )
    }

    private func staticPosePositionStdDevMm(in samples: [StaticPoseSample]) -> Double? {
        guard samples.count >= 2 else {
            return nil
        }

        let mean = samples.reduce(SIMD3<Double>.zero) {
            $0 + $1.translationVector
        } / Double(samples.count)
        let distances = samples.map {
            simd_distance($0.translationVector, mean)
        }

        return standardDeviation(distances)
    }

    private func staticPosePositionPeakToPeakMm(in samples: [StaticPoseSample]) -> Double? {
        guard samples.count >= 2,
              let minX = samples.map(\.translationVector.x).min(),
              let maxX = samples.map(\.translationVector.x).max(),
              let minY = samples.map(\.translationVector.y).min(),
              let maxY = samples.map(\.translationVector.y).max(),
              let minZ = samples.map(\.translationVector.z).min(),
              let maxZ = samples.map(\.translationVector.z).max()
        else {
            return nil
        }

        return simd_length(
            SIMD3(
                maxX - minX,
                maxY - minY,
                maxZ - minZ
            )
        )
    }

    private func staticPoseRotationStdDevDegrees(in samples: [StaticPoseSample]) -> Double? {
        guard samples.count >= 2,
              let latestRotation = samples.last?.rotationMatrix
        else {
            return nil
        }

        let distances = samples.map {
            rotationAngularDistanceDegrees($0.rotationMatrix, latestRotation)
        }

        return standardDeviation(distances)
    }

    private func staticPoseRotationPeakToPeakDegrees(in samples: [StaticPoseSample]) -> Double? {
        guard samples.count >= 2 else {
            return nil
        }

        var maximumDistance = 0.0
        for firstIndex in samples.indices.dropLast() {
            for secondIndex in samples.indices where secondIndex > firstIndex {
                let distance = rotationAngularDistanceDegrees(
                    samples[firstIndex].rotationMatrix,
                    samples[secondIndex].rotationMatrix
                )
                if distance.isFinite {
                    maximumDistance = max(maximumDistance, distance)
                }
            }
        }

        return maximumDistance
    }

    private func staticPoseNormalStdDevDegrees(in samples: [StaticPoseSample]) -> Double? {
        let normals = samples.compactMap { markerNormal(for: $0.rotationMatrix) }
        guard normals.count >= 2,
              let averageNormal = averageNormal(normals)
        else {
            return nil
        }

        let distances = normals.map {
            normalAngularDistanceDegrees($0, averageNormal)
        }

        return standardDeviation(distances)
    }

    private func staticPoseNormalPeakToPeakDegrees(in samples: [StaticPoseSample]) -> Double? {
        let normals = samples.compactMap { markerNormal(for: $0.rotationMatrix) }
        guard normals.count >= 2 else {
            return nil
        }

        var maximumDistance = 0.0
        for firstIndex in normals.indices.dropLast() {
            for secondIndex in normals.indices where secondIndex > firstIndex {
                let distance = normalAngularDistanceDegrees(
                    normals[firstIndex],
                    normals[secondIndex]
                )
                if distance.isFinite {
                    maximumDistance = max(maximumDistance, distance)
                }
            }
        }

        return maximumDistance
    }

    private func ratio(_ count: Int, _ totalCount: Int) -> Double {
        guard totalCount > 0 else {
            return 0
        }

        return Double(count) / Double(totalCount)
    }

    @MainActor
    private func recordDualArucoV2RejectionReasons(_ reasonsByMarkerId: [Int: String]) {
        guard markerProfile == .dualArucoV2 else {
            return
        }

        for (markerId, reason) in reasonsByMarkerId {
            scanDualTagRejectionReasonCountsByMarkerId[
                markerId,
                default: [:]
            ][reason, default: 0] += 1
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

    private func dualAngularCoveragePercent(forPhysicalMarkerId markerId: Int) -> Double {
        guard markerProfile == .dualArucoV2 else {
            return 0
        }

        let coveredBinCount = scanDualCoverageBinsByMarkerId[markerId]?.count ?? 0
        let rawCoverage = Double(coveredBinCount) / Double(totalAngularCoverageBinCount)

        return clampedCoverage(rawCoverage) * 100.0
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
        let finiteValues = values.filter { $0.isFinite }
        guard !finiteValues.isEmpty else {
            return nil
        }

        return finiteValues.reduce(0.0, +) / Double(finiteValues.count)
    }

    private func standardDeviation(_ values: [Double]) -> Double? {
        let finiteValues = values.filter { $0.isFinite }
        guard finiteValues.count >= 2,
              let mean = average(finiteValues)
        else {
            return nil
        }

        let variance = finiteValues.reduce(0.0) {
            let delta = $1 - mean
            return $0 + delta * delta
        } / Double(finiteValues.count)

        return sqrt(variance)
    }

    private func peakToPeak(_ values: [Double]) -> Double? {
        let finiteValues = values.filter { $0.isFinite }
        guard let minimum = finiteValues.min(),
              let maximum = finiteValues.max()
        else {
            return nil
        }

        return maximum - minimum
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

    private func rotationAngularDistanceDegrees(
        _ lhs: simd_double3x3,
        _ rhs: simd_double3x3
    ) -> Double {
        guard PoseMath.isFinite(lhs),
              PoseMath.isFinite(rhs)
        else {
            return .infinity
        }

        let delta = simd_transpose(lhs) * rhs
        let trace = PoseMath.matrixElement(delta, row: 0, column: 0) +
            PoseMath.matrixElement(delta, row: 1, column: 1) +
            PoseMath.matrixElement(delta, row: 2, column: 2)
        let cosineTheta = min(max((trace - 1.0) / 2.0, -1.0), 1.0)
        let radians = acos(cosineTheta)

        guard radians.isFinite else {
            return .infinity
        }

        return radians * 180.0 / Double.pi
    }

    private func markerNormal(for rotationMatrix: simd_double3x3) -> SIMD3<Double>? {
        guard PoseMath.isFinite(rotationMatrix) else {
            return nil
        }

        let normal = rotationMatrix * SIMD3<Double>(0.0, 0.0, 1.0)
        let length = simd_length(normal)
        guard length.isFinite, length > 1e-9 else {
            return nil
        }

        let normalized = normal / length
        return PoseMath.isFinite(normalized) ? normalized : nil
    }

    private func averageNormal(_ normals: [SIMD3<Double>]) -> SIMD3<Double>? {
        guard let firstNormal = normals.first else {
            return nil
        }

        var sum = SIMD3<Double>(repeating: 0.0)
        for normal in normals {
            let alignedNormal = simd_dot(normal, firstNormal) < 0 ? -normal : normal
            sum += alignedNormal
        }

        let length = simd_length(sum)
        guard length.isFinite, length > 1e-9 else {
            return nil
        }

        let normal = sum / length
        return PoseMath.isFinite(normal) ? normal : nil
    }

    private func normalAngularDistanceDegrees(
        _ lhs: SIMD3<Double>,
        _ rhs: SIMD3<Double>
    ) -> Double {
        guard PoseMath.isFinite(lhs), PoseMath.isFinite(rhs) else {
            return .infinity
        }

        let lhsLength = simd_length(lhs)
        let rhsLength = simd_length(rhs)
        guard lhsLength.isFinite, rhsLength.isFinite, lhsLength > 1e-9, rhsLength > 1e-9 else {
            return .infinity
        }

        let cosineTheta = min(max(simd_dot(lhs / lhsLength, rhs / rhsLength), -1.0), 1.0)
        let radians = acos(cosineTheta)
        guard radians.isFinite else {
            return .infinity
        }

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

        updateVisualTrackedMarkers(with: markers, timestamp: timestamp)

        return visualTrackedMarkersByMarkerId.keys.sorted().compactMap { markerId in
            visualTrackedMarkersByMarkerId[markerId]?.marker
        }
    }

    private func updateVisualTrackedMarkers(
        with markers: [MarkerOverlayResult],
        timestamp: Double
    ) {
        let currentMarkerIds = Set(markers.map(\.markerId))

        for marker in markers {
            let previousVisualMarker = visualTrackedMarkersByMarkerId[marker.markerId]
            let source = marker.poseSource ?? previousVisualMarker?.lastMode ?? .dualTag
            let lastDualSeenTimestamp = updatedLastDualSeenTimestamp(
                previous: previousVisualMarker?.lastDualSeenTimestamp,
                source: source,
                timestamp: timestamp
            )
            let visualModeTitle = visualModeTitle(
                source: source,
                bottomRecentlySeen: marker.bottomTagRecentlySeen,
                lastDualSeenTimestamp: lastDualSeenTimestamp,
                timestamp: timestamp,
                isPersisted: false
            )
            let visualMarker = marker.withVisualState(
                modeTitle: visualModeTitle,
                confidence: 1.0,
                isPersistence: false
            )

            visualTrackedMarkersByMarkerId[marker.markerId] = VisualTrackedMarker(
                markerId: marker.markerId,
                marker: visualMarker,
                lastSeenTimestamp: timestamp,
                lastDualSeenTimestamp: lastDualSeenTimestamp,
                lastMode: source,
                confidence: 1.0
            )
        }

        for markerId in Array(visualTrackedMarkersByMarkerId.keys) {
            guard var trackedMarker = visualTrackedMarkersByMarkerId[markerId],
                  !currentMarkerIds.contains(markerId)
            else {
                continue
            }

            let age = timestamp - trackedMarker.lastSeenTimestamp
            guard age.isFinite,
                  age <= OverlayStabilization.timeout
            else {
                visualTrackedMarkersByMarkerId.removeValue(forKey: markerId)
                continue
            }

            let confidence = visualPersistenceConfidence(forAge: age)
            trackedMarker.confidence = confidence
            trackedMarker.marker = trackedMarker.marker.withVisualState(
                modeTitle: visualModeTitle(
                    source: trackedMarker.lastMode,
                    bottomRecentlySeen: trackedMarker.marker.bottomTagRecentlySeen,
                    lastDualSeenTimestamp: trackedMarker.lastDualSeenTimestamp,
                    timestamp: timestamp,
                    isPersisted: true
                ),
                confidence: confidence,
                isPersistence: true
            )
            visualTrackedMarkersByMarkerId[markerId] = trackedMarker
        }
    }

    private func updatedLastDualSeenTimestamp(
        previous: Double?,
        source: MarkerPoseSource,
        timestamp: Double
    ) -> Double? {
        if case .dualTag = source {
            return timestamp
        }

        return previous
    }

    private func visualPersistenceConfidence(forAge age: Double) -> Double {
        guard age.isFinite, OverlayStabilization.timeout > 0 else {
            return OverlayStabilization.minimumPersistedConfidence
        }

        let progress = min(max(age / OverlayStabilization.timeout, 0), 1)
        let confidence = 1.0 - progress * (1.0 - OverlayStabilization.minimumPersistedConfidence)

        return min(max(confidence, OverlayStabilization.minimumPersistedConfidence), 1.0)
    }

    private func visualModeTitle(
        source: MarkerPoseSource,
        bottomRecentlySeen: Bool,
        lastDualSeenTimestamp: Double?,
        timestamp: Double,
        isPersisted: Bool
    ) -> String {
        let dualRecentlySeen: Bool
        if let lastDualSeenTimestamp,
           timestamp.isFinite,
           lastDualSeenTimestamp.isFinite {
            dualRecentlySeen = timestamp - lastDualSeenTimestamp <=
                OverlayStabilization.dualModeHysteresisSeconds
        } else {
            dualRecentlySeen = false
        }

        switch source {
        case .dualTag:
            return isPersisted ? "Dual recente" : "Dual"
        case let .singleFallback(_, role):
            if dualRecentlySeen {
                return "Dual recente"
            }

            switch role {
            case .top:
                return bottomRecentlySeen ? "Top + bottom recente" : "Top"
            case .bottom:
                return "Bottom"
            }
        case .singleArucoV1:
            return "Single"
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
            pruneDualTagDetectionHistory(
                &history,
                tagId: tagId,
                currentTimestamp: timestamp,
                currentFrameIndex: frameIndex
            )
            dualRecentDetectionHistoryByTagId[tagId] = history
        }
    }

    private func pruneDualTagDetectionHistory(
        _ history: inout [DualTagDetectionObservation],
        tagId: Int,
        currentTimestamp: Double,
        currentFrameIndex: Int
    ) {
        history.removeAll { observation in
            let frameExpired = currentFrameIndex - observation.frameIndex >=
                DualMarkerDebugConfiguration.recentDetectionWindowFrameCount
            let timeExpired: Bool
            if currentTimestamp.isFinite, observation.timestamp.isFinite {
                timeExpired = currentTimestamp - observation.timestamp >
                    recentDetectionTimeoutSeconds(forTagId: tagId)
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
                    DualMarkerDebugConfiguration.recentDualPoseTimeoutSeconds
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
                    DualMarkerDebugConfiguration.recentDualPoseTimeoutSeconds

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
                    recentDetectionTimeoutSeconds(forTagId: tagId)

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

    private func recentDetectionTimeoutSeconds(forTagId tagId: Int) -> Double {
        let bottomTagIds = Set(MarkerConfiguration.dualMarkers.map(\.bottomTagId))
        if bottomTagIds.contains(tagId) {
            return DualMarkerDebugConfiguration.bottomRecentDetectionTimeoutSeconds
        }

        return DualMarkerDebugConfiguration.recentDetectionTimeoutSeconds
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

    private func dualMarkerConsistencyWarning(
        markerId: Int,
        dualTagFrameCount: Int
    ) -> String? {
        guard markerProfile == .dualArucoV2,
              scanMinimumDualTagFrameCount > 0,
              dualTagFrameCount < scanMinimumDualTagFrameCount
        else {
            return nil
        }

        if preferDualTagForFinalExport {
            return "Marker \(markerId) com poucos frames dual-tag"
        }

        return "Poucos frames dual-tag: aproxime ou melhore iluminacao"
    }

    private func dominantDualTagRejectionReason(forPhysicalMarkerId markerId: Int) -> String? {
        dominantReason(in: scanDualTagRejectionReasonCountsByMarkerId[markerId] ?? [:])
    }

    private func dualTagRejectedFrameCount(forPhysicalMarkerId markerId: Int) -> Int {
        (scanDualTagRejectionReasonCountsByMarkerId[markerId] ?? [:])
            .reduce(0) { $0 + $1.value }
    }

    private func finalRefinementDiscardReason(
        forPhysicalMarkerId markerId: Int
    ) -> String? {
        dominantDualTagRejectionReason(forPhysicalMarkerId: markerId) ??
            finalObservationDiagnosticsByMarkerId[markerId]?.dominantDiscardReason
    }

    private func visualAge(
        timestamp: Double,
        lastTimestamp: Double?
    ) -> Double? {
        guard let lastTimestamp,
              timestamp.isFinite,
              lastTimestamp.isFinite
        else {
            return nil
        }

        return max(timestamp - lastTimestamp, 0)
    }

    private func finalRefinementConfidence(
        finalDiagnostics: FinalPoseObservationSelectionDiagnostics?,
        dualTagFrameCount: Int,
        dualAngularCoveragePercent: Double
    ) -> FinalPoseMarkerConfidence {
        if scanMinimumDualTagFrameCount > 0,
           dualTagFrameCount < scanMinimumDualTagFrameCount {
            return .low
        }

        if scanRequiredDualAngularCoveragePercent > 0,
           dualAngularCoveragePercent < scanRequiredDualAngularCoveragePercent {
            return .low
        }

        guard let finalDiagnostics = finalDiagnostics else {
            return .low
        }

        return finalDiagnostics.finalConfidence
    }

    private func finalRefinementConfidenceReason(
        finalDiagnostics: FinalPoseObservationSelectionDiagnostics?,
        dualTagFrameCount: Int,
        dualAngularCoveragePercent: Double
    ) -> String? {
        if scanMinimumDualTagFrameCount > 0,
           dualTagFrameCount < scanMinimumDualTagFrameCount {
            return "poucos dual-tag"
        }

        if scanRequiredDualAngularCoveragePercent > 0,
           dualAngularCoveragePercent < scanRequiredDualAngularCoveragePercent {
            return "pouca cobertura dual"
        }

        guard let finalDiagnostics = finalDiagnostics else {
            return "sem observacoes finais"
        }

        return finalDiagnostics.finalConfidenceReason
    }

    private func dominantReason(in counts: [String: Int]) -> String? {
        counts.max {
            if $0.value == $1.value {
                return $0.key > $1.key
            }

            return $0.value < $1.value
        }?.key
    }

    private func makeDualMarkerDebugStates(
        rawDetections: [ArUcoDetectionResult],
        acceptedDetections: [ArUcoDetectionResult],
        poseResults: [PoseResult],
        markerProfile: MarkerProfile,
        dualMarkerDefinitions: [DualArucoMarkerDefinition],
        frameSizePixels: CGSize,
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
            let finalDiagnostics = finalObservationDiagnosticsByMarkerId[
                definition.physicalMarkerId
            ]
            let observationsBeforeOutlierRejection =
                finalDiagnostics?.observationsBeforeOutlierRejectionCount ?? 0
            let finalAverageReprojectionError =
                finalDiagnostics?.finalAverageReprojectionError
            let finalAverageQualityScore =
                finalDiagnostics?.finalAverageQualityScore
            let dualAngularCoverage = dualAngularCoveragePercent(
                forPhysicalMarkerId: definition.physicalMarkerId
            )
            let visualTrackedMarker = visualTrackedMarkersByMarkerId[
                definition.physicalMarkerId
            ]
            let visualLastSeenAge = visualAge(
                timestamp: timestamp,
                lastTimestamp: visualTrackedMarker?.lastSeenTimestamp
            )
            let visualLastDualAge = visualAge(
                timestamp: timestamp,
                lastTimestamp: visualTrackedMarker?.lastDualSeenTimestamp
            )
            let imageDiagnostics = currentImagePositionDiagnostics(
                for: definition,
                acceptedDetectionsByTagId: acceptedDetectionsByTagId,
                rawDetectionsByTagId: rawDetectionsByTagId,
                frameSizePixels: frameSizePixels
            )
            let nearImageEdgeFrameCount = scanNearImageEdgeFrameCountsByMarkerId[
                definition.physicalMarkerId
            ] ?? 0
            let totalFrameCount = scanFrameCountsByMarkerId[
                definition.physicalMarkerId
            ] ?? 0
            let nearImageEdgeFramePercent = totalFrameCount > 0
                ? Double(nearImageEdgeFrameCount) / Double(totalFrameCount) * 100.0
                : 0
            let nearImageEdgeDominantPoseSource = dominantNearImageEdgePoseSource(
                for: definition
            )

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
                normalizedImageX: imageDiagnostics?.normalizedX,
                normalizedImageY: imageDiagnostics?.normalizedY,
                nearImageEdge: imageDiagnostics?.isNearPreferredEdge ?? false,
                nearestImageEdge: imageDiagnostics?.nearestEdge,
                imageEdgeDistancePercent: imageDiagnostics.map { $0.edgeMargin * 100.0 },
                imageEdgeWarning: imageEdgeWarning(
                    markerId: definition.physicalMarkerId,
                    diagnostics: imageDiagnostics
                ),
                visualMarkerActive: visualLastSeenAge.map {
                    $0 <= OverlayStabilization.timeout
                } ?? false,
                visualModeTitle: visualTrackedMarker?.marker.modeTitle,
                visualLastSeenAgeSeconds: visualLastSeenAge,
                visualLastDualSeenAgeSeconds: visualLastDualAge,
                scanDualTagFrameCount: dualTagFrameCount,
                scanTopFallbackFrameCount: topFallbackFrameCount,
                scanBottomFallbackFrameCount: bottomFallbackFrameCount,
                scanNearImageEdgeFrameCount: nearImageEdgeFrameCount,
                scanNearImageEdgeFramePercent: nearImageEdgeFramePercent,
                scanNearImageEdgeDominantPoseSource: nearImageEdgeDominantPoseSource,
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
                    markerId: definition.physicalMarkerId,
                    dualTagFrameCount: dualTagFrameCount
                ),
                scanDualAngularCoveragePercent: dualAngularCoverage,
                scanDualTagRejectedFrameCount: dualTagRejectedFrameCount(
                    forPhysicalMarkerId: definition.physicalMarkerId
                ),
                scanDualTagRejectionReason: dominantDualTagRejectionReason(
                    forPhysicalMarkerId: definition.physicalMarkerId
                ),
                finalPlanarDistanceMm: scanMarkerPlanarDistancesMm[
                    definition.physicalMarkerId
                ],
                finalRefinementCollectedObservationCount: finalDiagnostics?.totalObservationCount ?? 0,
                finalRefinementObservationCountBeforeFilter: observationsBeforeOutlierRejection,
                finalRefinementUsedObservationCount: finalDiagnostics?.selectedObservationCount ?? 0,
                finalRefinementDiscardedObservationCount: finalDiagnostics?.discardedObservationCount ?? 0,
                finalRefinementOutlierRemovedCount: finalDiagnostics?.outlierRemovedCount ?? 0,
                finalRefinementAverageReprojectionError: finalAverageReprojectionError,
                finalRefinementAverageQualityScore: finalAverageQualityScore,
                finalRefinementAverageNormalizedImageX:
                    finalDiagnostics?.averageNormalizedImageX,
                finalRefinementAverageNormalizedImageY:
                    finalDiagnostics?.averageNormalizedImageY,
                finalRefinementAverageImageEdgeMargin:
                    finalDiagnostics?.averageImageEdgeMargin,
                finalRefinementPositionVariationMm:
                    finalDiagnostics?.finalPositionVariationMm,
                finalRefinementRotationVariationDegrees:
                    finalDiagnostics?.finalRotationVariationDegrees,
                finalRefinementAverageNormal:
                    finalDiagnostics?.finalAverageNormal,
                finalRefinementNormalStdDevDegrees:
                    finalDiagnostics?.finalNormalStdDevDegrees,
                finalRefinementNormalPeakToPeakDegrees:
                    finalDiagnostics?.finalNormalPeakToPeakDegrees,
                finalRefinementWorstNormalDifferenceDegrees:
                    finalDiagnostics?.finalWorstNormalDifferenceDegrees,
                finalRefinementDualTagNormalStdDevDegrees:
                    finalDiagnostics?.finalDualTagNormalStdDevDegrees,
                finalRefinementFallbackNormalStdDevDegrees:
                    finalDiagnostics?.finalFallbackNormalStdDevDegrees,
                finalRefinementDualFallbackNormalDifferenceDegrees:
                    finalDiagnostics?.finalDualFallbackNormalDifferenceDegrees,
                finalRefinementAverageMotionStabilityScore:
                    finalDiagnostics?.finalAverageMotionStabilityScore,
                finalRefinementEdgeDiscardedObservationCount:
                    finalDiagnostics?.edgeDiscardedObservationCount ?? 0,
                finalRefinementSmallBottomDiscardedObservationCount:
                    finalDiagnostics?.smallBottomDiscardedObservationCount ?? 0,
                finalRefinementReprojectionDiscardedObservationCount:
                    finalDiagnostics?.reprojectionDiscardedObservationCount ?? 0,
                finalRefinementLowPriorityFallbackDiscardedObservationCount:
                    finalDiagnostics?.lowPriorityFallbackDiscardedObservationCount ?? 0,
                finalRefinementNormalOutlierDiscardedObservationCount:
                    finalDiagnostics?.normalOutlierDiscardedObservationCount ?? 0,
                finalRefinementMotionDiscardedObservationCount:
                    finalDiagnostics?.motionDiscardedObservationCount ?? 0,
                finalRefinementMotionPenalizedObservationCount:
                    finalDiagnostics?.motionPenalizedObservationCount ?? 0,
                finalRefinementDominantPoseSource: finalDiagnostics?.finalDominantPoseSource,
                finalRefinementConfidence: finalRefinementConfidence(
                    finalDiagnostics: finalDiagnostics,
                    dualTagFrameCount: dualTagFrameCount,
                    dualAngularCoveragePercent: dualAngularCoverage
                ),
                finalRefinementConfidenceReason: finalRefinementConfidenceReason(
                    finalDiagnostics: finalDiagnostics,
                    dualTagFrameCount: dualTagFrameCount,
                    dualAngularCoveragePercent: dualAngularCoverage
                ),
                finalRefinementDiscardReason: finalRefinementDiscardReason(
                    forPhysicalMarkerId: definition.physicalMarkerId
                )
            )
        }
    }

    private func currentImagePositionDiagnostics(
        for definition: DualArucoMarkerDefinition,
        acceptedDetectionsByTagId: [Int: ArUcoDetectionResult],
        rawDetectionsByTagId: [Int: ArUcoDetectionResult],
        frameSizePixels: CGSize
    ) -> MarkerImagePositionDiagnostics? {
        let acceptedPoints = [
            acceptedDetectionsByTagId[definition.topTagId]?.corners ?? [],
            acceptedDetectionsByTagId[definition.bottomTagId]?.corners ?? []
        ].flatMap { $0 }
        let rawPoints = [
            rawDetectionsByTagId[definition.topTagId]?.corners ?? [],
            rawDetectionsByTagId[definition.bottomTagId]?.corners ?? []
        ].flatMap { $0 }
        let points = acceptedPoints.isEmpty ? rawPoints : acceptedPoints

        return imagePositionDiagnostics(
            for: points,
            frameSizePixels: frameSizePixels
        )
    }

    private func imagePositionDiagnostics(
        for points: [CGPoint],
        frameSizePixels: CGSize
    ) -> MarkerImagePositionDiagnostics? {
        guard !points.isEmpty,
              frameSizePixels.width.isFinite,
              frameSizePixels.height.isFinite,
              frameSizePixels.width > 0,
              frameSizePixels.height > 0
        else {
            return nil
        }

        let sum = points.reduce(CGPoint.zero) { partialResult, point in
            CGPoint(
                x: partialResult.x + point.x,
                y: partialResult.y + point.y
            )
        }
        let pointCount = CGFloat(points.count)
        let normalizedX = Double(sum.x / pointCount / frameSizePixels.width)
        let normalizedY = Double(sum.y / pointCount / frameSizePixels.height)

        guard normalizedX.isFinite,
              normalizedY.isFinite
        else {
            return nil
        }

        let clampedX = min(max(normalizedX, 0), 1)
        let clampedY = min(max(normalizedY, 0), 1)
        let edgeMargin = [
            clampedX,
            1.0 - clampedX,
            clampedY,
            1.0 - clampedY
        ].min() ?? 0

        return MarkerImagePositionDiagnostics(
            normalizedX: clampedX,
            normalizedY: clampedY,
            edgeMargin: edgeMargin,
            nearestEdge: nearestImageEdgeName(
                normalizedX: clampedX,
                normalizedY: clampedY
            )
        )
    }

    private func nearestImageEdgeName(
        normalizedX: Double,
        normalizedY: Double
    ) -> String {
        let distances = [
            ("esquerda", normalizedX),
            ("direita", 1.0 - normalizedX),
            ("topo", normalizedY),
            ("baixo", 1.0 - normalizedY)
        ]

        return distances.min { $0.1 < $1.1 }?.0 ?? "-"
    }

    private func imageEdgeWarning(
        markerId: Int,
        diagnostics: MarkerImagePositionDiagnostics?
    ) -> String? {
        guard let diagnostics,
              diagnostics.isNearPreferredEdge
        else {
            return nil
        }

        return "Marker \(markerId) perto da borda \(diagnostics.nearestEdge)"
    }

    private func imageEdgeFramingWarning() -> String? {
        guard markerProfile == .dualArucoV2 else {
            return nil
        }

        for markerId in MarkerConfiguration.dualMarkers.map(\.physicalMarkerId).sorted() {
            let totalFrameCount = scanFrameCountsByMarkerId[markerId] ?? 0
            let nearImageEdgeFrameCount = scanNearImageEdgeFrameCountsByMarkerId[markerId] ?? 0
            guard totalFrameCount >= ImageEdgeDiagnosticsConfiguration.minimumFramesForWarning,
                  nearImageEdgeFrameCount > 0
            else {
                continue
            }

            let edgeRatio = Double(nearImageEdgeFrameCount) / Double(totalFrameCount)
            guard edgeRatio >= ImageEdgeDiagnosticsConfiguration.frequentEdgeFrameRatio else {
                continue
            }

            let edgeName = dominantNearImageEdgeName(forPhysicalMarkerId: markerId) ?? "-"
            return "Marker \(markerId) frequentemente perto da borda \(edgeName)"
        }

        return nil
    }

    private func dominantNearImageEdgeName(forPhysicalMarkerId markerId: Int) -> String? {
        dominantReason(in: scanNearImageEdgeNameCountsByMarkerId[markerId] ?? [:])
    }

    private func dominantNearImageEdgePoseSource(
        for definition: DualArucoMarkerDefinition
    ) -> MarkerPoseSource? {
        let candidates: [(source: MarkerPoseSource, count: Int)] = [
            (
                source: .dualTag,
                count: scanNearImageEdgeDualTagFrameCountsByMarkerId[
                    definition.physicalMarkerId
                ] ?? 0
            ),
            (
                source: .singleFallback(tagId: definition.topTagId, role: .top),
                count: scanNearImageEdgeTopFallbackFrameCountsByMarkerId[
                    definition.physicalMarkerId
                ] ?? 0
            ),
            (
                source: .singleFallback(tagId: definition.bottomTagId, role: .bottom),
                count: scanNearImageEdgeBottomFallbackFrameCountsByMarkerId[
                    definition.physicalMarkerId
                ] ?? 0
            )
        ]

        guard let dominantCandidate = candidates.max(by: { $0.count < $1.count }),
              dominantCandidate.count > 0
        else {
            return nil
        }

        return dominantCandidate.source
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
                errorMessage: nil,
                dualTagRejectionReasons: [:]
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
                    errorMessage: nil,
                    dualTagRejectionReasons: poseEstimator.lastDualArucoV2RejectionReasonsByMarkerId
                )
            }

            let filterResult = stabilizePose(pose)

            return PoseMetrics(
                rawPoseResults: sortedPoses,
                rawPoseResult: pose,
                stablePoseResult: filterResult.pose,
                stabilityStatus: filterResult.stabilityStatus,
                errorMessage: nil,
                dualTagRejectionReasons: poseEstimator.lastDualArucoV2RejectionReasonsByMarkerId
            )
        } catch {
            resetPoseFilter()
            return PoseMetrics(
                rawPoseResults: [],
                rawPoseResult: nil,
                stablePoseResult: nil,
                stabilityStatus: "Instavel",
                errorMessage: error.localizedDescription,
                dualTagRejectionReasons: poseEstimator.lastDualArucoV2RejectionReasonsByMarkerId
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
        dualMarkerDefinitions: [DualArucoMarkerDefinition],
        motionQuality: MotionFrameQuality
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
                    frameSizePixels: CGSize(
                        width: CGFloat(frame.width),
                        height: CGFloat(frame.height)
                    ),
                    rotationMatrix: poseResult.rotationMatrix,
                    translationVector: poseResult.translationVector,
                    reprojectionError: poseResult.reprojectionError,
                    markerAreaPixels: poseResult.markerAreaPixels,
                    topTagAreaPixels: detection.markerAreaPixels,
                    bottomTagAreaPixels: nil,
                    distanceMm: poseResult.distanceMm,
                    motionQuality: motionQuality
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
                    frameSizePixels: CGSize(
                        width: CGFloat(frame.width),
                        height: CGFloat(frame.height)
                    ),
                    rotationMatrix: poseResult.rotationMatrix,
                    translationVector: poseResult.translationVector,
                    reprojectionError: poseResult.reprojectionError,
                    markerAreaPixels: poseResult.markerAreaPixels,
                    topTagAreaPixels: observationPoints.topTagAreaPixels,
                    bottomTagAreaPixels: observationPoints.bottomTagAreaPixels,
                    distanceMm: poseResult.distanceMm,
                    motionQuality: motionQuality
                )
            }
        }
    }

    private func dualMarkerObservationPoints(
        for poseResult: PoseResult,
        definition: DualArucoMarkerDefinition,
        detectionsByTagId: [Int: ArUcoDetectionResult]
    ) -> (
        objectPoints: [SIMD3<Double>],
        imagePoints: [CGPoint],
        topTagAreaPixels: Double?,
        bottomTagAreaPixels: Double?
    )? {
        switch poseResult.poseSource {
        case .dualTag:
            guard let topDetection = detectionsByTagId[definition.topTagId],
                  let bottomDetection = detectionsByTagId[definition.bottomTagId]
            else {
                return nil
            }

            return (
                objectPoints: definition.dualObjectPoints,
                imagePoints: topDetection.corners + bottomDetection.corners,
                topTagAreaPixels: topDetection.markerAreaPixels,
                bottomTagAreaPixels: bottomDetection.markerAreaPixels
            )
        case let .singleFallback(_, role):
            let tagId = definition.tagId(for: role)
            guard let detection = detectionsByTagId[tagId] else {
                return nil
            }

            return (
                objectPoints: definition.objectPoints(for: role),
                imagePoints: detection.corners,
                topTagAreaPixels: role == .top ? detection.markerAreaPixels : nil,
                bottomTagAreaPixels: role == .bottom ? detection.markerAreaPixels : nil
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
        let tagPoses = tagPosesForSTLExport()
        currentExportableTagPoseCount = tagPoses.count
        hasSTLExportURL = stlExportURL != nil
        updatePlanarAndDistanceDiagnostics(from: tagPoses)
        updateFinalConfidenceSummary()

        if let stlExportURL {
            hasSTLExportFile = FileManager.default.fileExists(atPath: stlExportURL.path)
        } else {
            hasSTLExportFile = false
        }

        canExportSTL = !staticPoseStabilityMode &&
            scanState == .ready &&
            (hasSTLExportURL || !tagPoses.isEmpty)
    }

    private func updateFinalConfidenceSummary() {
        guard markerProfile == .dualArucoV2,
              !finalObservationDiagnosticsByMarkerId.isEmpty
        else {
            scanFinalConfidenceSummary = "-"
            scanFinalWorstMarkerSummary = "-"
            scanFinalMainIssueSummary = "-"
            scanMotionDiscardedObservationCount = 0
            return
        }

        let diagnostics = finalObservationDiagnosticsByMarkerId.values.sorted {
            $0.markerId < $1.markerId
        }
        scanMotionDiscardedObservationCount = diagnostics.reduce(0) {
            $0 + $1.motionDiscardedObservationCount
        }
        let confidence = diagnostics.reduce(FinalPoseMarkerConfidence.high) { partialResult, item in
            if confidenceRank(item.finalConfidence) > confidenceRank(partialResult) {
                return item.finalConfidence
            }

            return partialResult
        }
        let worstDiagnostics = diagnostics.max {
            let lhsRank = confidenceRank($0.finalConfidence)
            let rhsRank = confidenceRank($1.finalConfidence)
            if lhsRank == rhsRank {
                return finalIssueWeight(for: $0) < finalIssueWeight(for: $1)
            }

            return lhsRank < rhsRank
        }

        scanFinalConfidenceSummary = confidence.rawValue
        scanFinalWorstMarkerSummary = worstDiagnostics.map { "M\($0.markerId)" } ?? "-"
        scanFinalMainIssueSummary = worstDiagnostics.map { finalMainIssue(for: $0) } ?? "-"
    }

    private func confidenceRank(_ confidence: FinalPoseMarkerConfidence) -> Int {
        switch confidence {
        case .high:
            return 0
        case .medium:
            return 1
        case .low:
            return 2
        }
    }

    private func finalIssueWeight(
        for diagnostics: FinalPoseObservationSelectionDiagnostics
    ) -> Int {
        let edgeFrameCount = scanNearImageEdgeFrameCountsByMarkerId[diagnostics.markerId] ?? 0
        return diagnostics.outlierRemovedCount +
            diagnostics.edgeDiscardedObservationCount +
            diagnostics.smallBottomDiscardedObservationCount +
            diagnostics.reprojectionDiscardedObservationCount +
            diagnostics.lowPriorityFallbackDiscardedObservationCount +
            diagnostics.normalOutlierDiscardedObservationCount +
            diagnostics.motionDiscardedObservationCount +
            edgeFrameCount
    }

    private func finalMainIssue(
        for diagnostics: FinalPoseObservationSelectionDiagnostics
    ) -> String {
        let totalFrameCount = scanFrameCountsByMarkerId[diagnostics.markerId] ?? 0
        let edgeFrameCount = scanNearImageEdgeFrameCountsByMarkerId[diagnostics.markerId] ?? 0
        let edgeFrameRatio = totalFrameCount > 0
            ? Double(edgeFrameCount) / Double(totalFrameCount)
            : 0

        if diagnostics.edgeDiscardedObservationCount > 0 ||
            edgeFrameRatio >= ImageEdgeDiagnosticsConfiguration.frequentEdgeFrameRatio ||
            (diagnostics.averageImageEdgeMargin ?? 1.0) <
                ImageEdgeDiagnosticsConfiguration.minimumPreferredNormalizedMargin {
            return "edge"
        }

        if diagnostics.smallBottomDiscardedObservationCount > 0 {
            return "bottom small"
        }

        if diagnostics.reprojectionDiscardedObservationCount > 0 ||
            (diagnostics.finalAverageReprojectionError ?? 0) >
                scanReadinessConfiguration.maximumAverageReprojectionError {
            return "reprojection"
        }

        if diagnostics.outlierRemovedCount > 0 {
            return "outliers"
        }

        if diagnostics.normalOutlierDiscardedObservationCount > 0 ||
            (diagnostics.finalNormalStdDevDegrees ?? 0) > scanMaximumFinalNormalOutlierDegrees {
            return "normal"
        }

        if diagnostics.motionDiscardedObservationCount > 0 ||
            (diagnostics.finalAverageMotionStabilityScore ?? 1.0) < 0.45 {
            return "motion"
        }

        if diagnostics.lowPriorityFallbackDiscardedObservationCount > 0 {
            return "fallback"
        }

        if let dominantSource = diagnostics.finalDominantPoseSource,
           case .singleFallback(_, _) = dominantSource {
            return "fallback"
        }

        return diagnostics.finalConfidenceReason ?? "ok"
    }

    private func updatePlanarAndDistanceDiagnostics(from poseResults: [PoseResult]) {
        let sortedPoseResults = poseResults.sorted { $0.markerId < $1.markerId }
        scanMarkerPairDistances = markerPairDistances(from: sortedPoseResults)

        guard let planarDiagnostics = planarDiagnostics(from: sortedPoseResults) else {
            scanPlanarAverageErrorMm = nil
            scanPlanarMaximumErrorMm = nil
            scanMarkerPlanarDistancesMm = [:]
            return
        }

        scanPlanarAverageErrorMm = planarDiagnostics.averageErrorMm
        scanPlanarMaximumErrorMm = planarDiagnostics.maximumErrorMm
        scanMarkerPlanarDistancesMm = planarDiagnostics.signedDistancesByMarkerId
    }

    private func markerPairDistances(from poseResults: [PoseResult]) -> [MarkerPairDistance] {
        guard poseResults.count >= 2 else {
            return []
        }

        var distances: [MarkerPairDistance] = []
        for firstIndex in poseResults.indices.dropLast() {
            for secondIndex in poseResults.indices where secondIndex > firstIndex {
                let firstPose = poseResults[firstIndex]
                let secondPose = poseResults[secondIndex]
                let distance = simd_distance(
                    firstPose.translationVector,
                    secondPose.translationVector
                )
                guard distance.isFinite else {
                    continue
                }

                distances.append(MarkerPairDistance(
                    firstMarkerId: firstPose.markerId,
                    secondMarkerId: secondPose.markerId,
                    distanceMm: distance
                ))
            }
        }

        return distances
    }

    private func planarDiagnostics(from poseResults: [PoseResult]) -> PlanarDiagnostics? {
        guard poseResults.count >= 3 else {
            return nil
        }

        let points = poseResults.map(\.translationVector)
        let centroid = points.reduce(SIMD3<Double>.zero) { $0 + $1 } / Double(points.count)
        var bestNormal: SIMD3<Double>?
        var bestScore = Double.infinity

        for firstIndex in 0..<(points.count - 2) {
            for secondIndex in (firstIndex + 1)..<(points.count - 1) {
                for thirdIndex in (secondIndex + 1)..<points.count {
                    let normal = simd_cross(
                        points[secondIndex] - points[firstIndex],
                        points[thirdIndex] - points[firstIndex]
                    )
                    let normalLength = simd_length(normal)
                    guard normalLength.isFinite, normalLength > 1e-9 else {
                        continue
                    }

                    let unitNormal = normal / normalLength
                    let distances = points.map {
                        simd_dot($0 - centroid, unitNormal)
                    }
                    let absoluteDistances = distances.map(abs)
                    let averageError = average(absoluteDistances) ?? .infinity
                    let maximumError = absoluteDistances.max() ?? .infinity
                    let score = averageError + maximumError * 0.25
                    if score < bestScore {
                        bestScore = score
                        bestNormal = unitNormal
                    }
                }
            }
        }

        guard var normal = bestNormal else {
            return nil
        }

        var signedDistances = points.map {
            simd_dot($0 - centroid, normal)
        }
        if let firstNonZero = signedDistances.first(where: { abs($0) > 1e-9 }),
           firstNonZero < 0 {
            normal = -normal
            signedDistances = points.map {
                simd_dot($0 - centroid, normal)
            }
        }

        let absoluteDistances = signedDistances.map(abs)
        guard let averageError = average(absoluteDistances),
              let maximumError = absoluteDistances.max(),
              averageError.isFinite,
              maximumError.isFinite
        else {
            return nil
        }

        let distancesByMarkerId = Dictionary(
            uniqueKeysWithValues: zip(poseResults.map(\.markerId), signedDistances)
        )

        return PlanarDiagnostics(
            averageErrorMm: averageError,
            maximumErrorMm: maximumError,
            signedDistancesByMarkerId: distancesByMarkerId
        )
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
        let hasMinimumDualAngularCoverage: Bool
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
        let dualTagRejectionReasons: [Int: String]
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
