import Foundation
import simd

enum CaptureMaturityObservationPolicy: String, Codable, Equatable, Sendable {
    case all = "ALL"
    case filtered = "FILTERED"

    var replayPolicy: ScanSessionReplayObservationPolicy {
        switch self {
        case .all:
            return .allPersisted
        case .filtered:
            return .preAccumulationGateAcceptedOnly
        }
    }
}

enum CaptureMaturityReplayMode: String, Codable, Equatable, Sendable {
    case strict = "STRICT"
    case referenceLike = "REFERENCE_LIKE"
}

enum CaptureMaturitySelectionStrategy: String, Codable, Equatable, Sendable {
    case perMarkerObservation
    case wholeFrameWhenAnyMarkerHasDistinctView
}

enum MarkerCaptureMaturityState: String, Codable, Equatable, Sendable {
    case notObserved
    case insufficientValidObservations
    case insufficientDistinctViews
    case insufficientAngularSpread
    case insufficientCoverage
    case mature
}

enum GlobalCaptureMaturityState: String, Codable, Equatable, Sendable {
    case notStarted
    case insufficientMarkerMaturity
    case insufficientConnectivity
    case insufficientSelectedFrameSupport
    case mature
}

enum CaptureMaturityEvidenceClassification: String, Codable, Equatable, Sendable {
    case confirmedByImplementation = "CONFIRMED_BY_IMPLEMENTATION"
    case confirmedByConfiguration = "CONFIRMED_BY_CONFIGURATION"
    case confirmedBySymbol = "CONFIRMED_BY_SYMBOL"
    case strongIndication = "STRONG_INDICATION"
    case inference = "INFERENCE"
    case uncertain = "UNCERTAIN"
}

enum CaptureMaturityObservationRejectReason:
    String,
    Codable,
    CaseIterable,
    Equatable,
    Error,
    Sendable {
    case nonFiniteRotation
    case nonOrthonormalRotation
    case invalidRotationDeterminant
    case nonFiniteTranslation
    case zeroCameraCenterNorm
    case unexpectedMarker
}

struct CaptureMaturityCoverageBin: Codable, Equatable, Hashable, Sendable {
    let azimuthIndex: Int
    let elevationIndex: Int
    let azimuthMinimumDegrees: Double
    let azimuthMaximumDegrees: Double
    let elevationMinimumDegrees: Double
    let elevationMaximumDegrees: Double
}

struct CaptureMaturityCoverageSummary: Codable, Equatable, Sendable {
    let azimuthConvention: String
    let elevationConvention: String
    let poleHandling: String
    let coveredBinCount: Int
    let totalBinCount: Int
    let coveragePercent: Double
    let coveredBins: [CaptureMaturityCoverageBin]
    let missingBins: [CaptureMaturityCoverageBin]
}

fileprivate struct CaptureMaturityCoverageMetrics {
    let coveredBinCount: Int
    let totalBinCount: Int
    let coveragePercent: Double
}

enum CaptureMaturityCoverage {
    static func summary(
        directions: [SIMD3<Double>],
        azimuthBinCount: Int,
        elevationBinCount: Int,
        epsilon: Double
    ) -> CaptureMaturityCoverageSummary {
        let azimuthCount = max(azimuthBinCount, 1)
        let elevationCount = max(elevationBinCount, 1)
        let covered = coveredBins(
            directions: directions,
            azimuthBinCount: azimuthCount,
            elevationBinCount: elevationCount,
            epsilon: epsilon
        )

        var allBins: [CaptureMaturityCoverageBin] = []
        for elevationIndex in 0..<elevationCount {
            for azimuthIndex in 0..<azimuthCount {
                allBins.append(
                    makeBin(
                        azimuthIndex: azimuthIndex,
                        elevationIndex: elevationIndex,
                        azimuthBinCount: azimuthCount,
                        elevationBinCount: elevationCount
                    )
                )
            }
        }
        let coveredBins = covered.sorted(by: binSort)
        let missingBins = allBins.filter { !covered.contains($0) }
        let total = allBins.count
        return CaptureMaturityCoverageSummary(
            azimuthConvention:
                "atan2(y, x), +180 normalized to -180, range [-180, 180) degrees in marker coordinates",
            elevationConvention:
                "asin(z), range [-90, 90] degrees in marker coordinates",
            poleHandling:
                "azimuth is deterministically set to 0 degrees when horizontal norm <= epsilon",
            coveredBinCount: coveredBins.count,
            totalBinCount: total,
            coveragePercent: total > 0
                ? Double(coveredBins.count) * 100.0 / Double(total)
                : 0,
            coveredBins: coveredBins,
            missingBins: missingBins
        )
    }

    fileprivate static func metrics(
        directions: [SIMD3<Double>],
        azimuthBinCount: Int,
        elevationBinCount: Int,
        epsilon: Double
    ) -> CaptureMaturityCoverageMetrics {
        let azimuthCount = max(azimuthBinCount, 1)
        let elevationCount = max(elevationBinCount, 1)
        let coveredCount = coveredBins(
            directions: directions,
            azimuthBinCount: azimuthCount,
            elevationBinCount: elevationCount,
            epsilon: epsilon
        ).count
        let total = azimuthCount * elevationCount
        return CaptureMaturityCoverageMetrics(
            coveredBinCount: coveredCount,
            totalBinCount: total,
            coveragePercent: total > 0
                ? Double(coveredCount) * 100.0 / Double(total)
                : 0
        )
    }

    private static func coveredBins(
        directions: [SIMD3<Double>],
        azimuthBinCount: Int,
        elevationBinCount: Int,
        epsilon: Double
    ) -> Set<CaptureMaturityCoverageBin> {
        var covered = Set<CaptureMaturityCoverageBin>()
        for direction in directions {
            guard let unit = CaptureMaturityViewpointMath.normalized(
                direction,
                epsilon: epsilon
            ) else {
                continue
            }
            covered.insert(
                bin(
                    for: unit,
                    azimuthBinCount: azimuthBinCount,
                    elevationBinCount: elevationBinCount,
                    epsilon: epsilon
                )
            )
        }
        return covered
    }

    private static func bin(
        for direction: SIMD3<Double>,
        azimuthBinCount: Int,
        elevationBinCount: Int,
        epsilon: Double
    ) -> CaptureMaturityCoverageBin {
        let horizontalNorm = hypot(direction.x, direction.y)
        let rawAzimuthRadians = horizontalNorm <= epsilon
            ? 0
            : atan2(direction.y, direction.x)
        let azimuthRadians = rawAzimuthRadians >= Double.pi
            ? -Double.pi
            : rawAzimuthRadians
        let elevationRadians = asin(min(max(direction.z, -1.0), 1.0))
        let azimuthFraction = (azimuthRadians + Double.pi) /
            (2.0 * Double.pi)
        let elevationFraction = (elevationRadians + Double.pi / 2.0) /
            Double.pi
        let azimuthIndex = min(
            max(Int(floor(azimuthFraction * Double(azimuthBinCount))), 0),
            azimuthBinCount - 1
        )
        let elevationIndex = min(
            max(Int(floor(elevationFraction * Double(elevationBinCount))), 0),
            elevationBinCount - 1
        )
        return makeBin(
            azimuthIndex: azimuthIndex,
            elevationIndex: elevationIndex,
            azimuthBinCount: azimuthBinCount,
            elevationBinCount: elevationBinCount
        )
    }

    private static func makeBin(
        azimuthIndex: Int,
        elevationIndex: Int,
        azimuthBinCount: Int,
        elevationBinCount: Int
    ) -> CaptureMaturityCoverageBin {
        let azimuthWidth = 360.0 / Double(azimuthBinCount)
        let elevationHeight = 180.0 / Double(elevationBinCount)
        return CaptureMaturityCoverageBin(
            azimuthIndex: azimuthIndex,
            elevationIndex: elevationIndex,
            azimuthMinimumDegrees: -180.0 +
                Double(azimuthIndex) * azimuthWidth,
            azimuthMaximumDegrees: -180.0 +
                Double(azimuthIndex + 1) * azimuthWidth,
            elevationMinimumDegrees: -90.0 +
                Double(elevationIndex) * elevationHeight,
            elevationMaximumDegrees: -90.0 +
                Double(elevationIndex + 1) * elevationHeight
        )
    }

    private static func binSort(
        _ lhs: CaptureMaturityCoverageBin,
        _ rhs: CaptureMaturityCoverageBin
    ) -> Bool {
        lhs.elevationIndex == rhs.elevationIndex
            ? lhs.azimuthIndex < rhs.azimuthIndex
            : lhs.elevationIndex < rhs.elevationIndex
    }
}

struct CaptureMaturityReasonCount: Codable, Equatable, Sendable {
    let reason: String
    let count: Int
}

struct CaptureMaturityProgressComponents: Codable, Equatable, Sendable {
    let validObservationProgress: Double
    let distinctViewProgress: Double
    let angularSpreadProgress: Double
    let coverageProgress: Double
    let markerProgress: Double
}

struct SelectedCaptureViewpoint: Codable, Equatable, Sendable {
    let frameIndex: Int
    let timestampSeconds: Double?
    let cameraCenterInMarker: ObservationPoint3D
    let viewDirection: ObservationPoint3D
}

struct MarkerCaptureMaturitySnapshot: Codable, Equatable, Sendable {
    let markerId: Int
    let isExpectedMarker: Bool
    let rawObservationCount: Int
    let policyInputObservationCount: Int
    let validObservationCount: Int
    let selectedObservationCount: Int
    let selectedDistinctViewCount: Int
    let redundantViewCount: Int
    let frameSupportExcludedObservationCount: Int
    let rejectedObservationCount: Int
    let rejectionReasons: [CaptureMaturityReasonCount]
    let selectedViewpoints: [SelectedCaptureViewpoint]
    let selectedViewDirections: [ObservationPoint3D]
    let minimumNearestSelectedAngleDegrees: Double?
    let meanNearestSelectedAngleDegrees: Double?
    let angularSpreadDegrees: Double?
    let angularMeanDirectionDefined: Bool
    let coverage: CaptureMaturityCoverageSummary
    let firstObservedTimestamp: Double?
    let firstDistinctViewTimestamp: Double?
    let maturityTimestamp: Double?
    let maturityFrameIndex: Int?
    let maturityState: MarkerCaptureMaturityState
    let progress: CaptureMaturityProgressComponents
    let blockingReason: String?
    let confirmedCriteriaSatisfied: [String]
    let adaptedCriteriaSatisfied: [String]
    let uncertainCriteria: [String]
}

struct CaptureMaturityConnectivitySummary: Codable, Equatable, Sendable {
    let componentCount: Int
    let largestComponentFrameCount: Int
    let largestComponentObservationCount: Int
    let largestComponentMarkerIds: [Int]
    let expectedMarkersConnected: Bool
    let disconnectedMarkerIds: [Int]
    let isolatedFrameCount: Int
}

struct CaptureMaturitySelectionSummary: Codable, Equatable, Sendable {
    let strategy: String
    let framesProcessed: Int
    let sourceObservationCount: Int
    let policyInputObservationCount: Int
    let validObservationCount: Int
    let rejectedObservationCount: Int
    let frameSupportExcludedObservationCount: Int
    let selectedObservationCount: Int
    let selectedFrameCount: Int
    let framesWithOneSelectedMarker: Int
    let framesWithAllExpectedMarkersSelected: Int
    let framesWithAllExpectedMarkersObserved: Int
    let timestampMissingCount: Int
    let timestampRegressionCount: Int
}

struct CaptureMaturityGlobalSnapshot: Codable, Equatable, Sendable {
    let firstTimestampAllMarkersMature: Double?
    let frameIndexAllMarkersMature: Int?
    let firstTimestampGlobalMature: Double?
    let frameIndexGlobalMature: Int?
    let slowestMarkerId: Int?
    let slowestMarkerBlockingReason: String?
    let matureMarkerCount: Int
    let expectedMarkerCount: Int
    let selectedFrameCount: Int
    let selectedObservationCount: Int
    let optimizationTargetReachedTimestamp: Double?
    let optimizationTargetReachedFrameIndex: Int?
    let optimizationTargetProgress: Double
    let expectedMarkersConnected: Bool
    let globalMaturityState: GlobalCaptureMaturityState
    let globalBlockingReason: String?
    let globalProgressPercent: Double
    let confirmedCriteriaSatisfied: [String]
    let adaptedCriteriaSatisfied: [String]
    let uncertainCriteria: [String]
}

struct CaptureMaturityTimelineMarkerSnapshot: Codable, Equatable, Sendable {
    let markerId: Int
    let rawObservationCount: Int
    let validObservationCount: Int
    let selectedDistinctViewCount: Int
    let redundantViewCount: Int
    let angularSpreadDegrees: Double?
    let angularMeanDirectionDefined: Bool
    let coveragePercent: Double
    let maturityState: MarkerCaptureMaturityState
    let progressPercent: Double
    let blockingReason: String?
}

struct CaptureMaturityTimelineGlobalSnapshot: Codable, Equatable, Sendable {
    let matureMarkerCount: Int
    let expectedMarkerCount: Int
    let allMarkersMature: Bool
    let selectedFrameCount: Int
    let selectedObservationCount: Int
    let connectivityReady: Bool
    let optimizationTargetProgress: Double
    let globalProgressPercent: Double
    let blockingReason: String?
}

struct CaptureMaturityTimelineSnapshot: Codable, Equatable, Sendable {
    let timestampSeconds: Double?
    let elapsedSeconds: Double?
    let frameIndex: Int
    let policy: String
    let mode: String
    let perMarker: [CaptureMaturityTimelineMarkerSnapshot]
    let global: CaptureMaturityTimelineGlobalSnapshot
}

struct CaptureMaturityRelaxationEvent: Codable, Equatable, Sendable {
    let frameIndex: Int
    let timestampSeconds: Double?
    let selectedFrameCount: Int
    let reason: String
    let previousMinimumDistinctViewAngleDegrees: Double
    let currentMinimumDistinctViewAngleDegrees: Double
    let previousMinimumAngularSpreadDegrees: Double
    let currentMinimumAngularSpreadDegrees: Double
    let relaxationCount: Int
    let nextRelaxationSelectedFrameThreshold: Int?
    let preventedFurtherRelaxationReason: String?
}

struct CaptureMaturityModeReplaySummary: Codable, Equatable, Sendable {
    let mode: String
    let selection: CaptureMaturitySelectionSummary
    let markerMaturity: [MarkerCaptureMaturitySnapshot]
    let validConnectivity: CaptureMaturityConnectivitySummary
    let selectedConnectivity: CaptureMaturityConnectivitySummary
    let globalMaturity: CaptureMaturityGlobalSnapshot
    let timeline: [CaptureMaturityTimelineSnapshot]
    let initialMinimumDistinctViewAngleDegrees: Double
    let currentMinimumDistinctViewAngleDegrees: Double
    let initialMinimumAngularSpreadDegrees: Double
    let currentMinimumAngularSpreadDegrees: Double
    let relaxationHistory: [CaptureMaturityRelaxationEvent]
    let relaxationCount: Int
    let selectionFrameIndices: [Int]
}

struct CaptureMaturityPolicyReplaySummary: Codable, Equatable, Sendable {
    let policy: String
    let strict: CaptureMaturityModeReplaySummary
    let referenceLike: CaptureMaturityModeReplaySummary?
    let readerSelectionDiagnostics: ScanSessionReplaySelectionDiagnostics
    let missingGateEvaluationCount: Int
    let missingGateDecisionCount: Int
}

struct CaptureMaturityActualProgressComparison: Codable, Equatable, Sendable {
    let comparisonStatus: String
    let sourceProgressArtifactFilename: String?
    let actualAllMarkersSeenTimestamp: Double?
    let actualAllMarkersExportableTimestamp: Double?
    let actualUI100PercentTimestamp: Double?
    let actualFinalizationStartedTimestamp: Double?
    let actualExportTriggeredTimestamp: Double?
    let actualExportTimestamp: Double?
    let offlineStrictMaturityTimestamp: Double?
    let offlineReferenceLikeMaturityTimestamp: Double?
    let filteredOfflineStrictMaturityTimestamp: Double?
    let ui100ToStrictMaturityDeltaSeconds: Double?
    let exportableToStrictMaturityDeltaSeconds: Double?
    let strictMaturityReachedBeforeExport: Bool?
    let caveats: [String]

    static let unavailable = CaptureMaturityActualProgressComparison(
        comparisonStatus: "unavailable",
        sourceProgressArtifactFilename: nil,
        actualAllMarkersSeenTimestamp: nil,
        actualAllMarkersExportableTimestamp: nil,
        actualUI100PercentTimestamp: nil,
        actualFinalizationStartedTimestamp: nil,
        actualExportTriggeredTimestamp: nil,
        actualExportTimestamp: nil,
        offlineStrictMaturityTimestamp: nil,
        offlineReferenceLikeMaturityTimestamp: nil,
        filteredOfflineStrictMaturityTimestamp: nil,
        ui100ToStrictMaturityDeltaSeconds: nil,
        exportableToStrictMaturityDeltaSeconds: nil,
        strictMaturityReachedBeforeExport: nil,
        caveats: ["associated diagnostics were not available"]
    )
}

struct CaptureMaturityReplaySummary: Codable, Equatable, Sendable {
    let artifactSchemaVersion: Int
    let algorithmIdentifier: String
    let sourceSessionFilename: String
    let sessionIdentifier: String
    let sourceSessionSchemaVersion: Int
    let appVersion: String?
    let appBuildIdentifier: String?
    let appGitCommitHash: String?
    let deviceModelIdentifier: String
    let osVersion: String
    let cameraProfileId: String
    let cameraProfileName: String
    let markerProfile: String
    let expectedPhysicalMarkerIds: [Int]
    let poseConvention: String
    let viewpointConvention: String
    let angleUnit: String
    let configuration: CaptureMaturityReplayConfiguration
    let all: CaptureMaturityPolicyReplaySummary
    let filtered: CaptureMaturityPolicyReplaySummary
    let actualProgressComparison: CaptureMaturityActualProgressComparison
    let integrityResult: String
    let provenanceCaveats: [String]
}

struct CaptureMaturityReplayResult {
    let summary: CaptureMaturityReplaySummary
}

private enum CaptureMaturityGraphNode: Hashable {
    case frame(Int)
    case marker(Int)
}

private struct CaptureMaturityGraphEdge: Hashable {
    let frameIndex: Int
    let markerId: Int
}

private final class CaptureMaturityBipartiteGraph {
    private var adjacency: [CaptureMaturityGraphNode: Set<CaptureMaturityGraphNode>] = [:]
    private var edgeObservationCounts: [CaptureMaturityGraphEdge: Int] = [:]
    private var parent: [CaptureMaturityGraphNode: CaptureMaturityGraphNode] = [:]
    private var rank: [CaptureMaturityGraphNode: Int] = [:]

    func addObservation(frameIndex: Int, markerId: Int) {
        let frame = CaptureMaturityGraphNode.frame(frameIndex)
        let marker = CaptureMaturityGraphNode.marker(markerId)
        addNode(frame)
        addNode(marker)
        adjacency[frame, default: []].insert(marker)
        adjacency[marker, default: []].insert(frame)
        edgeObservationCounts[
            CaptureMaturityGraphEdge(
                frameIndex: frameIndex,
                markerId: markerId
            ),
            default: 0
        ] += 1
        union(frame, marker)
    }

    func expectedMarkersConnected(_ expectedMarkerIds: [Int]) -> Bool {
        guard let firstId = expectedMarkerIds.sorted().first else {
            return false
        }
        let firstNode = CaptureMaturityGraphNode.marker(firstId)
        guard parent[firstNode] != nil else { return false }
        let root = find(firstNode)
        return expectedMarkerIds.allSatisfy { markerId in
            let node = CaptureMaturityGraphNode.marker(markerId)
            return parent[node] != nil && find(node) == root
        }
    }

    func summary(
        expectedMarkerIds: [Int],
        allFrameIndices: Set<Int>
    ) -> CaptureMaturityConnectivitySummary {
        var nodes = Set(adjacency.keys)
        for frameIndex in allFrameIndices {
            nodes.insert(.frame(frameIndex))
        }
        for markerId in expectedMarkerIds {
            nodes.insert(.marker(markerId))
        }

        var visited = Set<CaptureMaturityGraphNode>()
        var components: [(frames: [Int], markers: [Int], observations: Int)] = []
        for start in nodes.sorted(by: nodeSort) where !visited.contains(start) {
            var queue = [start]
            visited.insert(start)
            var frames: [Int] = []
            var markers: [Int] = []
            while !queue.isEmpty {
                let node = queue.removeFirst()
                switch node {
                case let .frame(frameIndex):
                    frames.append(frameIndex)
                case let .marker(markerId):
                    markers.append(markerId)
                }
                for neighbor in adjacency[node, default: []].sorted(by: nodeSort)
                    where !visited.contains(neighbor) {
                    visited.insert(neighbor)
                    queue.append(neighbor)
                }
            }
            let frameSet = Set(frames)
            let markerSet = Set(markers)
            let observationCount = edgeObservationCounts.reduce(0) { partial, item in
                frameSet.contains(item.key.frameIndex) &&
                    markerSet.contains(item.key.markerId)
                    ? partial + item.value
                    : partial
            }
            components.append(
                (
                    frames: frames.sorted(),
                    markers: markers.sorted(),
                    observations: observationCount
                )
            )
        }

        let largest = components.sorted { lhs, rhs in
            if lhs.frames.count != rhs.frames.count {
                return lhs.frames.count > rhs.frames.count
            }
            if lhs.observations != rhs.observations {
                return lhs.observations > rhs.observations
            }
            if lhs.markers.count != rhs.markers.count {
                return lhs.markers.count > rhs.markers.count
            }
            return lhs.markers.lexicographicallyPrecedes(rhs.markers)
        }.first
        let connected = expectedMarkersConnected(expectedMarkerIds)
        let disconnected = disconnectedExpectedMarkers(expectedMarkerIds)
        let isolatedFrameCount = allFrameIndices.filter {
            adjacency[.frame($0), default: []].isEmpty
        }.count
        return CaptureMaturityConnectivitySummary(
            componentCount: components.count,
            largestComponentFrameCount: largest?.frames.count ?? 0,
            largestComponentObservationCount: largest?.observations ?? 0,
            largestComponentMarkerIds: largest?.markers ?? [],
            expectedMarkersConnected: connected,
            disconnectedMarkerIds: disconnected,
            isolatedFrameCount: isolatedFrameCount
        )
    }

    private func disconnectedExpectedMarkers(_ expectedMarkerIds: [Int]) -> [Int] {
        guard let firstConnectedId = expectedMarkerIds.sorted().first(where: {
            parent[.marker($0)] != nil
        }) else {
            return expectedMarkerIds.sorted()
        }
        let root = find(.marker(firstConnectedId))
        return expectedMarkerIds.filter {
            let node = CaptureMaturityGraphNode.marker($0)
            return parent[node] == nil || find(node) != root
        }.sorted()
    }

    private func addNode(_ node: CaptureMaturityGraphNode) {
        if parent[node] == nil {
            parent[node] = node
            rank[node] = 0
        }
    }

    private func find(_ node: CaptureMaturityGraphNode) -> CaptureMaturityGraphNode {
        guard let currentParent = parent[node] else { return node }
        if currentParent == node { return node }
        let root = find(currentParent)
        parent[node] = root
        return root
    }

    private func union(
        _ lhs: CaptureMaturityGraphNode,
        _ rhs: CaptureMaturityGraphNode
    ) {
        let lhsRoot = find(lhs)
        let rhsRoot = find(rhs)
        guard lhsRoot != rhsRoot else { return }
        let lhsRank = rank[lhsRoot, default: 0]
        let rhsRank = rank[rhsRoot, default: 0]
        if lhsRank < rhsRank {
            parent[lhsRoot] = rhsRoot
        } else if lhsRank > rhsRank {
            parent[rhsRoot] = lhsRoot
        } else {
            parent[rhsRoot] = lhsRoot
            rank[lhsRoot] = lhsRank + 1
        }
    }

    private func nodeSort(
        _ lhs: CaptureMaturityGraphNode,
        _ rhs: CaptureMaturityGraphNode
    ) -> Bool {
        switch (lhs, rhs) {
        case let (.frame(lhsIndex), .frame(rhsIndex)):
            return lhsIndex < rhsIndex
        case (.frame, .marker):
            return true
        case (.marker, .frame):
            return false
        case let (.marker(lhsId), .marker(rhsId)):
            return lhsId < rhsId
        }
    }
}

private struct CaptureMaturityMarkerState {
    let markerId: Int
    let isExpected: Bool
    var rawObservationCount = 0
    var policyInputObservationCount = 0
    var validObservationCount = 0
    var selectedObservationCount = 0
    var redundantViewCount = 0
    var frameSupportExcludedObservationCount = 0
    var rejectedObservationCount = 0
    var rejectionReasons: [CaptureMaturityObservationRejectReason: Int] = [:]
    var selectedDirections: [SIMD3<Double>] = []
    var selectedViewpoints: [MarkerViewpointObservation] = []
    var firstObservedTimestamp: Double?
    var firstDistinctViewTimestamp: Double?
    var maturityTimestamp: Double?
    var maturityFrameIndex: Int?
}

private struct CaptureMaturityCandidate {
    let markerInput: ScanSessionReplayMarkerObservationInput
    let viewpoint: MarkerViewpointObservation
    let isDistinct: Bool
}

private struct CaptureMaturityMarkerMetrics {
    let maturityState: MarkerCaptureMaturityState
    let angularSpreadDegrees: Double?
    let angularMeanDirectionDefined: Bool
    let coveragePercent: Double
    let progress: CaptureMaturityProgressComponents
    let blockingReason: String?
}

final class CaptureMaturitySessionAnalyzer {
    private let policy: CaptureMaturityObservationPolicy
    private let mode: CaptureMaturityReplayMode
    private let configuration: CaptureMaturityReplayConfiguration
    private let selectionStrategy: CaptureMaturitySelectionStrategy
    private let expectedMarkerIds: [Int]
    private let expectedMarkerIdSet: Set<Int>

    private var markerStates: [Int: CaptureMaturityMarkerState] = [:]
    private let validGraph = CaptureMaturityBipartiteGraph()
    private let selectedGraph = CaptureMaturityBipartiteGraph()
    private var allFrameIndices = Set<Int>()
    private var selectedFrameIndices = Set<Int>()
    private var framesProcessed = 0
    private var sourceObservationCount = 0
    private var policyInputObservationCount = 0
    private var validObservationCount = 0
    private var rejectedObservationCount = 0
    private var frameSupportExcludedObservationCount = 0
    private var selectedObservationCount = 0
    private var framesWithOneSelectedMarker = 0
    private var framesWithAllExpectedMarkersSelected = 0
    private var framesWithAllExpectedMarkersObserved = 0
    private var timestampMissingCount = 0
    private var timestampRegressionCount = 0
    private var firstFrameTimestamp: Double?
    private var lastPhysicalTimestamp: Double?
    private var effectiveElapsedSeconds: Double?
    private var nextTimelineElapsedSeconds = 0.0
    private var timeline: [CaptureMaturityTimelineSnapshot] = []
    private var lastFrameIndex: Int?
    private var lastFrameTimestamp: Double?
    private var firstAllMarkersMatureTimestamp: Double?
    private var firstAllMarkersMatureFrameIndex: Int?
    private var firstGlobalMatureTimestamp: Double?
    private var firstGlobalMatureFrameIndex: Int?
    private var optimizationTargetReachedTimestamp: Double?
    private var optimizationTargetReachedFrameIndex: Int?
    private var currentMinimumDistinctViewAngleDegrees: Double
    private var currentMinimumAngularSpreadDegrees: Double
    private var relaxationHistory: [CaptureMaturityRelaxationEvent] = []
    private var nextRelaxationSelectedFrameThreshold: Int?

    init(
        metadata: ScanSessionReplayCaptureMetadata,
        policy: CaptureMaturityObservationPolicy,
        mode: CaptureMaturityReplayMode,
        configuration: CaptureMaturityReplayConfiguration
    ) {
        self.policy = policy
        self.mode = mode
        self.configuration = configuration
        self.expectedMarkerIds = Array(
            Set(metadata.expectedPhysicalMarkerIds)
        ).sorted()
        self.expectedMarkerIdSet = Set(expectedMarkerIds)
        self.selectionStrategy = mode == .strict
            ? configuration.strictSelectionStrategy
            : configuration.referenceLikeSelectionStrategy
        self.currentMinimumDistinctViewAngleDegrees =
            configuration.minimumDistinctViewAngleDegrees
        self.currentMinimumAngularSpreadDegrees =
            configuration.minimumAngularSpreadDegrees

        if mode == .referenceLike,
           configuration.relaxationPolicy.enabled {
            nextRelaxationSelectedFrameThreshold = Self.relaxationThreshold(
                target: configuration.targetSelectedFrameCount,
                fraction: configuration.relaxationPolicy.halfProgressFraction
            )
        }
        for markerId in expectedMarkerIds {
            markerStates[markerId] = CaptureMaturityMarkerState(
                markerId: markerId,
                isExpected: true
            )
        }
    }

    func process(_ input: ScanSessionReplayObservationFrameInput) {
        let frame = input.frame
        framesProcessed += 1
        allFrameIndices.insert(frame.frameIndex)
        lastFrameIndex = frame.frameIndex
        lastFrameTimestamp = frame.timestampSeconds
        updateTimestampState(frame.timestampSeconds)

        let rawMarkerIds = Set(frame.markerObservations.map(\.markerId))
        if expectedMarkerIdSet.isSubset(of: rawMarkerIds),
           !expectedMarkerIdSet.isEmpty {
            framesWithAllExpectedMarkersObserved += 1
        }

        let selectedPositions = Set(
            input.selectedMarkerObservations.map(\.markerPosition)
        )
        for (position, observation) in frame.markerObservations.enumerated() {
            sourceObservationCount += 1
            var state = state(for: observation.markerId)
            state.rawObservationCount += 1
            if state.firstObservedTimestamp == nil {
                state.firstObservedTimestamp = frame.timestampSeconds
            }
            if selectedPositions.contains(position) {
                state.policyInputObservationCount += 1
            }
            markerStates[observation.markerId] = state
        }

        var candidates: [CaptureMaturityCandidate] = []
        for markerInput in input.selectedMarkerObservations {
            policyInputObservationCount += 1
            let markerId = markerInput.observation.markerId
            var state = state(for: markerId)
            if !expectedMarkerIdSet.contains(markerId) {
                state.rejectedObservationCount += 1
                state.rejectionReasons[.unexpectedMarker, default: 0] += 1
                rejectedObservationCount += 1
                markerStates[markerId] = state
                continue
            }

            switch CaptureMaturityViewpointMath.viewpoint(
                frameIndex: frame.frameIndex,
                timestampSeconds: frame.timestampSeconds,
                pose: markerInput.poseResult,
                configuration: configuration
            ) {
            case let .failure(reason):
                state.rejectedObservationCount += 1
                state.rejectionReasons[reason, default: 0] += 1
                rejectedObservationCount += 1
                markerStates[markerId] = state

            case let .success(viewpoint):
                state.validObservationCount += 1
                validObservationCount += 1
                validGraph.addObservation(
                    frameIndex: frame.frameIndex,
                    markerId: markerId
                )
                let nearestAngle = state.selectedDirections.map {
                    CaptureMaturityViewpointMath.angularDistanceDegrees(
                        viewpoint.viewDirection,
                        $0
                    )
                }.min()
                let isDistinct = nearestAngle.map {
                    $0 + 1e-12 >= currentMinimumDistinctViewAngleDegrees
                } ?? true
                candidates.append(
                    CaptureMaturityCandidate(
                        markerInput: markerInput,
                        viewpoint: viewpoint,
                        isDistinct: isDistinct
                    )
                )
                markerStates[markerId] = state
            }
        }

        let frameSelected = selectCandidates(candidates, frame: frame)
        if frameSelected {
            selectedFrameIndices.insert(frame.frameIndex)
        }
        updateOptimizationTarget(frame: frame)
        updateMaturity(frame: frame)
        if applyReferenceLikeRelaxationIfNeeded(frame: frame) {
            updateMaturity(frame: frame)
        }
        appendTimelineSnapshots(frame: frame)
    }

    func makeSummary() -> CaptureMaturityModeReplaySummary {
        if timeline.isEmpty, let frameIndex = lastFrameIndex {
            timeline.append(
                timelineSnapshot(
                    frameIndex: frameIndex,
                    timestampSeconds: lastFrameTimestamp,
                    elapsedSeconds: effectiveElapsedSeconds
                )
            )
        } else if let frameIndex = lastFrameIndex,
                  timeline.last?.frameIndex != frameIndex ||
                    timeline.last?.timestampSeconds != lastFrameTimestamp {
            timeline.append(
                timelineSnapshot(
                    frameIndex: frameIndex,
                    timestampSeconds: lastFrameTimestamp,
                    elapsedSeconds: effectiveElapsedSeconds
                )
            )
        }

        let markerSnapshots = markerStates.keys.sorted().map {
            markerSnapshot(markerId: $0)
        }
        let validConnectivity = validGraph.summary(
            expectedMarkerIds: expectedMarkerIds,
            allFrameIndices: allFrameIndices
        )
        let selectedConnectivity = selectedGraph.summary(
            expectedMarkerIds: expectedMarkerIds,
            allFrameIndices: allFrameIndices
        )
        return CaptureMaturityModeReplaySummary(
            mode: mode.rawValue,
            selection: CaptureMaturitySelectionSummary(
                strategy: selectionStrategy.rawValue,
                framesProcessed: framesProcessed,
                sourceObservationCount: sourceObservationCount,
                policyInputObservationCount: policyInputObservationCount,
                validObservationCount: validObservationCount,
                rejectedObservationCount: rejectedObservationCount,
                frameSupportExcludedObservationCount:
                    frameSupportExcludedObservationCount,
                selectedObservationCount: selectedObservationCount,
                selectedFrameCount: selectedFrameIndices.count,
                framesWithOneSelectedMarker: framesWithOneSelectedMarker,
                framesWithAllExpectedMarkersSelected:
                    framesWithAllExpectedMarkersSelected,
                framesWithAllExpectedMarkersObserved:
                    framesWithAllExpectedMarkersObserved,
                timestampMissingCount: timestampMissingCount,
                timestampRegressionCount: timestampRegressionCount
            ),
            markerMaturity: markerSnapshots,
            validConnectivity: validConnectivity,
            selectedConnectivity: selectedConnectivity,
            globalMaturity: globalSnapshot(),
            timeline: timeline,
            initialMinimumDistinctViewAngleDegrees:
                configuration.minimumDistinctViewAngleDegrees,
            currentMinimumDistinctViewAngleDegrees:
                currentMinimumDistinctViewAngleDegrees,
            initialMinimumAngularSpreadDegrees:
                configuration.minimumAngularSpreadDegrees,
            currentMinimumAngularSpreadDegrees:
                currentMinimumAngularSpreadDegrees,
            relaxationHistory: relaxationHistory,
            relaxationCount: relaxationHistory.count,
            selectionFrameIndices: selectedFrameIndices.sorted()
        )
    }

    private func state(for markerId: Int) -> CaptureMaturityMarkerState {
        markerStates[markerId] ?? CaptureMaturityMarkerState(
            markerId: markerId,
            isExpected: expectedMarkerIdSet.contains(markerId)
        )
    }

    @discardableResult
    private func selectCandidates(
        _ candidates: [CaptureMaturityCandidate],
        frame: FrameObservation
    ) -> Bool {
        guard candidates.count >= configuration.minimumObservationsPerFrame else {
            for candidate in candidates {
                var state = state(for: candidate.viewpoint.markerId)
                state.frameSupportExcludedObservationCount += 1
                markerStates[candidate.viewpoint.markerId] = state
                frameSupportExcludedObservationCount += 1
            }
            return false
        }

        let orderedCandidates = candidates.sorted {
            $0.markerInput.markerPosition < $1.markerInput.markerPosition
        }
        let shouldSelectFrame: Bool
        switch selectionStrategy {
        case .perMarkerObservation:
            shouldSelectFrame = orderedCandidates.contains(where: \.isDistinct)
        case .wholeFrameWhenAnyMarkerHasDistinctView:
            shouldSelectFrame = orderedCandidates.contains(where: \.isDistinct)
        }
        guard shouldSelectFrame else {
            for candidate in orderedCandidates {
                markRedundant(candidate)
            }
            return false
        }

        var selectedMarkerIds = Set<Int>()
        for candidate in orderedCandidates {
            switch selectionStrategy {
            case .perMarkerObservation:
                if isDistinctFromCurrentHistory(candidate) {
                    select(candidate, appendDistinctDirection: true)
                    selectedMarkerIds.insert(candidate.viewpoint.markerId)
                } else {
                    markRedundant(candidate)
                }

            case .wholeFrameWhenAnyMarkerHasDistinctView:
                let isDistinct = isDistinctFromCurrentHistory(candidate)
                select(candidate, appendDistinctDirection: isDistinct)
                selectedMarkerIds.insert(candidate.viewpoint.markerId)
                if !isDistinct {
                    markRedundant(candidate)
                }
            }
        }

        if !selectedMarkerIds.isEmpty {
            framesWithOneSelectedMarker += 1
        }
        if !expectedMarkerIdSet.isEmpty,
           expectedMarkerIdSet.isSubset(of: selectedMarkerIds) {
            framesWithAllExpectedMarkersSelected += 1
        }
        return !selectedMarkerIds.isEmpty
    }

    private func isDistinctFromCurrentHistory(
        _ candidate: CaptureMaturityCandidate
    ) -> Bool {
        let state = state(for: candidate.viewpoint.markerId)
        guard !state.selectedDirections.isEmpty else { return true }
        let nearestAngle = state.selectedDirections.map {
            CaptureMaturityViewpointMath.angularDistanceDegrees(
                candidate.viewpoint.viewDirection,
                $0
            )
        }.min() ?? 0
        return nearestAngle + 1e-12 >=
            currentMinimumDistinctViewAngleDegrees
    }

    private func select(
        _ candidate: CaptureMaturityCandidate,
        appendDistinctDirection: Bool
    ) {
        let markerId = candidate.viewpoint.markerId
        var state = state(for: markerId)
        state.selectedObservationCount += 1
        selectedObservationCount += 1
        selectedGraph.addObservation(
            frameIndex: candidate.viewpoint.frameIndex,
            markerId: markerId
        )
        if appendDistinctDirection {
            state.selectedDirections.append(candidate.viewpoint.viewDirection)
            state.selectedViewpoints.append(candidate.viewpoint)
            if state.firstDistinctViewTimestamp == nil {
                state.firstDistinctViewTimestamp =
                    candidate.viewpoint.timestampSeconds
            }
        }
        markerStates[markerId] = state
    }

    private func markRedundant(_ candidate: CaptureMaturityCandidate) {
        var state = state(for: candidate.viewpoint.markerId)
        state.redundantViewCount += 1
        markerStates[candidate.viewpoint.markerId] = state
    }

    private func updateTimestampState(_ timestamp: Double?) {
        guard let timestamp, timestamp.isFinite else {
            timestampMissingCount += 1
            return
        }
        if let lastPhysicalTimestamp, timestamp < lastPhysicalTimestamp {
            timestampRegressionCount += 1
        }
        lastPhysicalTimestamp = timestamp
        if firstFrameTimestamp == nil {
            firstFrameTimestamp = timestamp
        }
        let elapsed = max(timestamp - (firstFrameTimestamp ?? timestamp), 0)
        effectiveElapsedSeconds = max(effectiveElapsedSeconds ?? 0, elapsed)
    }

    private func updateOptimizationTarget(frame: FrameObservation) {
        guard optimizationTargetReachedTimestamp == nil,
              selectedFrameIndices.count >=
                configuration.targetSelectedFrameCount
        else {
            return
        }
        optimizationTargetReachedTimestamp = frame.timestampSeconds
        optimizationTargetReachedFrameIndex = frame.frameIndex
    }

    private func updateMaturity(frame: FrameObservation) {
        for markerId in expectedMarkerIds {
            let metrics = markerMetrics(markerId: markerId)
            if metrics.maturityState == .mature {
                var state = state(for: markerId)
                if state.maturityFrameIndex == nil {
                    state.maturityFrameIndex = frame.frameIndex
                    state.maturityTimestamp = frame.timestampSeconds
                    markerStates[markerId] = state
                }
            }
        }

        let allMarkersMature = !expectedMarkerIds.isEmpty &&
            expectedMarkerIds.allSatisfy {
                markerMetrics(markerId: $0).maturityState == .mature
            }
        if allMarkersMature,
           firstAllMarkersMatureFrameIndex == nil {
            firstAllMarkersMatureFrameIndex = frame.frameIndex
            firstAllMarkersMatureTimestamp = frame.timestampSeconds
        }
        if globalSnapshot().globalMaturityState == .mature,
           firstGlobalMatureFrameIndex == nil {
            firstGlobalMatureFrameIndex = frame.frameIndex
            firstGlobalMatureTimestamp = frame.timestampSeconds
        }
    }

    @discardableResult
    private func applyReferenceLikeRelaxationIfNeeded(
        frame: FrameObservation
    ) -> Bool {
        guard mode == .referenceLike,
              configuration.relaxationPolicy.enabled,
              globalSnapshot().globalMaturityState != .mature,
              expectedMarkerIds.contains(where: {
                  markerMetrics(markerId: $0).maturityState != .mature
              }),
              selectedGraph.expectedMarkersConnected(expectedMarkerIds),
              let threshold = nextRelaxationSelectedFrameThreshold,
              selectedFrameIndices.count >= threshold
        else {
            return false
        }

        let policy = configuration.relaxationPolicy
        let previousAngle = currentMinimumDistinctViewAngleDegrees
        let previousSpread = currentMinimumAngularSpreadDegrees
        let nextAngle = max(
            previousAngle * policy.angularSeparationFactor,
            policy.minimumAngularSeparationFloorDegrees
        )
        let nextSpread = max(
            previousSpread - policy.angularSpreadRelaxationStepDegrees,
            policy.minimumAngularSpreadDegrees
        )
        let changed = abs(nextAngle - previousAngle) > 1e-12 ||
            abs(nextSpread - previousSpread) > 1e-12
        let nextThreshold = changed
            ? threshold + Self.relaxationThreshold(
                target: configuration.targetSelectedFrameCount,
                fraction: policy.progressStepFraction
            )
            : nil
        currentMinimumDistinctViewAngleDegrees = nextAngle
        currentMinimumAngularSpreadDegrees = nextSpread
        nextRelaxationSelectedFrameThreshold = nextThreshold
        relaxationHistory.append(
            CaptureMaturityRelaxationEvent(
                frameIndex: frame.frameIndex,
                timestampSeconds: frame.timestampSeconds,
                selectedFrameCount: selectedFrameIndices.count,
                reason:
                    "adapted bounded relaxation after the selected frame-marker graph became fully connected",
                previousMinimumDistinctViewAngleDegrees: previousAngle,
                currentMinimumDistinctViewAngleDegrees: nextAngle,
                previousMinimumAngularSpreadDegrees: previousSpread,
                currentMinimumAngularSpreadDegrees: nextSpread,
                relaxationCount: relaxationHistory.count + 1,
                nextRelaxationSelectedFrameThreshold: nextThreshold,
                preventedFurtherRelaxationReason: changed
                    ? nil
                    : "configured lower bounds reached"
            )
        )
        return changed
    }

    private func appendTimelineSnapshots(frame: FrameObservation) {
        guard let elapsed = effectiveElapsedSeconds else {
            return
        }
        guard timeline.isEmpty ||
                elapsed + 1e-12 >= nextTimelineElapsedSeconds
        else {
            return
        }
        timeline.append(
            timelineSnapshot(
                frameIndex: frame.frameIndex,
                timestampSeconds: frame.timestampSeconds,
                elapsedSeconds: elapsed
            )
        )
        repeat {
            nextTimelineElapsedSeconds +=
                configuration.timelineIntervalSeconds
        } while nextTimelineElapsedSeconds <= elapsed + 1e-12
    }

    private func timelineSnapshot(
        frameIndex: Int,
        timestampSeconds: Double?,
        elapsedSeconds: Double?
    ) -> CaptureMaturityTimelineSnapshot {
        let markers = expectedMarkerIds.map { markerId in
            let state = state(for: markerId)
            let metrics = markerMetrics(markerId: markerId)
            return CaptureMaturityTimelineMarkerSnapshot(
                markerId: markerId,
                rawObservationCount: state.rawObservationCount,
                validObservationCount: state.validObservationCount,
                selectedDistinctViewCount:
                    state.selectedDirections.count,
                redundantViewCount: state.redundantViewCount,
                angularSpreadDegrees: metrics.angularSpreadDegrees,
                angularMeanDirectionDefined:
                    metrics.angularMeanDirectionDefined,
                coveragePercent: metrics.coveragePercent,
                maturityState: metrics.maturityState,
                progressPercent: metrics.progress.markerProgress * 100.0,
                blockingReason: metrics.blockingReason
            )
        }
        let global = globalSnapshot()
        return CaptureMaturityTimelineSnapshot(
            timestampSeconds: timestampSeconds,
            elapsedSeconds: elapsedSeconds,
            frameIndex: frameIndex,
            policy: policy.rawValue,
            mode: mode.rawValue,
            perMarker: markers,
            global: CaptureMaturityTimelineGlobalSnapshot(
                matureMarkerCount: global.matureMarkerCount,
                expectedMarkerCount: global.expectedMarkerCount,
                allMarkersMature:
                    global.matureMarkerCount == global.expectedMarkerCount &&
                    global.expectedMarkerCount > 0,
                selectedFrameCount: global.selectedFrameCount,
                selectedObservationCount: global.selectedObservationCount,
                connectivityReady: global.expectedMarkersConnected,
                optimizationTargetProgress:
                    global.optimizationTargetProgress,
                globalProgressPercent: global.globalProgressPercent,
                blockingReason: global.globalBlockingReason
            )
        )
    }

    private func markerSnapshot(
        markerId: Int
    ) -> MarkerCaptureMaturitySnapshot {
        let state = state(for: markerId)
        let metrics = markerMetrics(markerId: markerId)
        let distinctCount = state.selectedDirections.count
        let coverage = CaptureMaturityCoverage.summary(
            directions: state.selectedDirections,
            azimuthBinCount: configuration.azimuthBinCount,
            elevationBinCount: configuration.elevationBinCount,
            epsilon: configuration.vectorNormEpsilon
        )
        let nearest = CaptureMaturityViewpointMath
            .nearestAngleStatisticsDegrees(state.selectedDirections)

        let confirmedCriteria = [
            state.validObservationCount >=
                configuration.minimumValidObservationsPerMarker
                ? "configured minimum valid-frame support reached"
                : nil,
            (metrics.angularSpreadDegrees ?? -Double.infinity) + 1e-12 >=
                currentMinimumAngularSpreadDegrees
                ? "configured angular-spread target reached"
                : nil
        ].compactMap { $0 }
        let adaptedCriteria = [
            distinctCount >= configuration.minimumDistinctViewsPerMarker
                ? "replay distinct-view count reached"
                : nil,
            metrics.coveragePercent + 1e-12 >=
                configuration.requiredCoveragePercent
                ? "diagnostic spherical coverage target reached"
                : nil
        ].compactMap { $0 }
        let uncertainCriteria = [
            "the reference comparison rule against viewpoint history is unavailable",
            "the reference angular standard-deviation formula is unavailable",
            "azimuth/elevation bins are a DentalScanner diagnostic adaptation",
            metrics.angularMeanDirectionDefined
                ? nil
                : "spherical mean direction is undefined; angular spread cannot satisfy maturity"
        ].compactMap { $0 }
        let directions = state.selectedDirections.map {
            ObservationPoint3D(x: $0.x, y: $0.y, z: $0.z)
        }
        let selectedViewpoints = state.selectedViewpoints.map {
            SelectedCaptureViewpoint(
                frameIndex: $0.frameIndex,
                timestampSeconds: $0.timestampSeconds,
                cameraCenterInMarker: ObservationPoint3D(
                    x: $0.cameraCenterInMarker.x,
                    y: $0.cameraCenterInMarker.y,
                    z: $0.cameraCenterInMarker.z
                ),
                viewDirection: ObservationPoint3D(
                    x: $0.viewDirection.x,
                    y: $0.viewDirection.y,
                    z: $0.viewDirection.z
                )
            )
        }
        let rejectionReasons = state.rejectionReasons.keys.sorted {
            $0.rawValue < $1.rawValue
        }.map {
            CaptureMaturityReasonCount(
                reason: $0.rawValue,
                count: state.rejectionReasons[$0, default: 0]
            )
        }
        return MarkerCaptureMaturitySnapshot(
            markerId: markerId,
            isExpectedMarker: state.isExpected,
            rawObservationCount: state.rawObservationCount,
            policyInputObservationCount: state.policyInputObservationCount,
            validObservationCount: state.validObservationCount,
            selectedObservationCount: state.selectedObservationCount,
            selectedDistinctViewCount: distinctCount,
            redundantViewCount: state.redundantViewCount,
            frameSupportExcludedObservationCount:
                state.frameSupportExcludedObservationCount,
            rejectedObservationCount: state.rejectedObservationCount,
            rejectionReasons: rejectionReasons,
            selectedViewpoints: selectedViewpoints,
            selectedViewDirections: directions,
            minimumNearestSelectedAngleDegrees: nearest.minimum,
            meanNearestSelectedAngleDegrees: nearest.mean,
            angularSpreadDegrees: metrics.angularSpreadDegrees,
            angularMeanDirectionDefined:
                metrics.angularMeanDirectionDefined,
            coverage: coverage,
            firstObservedTimestamp: state.firstObservedTimestamp,
            firstDistinctViewTimestamp: state.firstDistinctViewTimestamp,
            maturityTimestamp: state.maturityTimestamp,
            maturityFrameIndex: state.maturityFrameIndex,
            maturityState: metrics.maturityState,
            progress: metrics.progress,
            blockingReason: metrics.blockingReason,
            confirmedCriteriaSatisfied: confirmedCriteria,
            adaptedCriteriaSatisfied: adaptedCriteria,
            uncertainCriteria: uncertainCriteria
        )
    }

    private func globalSnapshot() -> CaptureMaturityGlobalSnapshot {
        let markers = expectedMarkerIds.map { markerId in
            (
                markerId: markerId,
                state: state(for: markerId),
                metrics: markerMetrics(markerId: markerId)
            )
        }
        let matureCount = markers.filter {
            $0.metrics.maturityState == .mature
        }.count
        let connected = selectedGraph.expectedMarkersConnected(
            expectedMarkerIds
        )
        let targetProgress = min(
            Double(selectedFrameIndices.count) /
                Double(configuration.targetSelectedFrameCount),
            1
        )
        let state: GlobalCaptureMaturityState
        let blockingReason: String?
        if framesProcessed == 0 {
            state = .notStarted
            blockingReason = "no frame observations processed"
        } else if matureCount != expectedMarkerIds.count ||
                    expectedMarkerIds.isEmpty {
            state = .insufficientMarkerMaturity
            blockingReason =
                slowestMarker(from: markers)?.metrics.blockingReason ??
                "one or more expected markers are not mature"
        } else if configuration.requireExpectedMarkersConnected &&
                    !connected {
            state = .insufficientConnectivity
            blockingReason =
                "expected markers are disconnected in the selected frame-marker graph"
        } else if configuration
                    .requireSelectedFrameTargetForGlobalMaturity &&
                    selectedFrameIndices.count <
                        configuration.targetSelectedFrameCount {
            state = .insufficientSelectedFrameSupport
            blockingReason =
                "adapted selected-frame support target has not been reached"
        } else {
            state = .mature
            blockingReason = nil
        }

        let minimumMarkerProgress = markers.map {
            $0.metrics.progress.markerProgress
        }.min() ?? 0
        var progress = configuration
            .requireSelectedFrameTargetForGlobalMaturity
            ? min(minimumMarkerProgress, targetProgress)
            : minimumMarkerProgress
        if state != .mature {
            progress = min(progress, 0.99)
        } else {
            progress = 1
        }
        let slowest = slowestMarker(from: markers)
        let confirmedCriteria = [
            matureCount == expectedMarkerIds.count &&
                !expectedMarkerIds.isEmpty
                ? "all expected markers satisfy per-marker maturity"
                : nil,
            !configuration.requireExpectedMarkersConnected || connected
                ? "configured selected frame-marker connectivity satisfied"
                : nil
        ].compactMap { $0 }
        let adaptedCriteria = [
            !configuration.requireSelectedFrameTargetForGlobalMaturity ||
                selectedFrameIndices.count >=
                    configuration.targetSelectedFrameCount
                ? "adapted selected-frame support target satisfied"
                : nil
        ].compactMap { $0 }
        return CaptureMaturityGlobalSnapshot(
            firstTimestampAllMarkersMature:
                firstAllMarkersMatureTimestamp,
            frameIndexAllMarkersMature:
                firstAllMarkersMatureFrameIndex,
            firstTimestampGlobalMature:
                firstGlobalMatureTimestamp,
            frameIndexGlobalMature:
                firstGlobalMatureFrameIndex,
            slowestMarkerId: slowest?.markerId,
            slowestMarkerBlockingReason:
                slowest?.metrics.blockingReason,
            matureMarkerCount: matureCount,
            expectedMarkerCount: expectedMarkerIds.count,
            selectedFrameCount: selectedFrameIndices.count,
            selectedObservationCount: selectedObservationCount,
            optimizationTargetReachedTimestamp:
                optimizationTargetReachedTimestamp,
            optimizationTargetReachedFrameIndex:
                optimizationTargetReachedFrameIndex,
            optimizationTargetProgress: targetProgress,
            expectedMarkersConnected: connected,
            globalMaturityState: state,
            globalBlockingReason: blockingReason,
            globalProgressPercent: progress * 100.0,
            confirmedCriteriaSatisfied: confirmedCriteria,
            adaptedCriteriaSatisfied: adaptedCriteria,
            uncertainCriteria: [
                "the reference exact global progress composition is unavailable",
                configuration.requireSelectedFrameTargetForGlobalMaturity
                    ? "using the configured optimization-frame target as a hard global support gate is an explicit DentalScanner adaptation"
                    : "the configured optimization-frame target is reported but does not gate global maturity"
            ]
        )
    }

    private func slowestMarker(
        from markers: [
            (
                markerId: Int,
                state: CaptureMaturityMarkerState,
                metrics: CaptureMaturityMarkerMetrics
            )
        ]
    ) -> (
        markerId: Int,
        state: CaptureMaturityMarkerState,
        metrics: CaptureMaturityMarkerMetrics
    )? {
        markers.sorted { lhs, rhs in
            if abs(
                lhs.metrics.progress.markerProgress -
                    rhs.metrics.progress.markerProgress
            ) > 1e-12 {
                return lhs.metrics.progress.markerProgress <
                    rhs.metrics.progress.markerProgress
            }
            if lhs.metrics.maturityState == .mature,
               rhs.metrics.maturityState == .mature {
                let lhsTimestamp = lhs.state.maturityTimestamp ??
                    -Double.infinity
                let rhsTimestamp = rhs.state.maturityTimestamp ??
                    -Double.infinity
                if lhsTimestamp != rhsTimestamp {
                    return lhsTimestamp > rhsTimestamp
                }
            }
            return lhs.markerId < rhs.markerId
        }.first
    }

    private func markerMetrics(
        markerId: Int
    ) -> CaptureMaturityMarkerMetrics {
        let state = state(for: markerId)
        let distinctCount = state.selectedDirections.count
        let spread = CaptureMaturityViewpointMath.angularSpread(
            state.selectedDirections,
            epsilon: configuration.vectorNormEpsilon
        )
        let coverage = CaptureMaturityCoverage.metrics(
            directions: state.selectedDirections,
            azimuthBinCount: configuration.azimuthBinCount,
            elevationBinCount: configuration.elevationBinCount,
            epsilon: configuration.vectorNormEpsilon
        )
        let maturityState: MarkerCaptureMaturityState
        if state.rawObservationCount == 0 {
            maturityState = .notObserved
        } else if state.validObservationCount <
                    configuration.minimumValidObservationsPerMarker {
            maturityState = .insufficientValidObservations
        } else if distinctCount <
                    configuration.minimumDistinctViewsPerMarker {
            maturityState = .insufficientDistinctViews
        } else if spread.degrees == nil ||
                    (spread.degrees ?? 0) + 1e-12 <
                        currentMinimumAngularSpreadDegrees {
            maturityState = .insufficientAngularSpread
        } else if coverage.coveragePercent + 1e-12 <
                    configuration.requiredCoveragePercent {
            maturityState = .insufficientCoverage
        } else {
            maturityState = .mature
        }

        let validProgress = min(
            Double(state.validObservationCount) /
                Double(configuration.minimumValidObservationsPerMarker),
            1
        )
        let distinctProgress = min(
            Double(distinctCount) /
                Double(configuration.minimumDistinctViewsPerMarker),
            1
        )
        let spreadProgress: Double
        if currentMinimumAngularSpreadDegrees <= 0 {
            spreadProgress = 1
        } else if let degrees = spread.degrees {
            spreadProgress = min(
                degrees / currentMinimumAngularSpreadDegrees,
                1
            )
        } else {
            spreadProgress = 0
        }
        let coverageProgress = configuration.requiredCoveragePercent > 0
            ? min(
                coverage.coveragePercent /
                    configuration.requiredCoveragePercent,
                1
            )
            : 1
        var markerProgress = [
            validProgress,
            distinctProgress,
            spreadProgress,
            coverageProgress
        ].min() ?? 0
        if maturityState != .mature {
            markerProgress = min(markerProgress, 0.99)
        } else {
            markerProgress = 1
        }
        return CaptureMaturityMarkerMetrics(
            maturityState: maturityState,
            angularSpreadDegrees: spread.degrees,
            angularMeanDirectionDefined: spread.meanDirectionDefined,
            coveragePercent: coverage.coveragePercent,
            progress: CaptureMaturityProgressComponents(
                validObservationProgress: validProgress,
                distinctViewProgress: distinctProgress,
                angularSpreadProgress: spreadProgress,
                coverageProgress: coverageProgress,
                markerProgress: markerProgress
            ),
            blockingReason: maturityState == .mature
                ? nil
                : maturityState.rawValue
        )
    }

    private static func relaxationThreshold(
        target: Int,
        fraction: Double
    ) -> Int {
        max(Int(ceil(Double(max(target, 1)) * max(fraction, 0))), 1)
    }
}

struct CaptureMaturityReferenceEvidence: Codable, Equatable, Sendable {
    let concept: String
    let configuredValue: Double?
    let unit: String?
    let scope: String
    let pipelineMoment: String
    let effect: String
    let classification: CaptureMaturityEvidenceClassification
    let source: String
}

struct CaptureMaturityRelaxationPolicy: Codable, Equatable, Sendable {
    let enabled: Bool
    let halfProgressFraction: Double
    let progressStepFraction: Double
    let minimumAngularSeparationFloorDegrees: Double
    let angularSeparationFactor: Double
    let angularSpreadRelaxationStepDegrees: Double
    let minimumAngularSpreadDegrees: Double

    init(
        enabled: Bool = true,
        halfProgressFraction: Double = 0.5,
        progressStepFraction: Double = 0.25,
        minimumAngularSeparationFloorDegrees: Double = 0.1,
        angularSeparationFactor: Double = 0.8,
        angularSpreadRelaxationStepDegrees: Double = 0.25,
        minimumAngularSpreadDegrees: Double = 0.25
    ) {
        self.enabled = enabled
        self.halfProgressFraction = max(halfProgressFraction, 0)
        self.progressStepFraction = max(progressStepFraction, 0)
        self.minimumAngularSeparationFloorDegrees =
            max(minimumAngularSeparationFloorDegrees, 0)
        self.angularSeparationFactor = min(
            max(angularSeparationFactor, 0),
            1
        )
        self.angularSpreadRelaxationStepDegrees =
            max(angularSpreadRelaxationStepDegrees, 0)
        self.minimumAngularSpreadDegrees =
            max(minimumAngularSpreadDegrees, 0)
    }
}

struct CaptureMaturityReplayConfiguration: Codable, Equatable, Sendable {
    let minimumDistinctViewAngleDegrees: Double
    let minimumValidObservationsPerMarker: Int
    let minimumDistinctViewsPerMarker: Int
    let targetSelectedFrameCount: Int
    let minimumAngularSpreadDegrees: Double
    let requiredCoveragePercent: Double
    let azimuthBinCount: Int
    let elevationBinCount: Int
    let minimumObservationsPerFrame: Int
    let requireExpectedMarkersConnected: Bool
    let requireSelectedFrameTargetForGlobalMaturity: Bool
    let timelineIntervalSeconds: Double
    let strictSelectionStrategy: CaptureMaturitySelectionStrategy
    let referenceLikeSelectionStrategy: CaptureMaturitySelectionStrategy
    let rotationOrthogonalityTolerance: Double
    let rotationDeterminantTolerance: Double
    let vectorNormEpsilon: Double
    let relaxationPolicy: CaptureMaturityRelaxationPolicy
    let referenceEvidence: [CaptureMaturityReferenceEvidence]

    init(
        minimumDistinctViewAngleDegrees: Double = 1.5,
        minimumValidObservationsPerMarker: Int = 65,
        minimumDistinctViewsPerMarker: Int = 65,
        targetSelectedFrameCount: Int = 300,
        minimumAngularSpreadDegrees: Double = 4.5,
        requiredCoveragePercent: Double = 0,
        azimuthBinCount: Int = 12,
        elevationBinCount: Int = 6,
        minimumObservationsPerFrame: Int = 1,
        requireExpectedMarkersConnected: Bool = true,
        requireSelectedFrameTargetForGlobalMaturity: Bool = true,
        timelineIntervalSeconds: Double = 0.5,
        strictSelectionStrategy: CaptureMaturitySelectionStrategy =
            .perMarkerObservation,
        referenceLikeSelectionStrategy: CaptureMaturitySelectionStrategy =
            .wholeFrameWhenAnyMarkerHasDistinctView,
        rotationOrthogonalityTolerance: Double = 1e-5,
        rotationDeterminantTolerance: Double = 1e-5,
        vectorNormEpsilon: Double = 1e-9,
        relaxationPolicy: CaptureMaturityRelaxationPolicy =
            CaptureMaturityRelaxationPolicy(),
        referenceEvidence: [CaptureMaturityReferenceEvidence] =
            CaptureMaturityReferenceEvidence.authorizedReferenceDefaults
    ) {
        self.minimumDistinctViewAngleDegrees =
            max(minimumDistinctViewAngleDegrees, 0)
        self.minimumValidObservationsPerMarker =
            max(minimumValidObservationsPerMarker, 1)
        self.minimumDistinctViewsPerMarker =
            max(minimumDistinctViewsPerMarker, 1)
        self.targetSelectedFrameCount = max(targetSelectedFrameCount, 1)
        self.minimumAngularSpreadDegrees =
            max(minimumAngularSpreadDegrees, 0)
        self.requiredCoveragePercent = min(max(requiredCoveragePercent, 0), 100)
        self.azimuthBinCount = max(azimuthBinCount, 1)
        self.elevationBinCount = max(elevationBinCount, 1)
        self.minimumObservationsPerFrame = max(minimumObservationsPerFrame, 1)
        self.requireExpectedMarkersConnected = requireExpectedMarkersConnected
        self.requireSelectedFrameTargetForGlobalMaturity =
            requireSelectedFrameTargetForGlobalMaturity
        self.timelineIntervalSeconds = max(timelineIntervalSeconds, 0.01)
        self.strictSelectionStrategy = strictSelectionStrategy
        self.referenceLikeSelectionStrategy = referenceLikeSelectionStrategy
        self.rotationOrthogonalityTolerance =
            max(rotationOrthogonalityTolerance, 0)
        self.rotationDeterminantTolerance =
            max(rotationDeterminantTolerance, 0)
        self.vectorNormEpsilon = max(vectorNormEpsilon, 1e-12)
        self.relaxationPolicy = relaxationPolicy
        self.referenceEvidence = referenceEvidence
    }
}

extension CaptureMaturityReferenceEvidence {
    static let authorizedReferenceDefaults: [CaptureMaturityReferenceEvidence] = [
        value(
            "minimum angular separation",
            1.5,
            "degrees",
            "per marker viewpoint history",
            "frame validity/diversity assessment",
            "separates a new viewpoint from retained viewpoints",
            .confirmedByConfiguration,
            "CommonConfig.json AngleDiversityConfig.kMinAngularSeparationDeg"
        ),
        value(
            "target angular standard deviation",
            4.5,
            "degrees",
            "per marker",
            "capture progress/diversity",
            "target dispersion; exact formula is not exposed",
            .confirmedByConfiguration,
            "CommonConfig.json AngleDiversityConfig.kTargetAngularStdDeg"
        ),
        value(
            "minimum valid frames",
            65,
            "frames per marker",
            "per marker",
            "capture validity/progress",
            "minimum retained valid-frame support",
            .confirmedByConfiguration,
            "CommonConfig.json MarkerConfig.kMinValidFramesPerMarker"
        ),
        value(
            "progress marker count",
            3,
            "markers",
            "per frame/session",
            "capture progress",
            "configured marker support count; the exact acceptance expression is unavailable and is not transplanted into DentalScanner",
            .confirmedByConfiguration,
            "CommonConfig.json MarkerConfig.kProgressMarkerCount"
        ),
        value(
            "optimization marker count",
            2,
            "markers",
            "per frame",
            "optimization-frame retention",
            "configured support count with strong indication that partial-marker frames may be retained; not transplanted into DentalScanner",
            .confirmedByConfiguration,
            "CommonConfig.json MarkerConfig.kOptimizationMarkerCount"
        ),
        value(
            "optimization frame target",
            300,
            "frames",
            "session/global",
            "progress hold/optimization preparation",
            "target support; it is not sufficient by itself for maturity",
            .confirmedByConfiguration,
            "CommonConfig.json ProgressHoldConfig.kTargetOptFrames"
        ),
        value(
            "half-progress fraction",
            0.5,
            "fraction",
            "session/global",
            "dynamic progress logic",
            "participates in bounded dynamic behavior; exact call semantics unavailable",
            .confirmedByConfiguration,
            "CommonConfig.json AngleDiversityConfig.kHalfProgressFraction"
        ),
        value(
            "dynamic progress step",
            0.25,
            "fraction",
            "session/global",
            "dynamic progress logic",
            "participates in bounded dynamic behavior; exact call semantics unavailable",
            .confirmedByConfiguration,
            "CommonConfig.json AngleDiversityConfig.kDynamicStepUpFactor"
        ),
        value(
            "minimum dynamic angular step",
            0.1,
            "degrees",
            "dynamic threshold",
            "dynamic progress logic",
            "bounded minimum used only by the adapted REFERENCE_LIKE mode",
            .confirmedByConfiguration,
            "CommonConfig.json AngleDiversityConfig.kDynamicStepUpMinDeg"
        ),
        value(
            "angular spread relaxation margin",
            0.25,
            "degrees",
            "dynamic threshold",
            "progress relaxation",
            "bounded decrement used only by the adapted REFERENCE_LIKE mode",
            .confirmedByConfiguration,
            "CommonConfig.json AngleDiversityConfig.kStdRelaxMarginDeg"
        ),
        value(
            "dynamic relaxation factor",
            0.8,
            "factor",
            "dynamic threshold",
            "progress relaxation",
            "bounded multiplier used only by the adapted REFERENCE_LIKE mode",
            .confirmedByConfiguration,
            "CommonConfig.json AngleDiversityConfig.kDynamicRelaxFactor"
        ),
        value(
            "progress hold start",
            1.0,
            "Percent-named configuration unit",
            "session/global",
            "progress hold",
            "configured boundary; exact scale and call semantics are unavailable and are not transplanted",
            .confirmedByConfiguration,
            "CommonConfig.json ProgressHoldConfig.kHoldStartPercent"
        ),
        value(
            "progress hold interval",
            1.0,
            "Percent-named configuration unit",
            "session/global",
            "progress hold",
            "configured update interval; exact scale and call semantics are unavailable and are not transplanted",
            .confirmedByConfiguration,
            "CommonConfig.json ProgressHoldConfig.kHoldIntervalPercent"
        ),
        symbol(
            "frame-level validity and diversity assessment",
            "frame and frame-container",
            "before capture progress/optimization",
            "distinguishes a raw frame from a valid/diverse frame",
            "TM::Record::AssessFrameValidity, TM::Record::IsDiversityValid"
        ),
        symbol(
            "per-marker angular dispersion",
            "per marker",
            "capture progress",
            "computes an angular standard-deviation diagnostic",
            "TM::Record::ComputeAngularStdDeg"
        ),
        symbol(
            "bounded progress relaxation after connectivity",
            "session/global",
            "capture progress",
            "relaxes a progress threshold only after full connectivity",
            "TM::Record::RelaxProgressThresholdIfFullyConnected"
        ),
        symbol(
            "optimization consumes a frame container",
            "session/frame-marker graph",
            "offline optimization",
            "preserves frame identity through optimization",
            "TM::OptimizeLogic::Run(FrameContainer, baseMarkerId)"
        )
    ]

    private static func value(
        _ concept: String,
        _ configuredValue: Double,
        _ unit: String,
        _ scope: String,
        _ pipelineMoment: String,
        _ effect: String,
        _ classification: CaptureMaturityEvidenceClassification,
        _ source: String
    ) -> CaptureMaturityReferenceEvidence {
        CaptureMaturityReferenceEvidence(
            concept: concept,
            configuredValue: configuredValue,
            unit: unit,
            scope: scope,
            pipelineMoment: pipelineMoment,
            effect: effect,
            classification: classification,
            source: source
        )
    }

    private static func symbol(
        _ concept: String,
        _ scope: String,
        _ pipelineMoment: String,
        _ effect: String,
        _ source: String
    ) -> CaptureMaturityReferenceEvidence {
        CaptureMaturityReferenceEvidence(
            concept: concept,
            configuredValue: nil,
            unit: nil,
            scope: scope,
            pipelineMoment: pipelineMoment,
            effect: effect,
            classification: .confirmedBySymbol,
            source: source
        )
    }
}

struct MarkerViewpointObservation: Equatable, Sendable {
    let frameIndex: Int
    let timestampSeconds: Double?
    let markerId: Int
    let cameraCenterInMarker: SIMD3<Double>
    let viewDirection: SIMD3<Double>
}

struct CaptureMaturityAngularSpreadResult: Equatable, Sendable {
    let degrees: Double?
    let meanDirectionDefined: Bool
}

enum CaptureMaturityViewpointMath {
    static func viewpoint(
        frameIndex: Int,
        timestampSeconds: Double?,
        pose: PoseResult,
        configuration: CaptureMaturityReplayConfiguration
    ) -> Result<MarkerViewpointObservation, CaptureMaturityObservationRejectReason> {
        let rotation = pose.rotationMatrix
        guard PoseMath.isFinite(rotation) else {
            return .failure(.nonFiniteRotation)
        }
        guard isOrthonormal(
            rotation,
            tolerance: configuration.rotationOrthogonalityTolerance
        ) else {
            return .failure(.nonOrthonormalRotation)
        }
        let determinant = simd_determinant(rotation)
        guard determinant.isFinite,
              abs(determinant - 1.0) <=
                configuration.rotationDeterminantTolerance
        else {
            return .failure(.invalidRotationDeterminant)
        }
        guard PoseMath.isFinite(pose.translationVector) else {
            return .failure(.nonFiniteTranslation)
        }

        let cameraCenter = -(simd_transpose(rotation) * pose.translationVector)
        let norm = simd_length(cameraCenter)
        guard norm.isFinite, norm > configuration.vectorNormEpsilon else {
            return .failure(.zeroCameraCenterNorm)
        }
        let direction = cameraCenter / norm
        guard PoseMath.isFinite(direction) else {
            return .failure(.zeroCameraCenterNorm)
        }
        return .success(
            MarkerViewpointObservation(
                frameIndex: frameIndex,
                timestampSeconds: timestampSeconds,
                markerId: pose.markerId,
                cameraCenterInMarker: cameraCenter,
                viewDirection: direction
            )
        )
    }

    static func angularDistanceRadians(
        _ lhs: SIMD3<Double>,
        _ rhs: SIMD3<Double>
    ) -> Double {
        angleRadians(fromDotProduct: simd_dot(lhs, rhs))
    }

    static func angularDistanceDegrees(
        _ lhs: SIMD3<Double>,
        _ rhs: SIMD3<Double>
    ) -> Double {
        angularDistanceRadians(lhs, rhs) * 180.0 / Double.pi
    }

    static func angleRadians(fromDotProduct dotProduct: Double) -> Double {
        acos(min(max(dotProduct, -1.0), 1.0))
    }

    static func normalized(
        _ vector: SIMD3<Double>,
        epsilon: Double = 1e-9
    ) -> SIMD3<Double>? {
        guard PoseMath.isFinite(vector) else { return nil }
        let norm = simd_length(vector)
        guard norm.isFinite, norm > epsilon else { return nil }
        return vector / norm
    }

    static func angularSpreadDegrees(
        _ directions: [SIMD3<Double>],
        epsilon: Double = 1e-9
    ) -> Double? {
        angularSpread(directions, epsilon: epsilon).degrees
    }

    static func angularSpread(
        _ directions: [SIMD3<Double>],
        epsilon: Double = 1e-9
    ) -> CaptureMaturityAngularSpreadResult {
        guard !directions.isEmpty else {
            return CaptureMaturityAngularSpreadResult(
                degrees: 0,
                meanDirectionDefined: false
            )
        }
        let sum = directions.reduce(SIMD3<Double>.zero, +)
        guard let meanDirection = normalized(sum, epsilon: epsilon) else {
            return CaptureMaturityAngularSpreadResult(
                degrees: nil,
                meanDirectionDefined: false
            )
        }
        let squared = directions.reduce(0.0) { partial, direction in
            let radians = angularDistanceRadians(direction, meanDirection)
            return partial + radians * radians
        }
        return CaptureMaturityAngularSpreadResult(
            degrees:
                sqrt(squared / Double(directions.count)) *
                180.0 / Double.pi,
            meanDirectionDefined: true
        )
    }

    static func nearestAngleStatisticsDegrees(
        _ directions: [SIMD3<Double>]
    ) -> (minimum: Double?, mean: Double?) {
        guard directions.count >= 2 else { return (nil, nil) }
        var nearest: [Double] = []
        nearest.reserveCapacity(directions.count)
        for index in directions.indices {
            var closest = Double.infinity
            for otherIndex in directions.indices where otherIndex != index {
                closest = min(
                    closest,
                    angularDistanceDegrees(
                        directions[index],
                        directions[otherIndex]
                    )
                )
            }
            if closest.isFinite {
                nearest.append(closest)
            }
        }
        guard !nearest.isEmpty else { return (nil, nil) }
        return (
            nearest.min(),
            nearest.reduce(0, +) / Double(nearest.count)
        )
    }

    private static func isOrthonormal(
        _ matrix: simd_double3x3,
        tolerance: Double
    ) -> Bool {
        let gram = simd_transpose(matrix) * matrix
        for row in 0..<3 {
            for column in 0..<3 {
                let expected = row == column ? 1.0 : 0.0
                let delta = abs(
                    PoseMath.matrixElement(
                        gram,
                        row: row,
                        column: column
                    ) - expected
                )
                if !delta.isFinite || delta > tolerance {
                    return false
                }
            }
        }
        return true
    }
}

private struct CaptureMaturityAssociatedDiagnostics: Decodable {
    struct Event: Decodable {
        let name: String
        let timestampSeconds: Double
    }

    let scanDurationSeconds: Double?
    let timeToAllMarkersSeenSeconds: Double?
    let timeToAllMarkersExportableSeconds: Double?
    let normalFinalizationStartedAtSeconds: Double?
    let events: [Event]?
}

enum ScanSessionCaptureMaturityReplayError: Error, LocalizedError {
    case policyMetadataMismatch
    case analyzerMetadataUnavailable

    var errorDescription: String? {
        switch self {
        case .policyMetadataMismatch:
            return "ALL and FILTERED maturity passes read different session metadata."
        case .analyzerMetadataUnavailable:
            return "Capture maturity analyzer metadata was not initialized."
        }
    }
}

final class ScanSessionCaptureMaturityReplayRunner {
    static let artifactSchemaVersion = 1
    static let algorithmIdentifier =
        "DentalScanner.captureMaturity.frameIndexed.v1"

    private let readerFactory: () -> ScanSessionSchemaV1Reader
    private let configuration: CaptureMaturityReplayConfiguration
    private let includeReferenceLikeMode: Bool

    init(
        readerFactory: @escaping () -> ScanSessionSchemaV1Reader = {
            ScanSessionSchemaV1Reader()
        },
        configuration: CaptureMaturityReplayConfiguration =
            CaptureMaturityReplayConfiguration(),
        includeReferenceLikeMode: Bool = true
    ) {
        self.readerFactory = readerFactory
        self.configuration = configuration
        self.includeReferenceLikeMode = includeReferenceLikeMode
    }

    func run(
        sessionFileURL: URL,
        diagnosticsFileURL: URL? = nil,
        reportFileURL: URL? = nil,
        options: ScanSessionReplayOptions = .deterministic
    ) throws -> CaptureMaturityReplayResult {
        let all = try runPolicy(
            .all,
            sessionFileURL: sessionFileURL,
            options: options
        )
        let filtered = try runPolicy(
            .filtered,
            sessionFileURL: sessionFileURL,
            options: options
        )
        guard all.readSummary.metadata == filtered.readSummary.metadata,
              all.readSummary.footer == filtered.readSummary.footer,
              all.readSummary.framesRead == filtered.readSummary.framesRead
        else {
            throw ScanSessionCaptureMaturityReplayError
                .policyMetadataMismatch
        }

        let metadata = all.readSummary.metadata
        let actualComparison = actualProgressComparison(
            progressArtifactURL:
                availableProgressArtifactURL(
                    diagnosticsFileURL: diagnosticsFileURL,
                    reportFileURL: reportFileURL
                ),
            metadata: metadata,
            readSummary: all.readSummary,
            all: all.summary,
            filtered: filtered.summary
        )
        let missingAnnotations =
            filtered.readSummary.selectionDiagnostics
                .missingGateEvaluationCount +
            filtered.readSummary.selectionDiagnostics
                .missingGateDecisionCount
        var caveats = [
            "capture maturity replay is offline diagnostics only and does not change live progress, readiness, accumulation, finalization, or export",
            "T_cm is interpreted as camera-from-marker from the production solvePnP/projectPoints path",
            "65 valid observations, 1.5 degrees, 4.5 degrees, and 300 selected frames originate in authorized reference configuration, but their exact reference composition formula is unavailable",
            "the replay maps the configured valid-frame count to replay-valid marker observations; this is an explicit DentalScanner adaptation",
            "spherical RMS spread and azimuth/elevation coverage bins are DentalScanner diagnostic adaptations",
            "REFERENCE_LIKE relaxation is a bounded adaptation informed by configuration and symbols; it is not claimed to reproduce unavailable encrypted implementation",
            "the optimization-frame target is treated as global support and never creates maturity by itself",
            "capture maturity and future bundle adjustment frame selection remain separate decisions"
        ]
        if metadata.appGitCommitHash == nil {
            caveats.append(
                "capture appGitCommitHash is unavailable; current development HEAD was not substituted"
            )
        }
        if missingAnnotations > 0 {
            caveats.append(
                "\(missingAnnotations) missing persisted Pre-Gate annotations were diagnosed and excluded from FILTERED without inference"
            )
        }
        caveats.append(contentsOf: actualComparison.caveats)

        return CaptureMaturityReplayResult(
            summary: CaptureMaturityReplaySummary(
                artifactSchemaVersion: Self.artifactSchemaVersion,
                algorithmIdentifier: Self.algorithmIdentifier,
                sourceSessionFilename: sessionFileURL.lastPathComponent,
                sessionIdentifier: metadata.sessionIdentifier,
                sourceSessionSchemaVersion: metadata.schemaVersion,
                appVersion: metadata.appVersion,
                appBuildIdentifier: metadata.appBuildIdentifier,
                appGitCommitHash: metadata.appGitCommitHash,
                deviceModelIdentifier: metadata.deviceModelIdentifier,
                osVersion: metadata.osVersion,
                cameraProfileId: metadata.cameraProfileId,
                cameraProfileName: metadata.cameraProfileName,
                markerProfile: metadata.markerProfile,
                expectedPhysicalMarkerIds:
                    Array(Set(metadata.expectedPhysicalMarkerIds)).sorted(),
                poseConvention:
                    "T_cm: p_camera = R_cm * p_marker + t_cm",
                viewpointConvention:
                    "cameraCenterInMarker = -transpose(R_cm) * t_cm; viewDirection = normalize(cameraCenterInMarker)",
                angleUnit: "degrees (internal trigonometry uses radians)",
                configuration: configuration,
                all: all.summary,
                filtered: filtered.summary,
                actualProgressComparison: actualComparison,
                integrityResult: missingAnnotations == 0
                    ? "valid"
                    : "validWithMissingGateAnnotations",
                provenanceCaveats: Array(Set(caveats)).sorted()
            )
        )
    }

    private struct PolicyRun {
        let summary: CaptureMaturityPolicyReplaySummary
        let readSummary: ScanSessionReplayReadSummary
    }

    private func runPolicy(
        _ policy: CaptureMaturityObservationPolicy,
        sessionFileURL: URL,
        options: ScanSessionReplayOptions
    ) throws -> PolicyRun {
        var strictAnalyzer: CaptureMaturitySessionAnalyzer?
        var referenceLikeAnalyzer: CaptureMaturitySessionAnalyzer?
        let readSummary = try readerFactory().readObservationFrames(
            from: sessionFileURL,
            options: options,
            observationPolicy: policy.replayPolicy,
            missingGateAnnotationBehavior: .diagnoseAndExclude,
            onMetadata: { metadata in
                strictAnalyzer = CaptureMaturitySessionAnalyzer(
                    metadata: metadata,
                    policy: policy,
                    mode: .strict,
                    configuration: configuration
                )
                if includeReferenceLikeMode {
                    referenceLikeAnalyzer =
                        CaptureMaturitySessionAnalyzer(
                            metadata: metadata,
                            policy: policy,
                            mode: .referenceLike,
                            configuration: configuration
                        )
                }
            },
            onFrame: { frame in
                strictAnalyzer?.process(frame)
                referenceLikeAnalyzer?.process(frame)
            }
        )
        guard let strictAnalyzer else {
            throw ScanSessionCaptureMaturityReplayError
                .analyzerMetadataUnavailable
        }
        let diagnostics = readSummary.selectionDiagnostics
        return PolicyRun(
            summary: CaptureMaturityPolicyReplaySummary(
                policy: policy.rawValue,
                strict: strictAnalyzer.makeSummary(),
                referenceLike: referenceLikeAnalyzer?.makeSummary(),
                readerSelectionDiagnostics: diagnostics,
                missingGateEvaluationCount:
                    diagnostics.missingGateEvaluationCount,
                missingGateDecisionCount:
                    diagnostics.missingGateDecisionCount
            ),
            readSummary: readSummary
        )
    }

    private func actualProgressComparison(
        progressArtifactURL: URL?,
        metadata: ScanSessionReplayCaptureMetadata,
        readSummary: ScanSessionReplayReadSummary,
        all: CaptureMaturityPolicyReplaySummary,
        filtered: CaptureMaturityPolicyReplaySummary
    ) -> CaptureMaturityActualProgressComparison {
        guard let progressArtifactURL,
              FileManager.default.fileExists(
                atPath: progressArtifactURL.path
              )
        else {
            return comparisonUnavailable(
                caveat: "associated diagnostics/report timing artifact was not available"
            )
        }

        let diagnostics: CaptureMaturityAssociatedDiagnostics
        do {
            diagnostics = try JSONDecoder().decode(
                CaptureMaturityAssociatedDiagnostics.self,
                from: Data(contentsOf: progressArtifactURL)
            )
        } catch {
            return comparisonUnavailable(
                filename: progressArtifactURL.lastPathComponent,
                caveat:
                    "associated diagnostics/report timing artifact could not be decoded: \(error.localizedDescription)"
            )
        }

        let events = diagnostics.events ?? []
        let finalizationStarted = events
            .filter { $0.name == "normal_finalization_started" }
            .map(\.timestampSeconds)
            .filter { $0.isFinite }
            .min() ?? finite(diagnostics.normalFinalizationStartedAtSeconds)
        let exportTriggered = events
            .filter { $0.name == "normal_finalization_export_triggered" }
            .map(\.timestampSeconds)
            .filter { $0.isFinite }
            .min()
        var caveats = [
            "diagnostics timestamps are relative to scan start; offline frame timestamps are converted relative to sessionHeader.captureStartedTimestamp",
            "actualUI100PercentTimestamp uses the first normal_finalization_started event because that transition requires all expected markers at 100 percent and exportable poses",
            "actualExportTriggeredTimestamp is an export trigger, not verified file-write completion",
            "actualExportTimestamp is unavailable in the current associated timing schemas"
        ]
        if progressArtifactURL.lastPathComponent.hasSuffix("_report.json") {
            caveats.append(
                "associated technical report is a partial fallback and may omit detailed timing events present in diagnostics"
            )
        } else {
            caveats.append(
                "diagnostic event history is bounded and may omit an earlier normal_finalization_started event"
            )
        }
        let timestampsShareClockDomain = captureTimestampAlignmentIsPlausible(
            metadata: metadata,
            readSummary: readSummary,
            scanDurationSeconds: diagnostics.scanDurationSeconds
        )
        if !timestampsShareClockDomain {
            caveats.append(
                "sessionHeader.captureStartedTimestamp and frame timestamps do not have a plausible shared clock domain; offline-to-live timestamp deltas were omitted"
            )
        }
        let strictElapsed = elapsedTimestamp(
            all.strict.globalMaturity.firstTimestampGlobalMature,
            captureStartedTimestamp: metadata.captureStartedTimestamp,
            timestampsShareClockDomain: timestampsShareClockDomain,
            caveats: &caveats
        )
        let referenceLikeElapsed = elapsedTimestamp(
            all.referenceLike?.globalMaturity
                .firstTimestampGlobalMature,
            captureStartedTimestamp: metadata.captureStartedTimestamp,
            timestampsShareClockDomain: timestampsShareClockDomain,
            caveats: &caveats
        )
        let filteredStrictElapsed = elapsedTimestamp(
            filtered.strict.globalMaturity
                .firstTimestampGlobalMature,
            captureStartedTimestamp: metadata.captureStartedTimestamp,
            timestampsShareClockDomain: timestampsShareClockDomain,
            caveats: &caveats
        )
        let allMarkersSeen = finite(
            diagnostics.timeToAllMarkersSeenSeconds
        )
        let allMarkersExportable = finite(
            diagnostics.timeToAllMarkersExportableSeconds
        )
        return CaptureMaturityActualProgressComparison(
            comparisonStatus: "availableWithCaveats",
            sourceProgressArtifactFilename:
                progressArtifactURL.lastPathComponent,
            actualAllMarkersSeenTimestamp: allMarkersSeen,
            actualAllMarkersExportableTimestamp: allMarkersExportable,
            actualUI100PercentTimestamp: finalizationStarted,
            actualFinalizationStartedTimestamp: finalizationStarted,
            actualExportTriggeredTimestamp: exportTriggered,
            actualExportTimestamp: nil,
            offlineStrictMaturityTimestamp: strictElapsed,
            offlineReferenceLikeMaturityTimestamp:
                referenceLikeElapsed,
            filteredOfflineStrictMaturityTimestamp:
                filteredStrictElapsed,
            ui100ToStrictMaturityDeltaSeconds: delta(
                from: finalizationStarted,
                to: strictElapsed
            ),
            exportableToStrictMaturityDeltaSeconds: delta(
                from: allMarkersExportable,
                to: strictElapsed
            ),
            strictMaturityReachedBeforeExport: compareBefore(
                strictElapsed,
                exportTriggered
            ),
            caveats: caveats.sorted()
        )
    }

    private func comparisonUnavailable(
        filename: String? = nil,
        caveat: String
    ) -> CaptureMaturityActualProgressComparison {
        CaptureMaturityActualProgressComparison(
            comparisonStatus: "unavailable",
            sourceProgressArtifactFilename: filename,
            actualAllMarkersSeenTimestamp: nil,
            actualAllMarkersExportableTimestamp: nil,
            actualUI100PercentTimestamp: nil,
            actualFinalizationStartedTimestamp: nil,
            actualExportTriggeredTimestamp: nil,
            actualExportTimestamp: nil,
            offlineStrictMaturityTimestamp: nil,
            offlineReferenceLikeMaturityTimestamp: nil,
            filteredOfflineStrictMaturityTimestamp: nil,
            ui100ToStrictMaturityDeltaSeconds: nil,
            exportableToStrictMaturityDeltaSeconds: nil,
            strictMaturityReachedBeforeExport: nil,
            caveats: [caveat]
        )
    }

    private func elapsedTimestamp(
        _ timestamp: Double?,
        captureStartedTimestamp: Double,
        timestampsShareClockDomain: Bool,
        caveats: inout [String]
    ) -> Double? {
        guard timestampsShareClockDomain else { return nil }
        guard let timestamp,
              timestamp.isFinite,
              captureStartedTimestamp.isFinite
        else {
            return nil
        }
        let elapsed = timestamp - captureStartedTimestamp
        guard elapsed >= -0.5 else {
            caveats.append(
                "an offline maturity timestamp preceded captureStartedTimestamp and was excluded from actual-progress comparison"
            )
            return nil
        }
        return max(elapsed, 0)
    }

    private func captureTimestampAlignmentIsPlausible(
        metadata: ScanSessionReplayCaptureMetadata,
        readSummary: ScanSessionReplayReadSummary,
        scanDurationSeconds: Double?
    ) -> Bool {
        guard metadata.captureStartedTimestamp.isFinite,
              let first = readSummary.firstTimestampSeconds,
              let last = readSummary.lastTimestampSeconds,
              first.isFinite,
              last.isFinite,
              last >= first
        else {
            return false
        }
        let firstDelta = first - metadata.captureStartedTimestamp
        let observedDuration = last - first
        let durationAllowance = max(
            finite(scanDurationSeconds) ?? observedDuration,
            observedDuration
        ) + 10
        return firstDelta >= -0.5 &&
            firstDelta <= durationAllowance
    }

    private func finite(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return value
    }

    private func delta(from start: Double?, to end: Double?) -> Double? {
        guard let start, let end else { return nil }
        return end - start
    }

    private func compareBefore(
        _ lhs: Double?,
        _ rhs: Double?
    ) -> Bool? {
        guard let lhs, let rhs else { return nil }
        return lhs <= rhs
    }

    private func availableProgressArtifactURL(
        diagnosticsFileURL: URL?,
        reportFileURL: URL?
    ) -> URL? {
        if let diagnosticsFileURL,
           FileManager.default.fileExists(atPath: diagnosticsFileURL.path) {
            return diagnosticsFileURL
        }
        if let reportFileURL,
           FileManager.default.fileExists(atPath: reportFileURL.path) {
            return reportFileURL
        }
        return nil
    }
}
