import Foundation

struct ScanDiagnosticEvent: Codable, Equatable, Identifiable {
    let id: UUID
    let name: String
    let timestampSeconds: Double
    let markerId: Int?
    let message: String?
    let metadata: [String: String]?

    init(
        name: String,
        timestampSeconds: Double,
        markerId: Int? = nil,
        message: String? = nil,
        metadata: [String: String]? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.timestampSeconds = timestampSeconds
        self.markerId = markerId
        self.message = message
        self.metadata = metadata?.isEmpty == true ? nil : metadata
    }
}

struct ScanDiagnosticsSnapshot: Codable, Equatable {
    var createdAt: String?
    var markerProfile: String?
    var scanDurationSeconds: Double?
    var timeToFirstMarkerSeconds: Double?
    var timeToAllMarkersSeenSeconds: Double?
    var timeToAllMarkersExportableSeconds: Double?
    var extraTimeAfterAllMarkers100PercentSeconds: Double?
    var fpsMean: Double?
    var fpsMin: Double?
    var framesProcessed: Int
    var framesAccepted: Int
    var framesRejectedByFocus: Int
    var framesRejectedByBlur: Int
    var framesRejectedByMotion: Int
    var framesRejectedByNormal: Int
    var framesRejectedByReprojection: Int
    var exportGateReason: String?
    var scanConfidence: String?
    var mainIssue: String?
    var focusRecoveryState: String?
    var focusRecoveryCount: Int
    var arucoLostCount: Int
    var centerFocusRecoveryCount: Int
    var distanceGuideState: String?
    var lastDistanceMm: Double?
    var distanceValidPercent: Double?
    var guidedStaticCaptureEnabled: Bool
    var guidedStages: [GuidedStageSummary]?
    var slowestMarkerId: Int?
    var currentBlockingReason: String?
    var lastEventName: String?
    var eventsCount: Int
    var events: [ScanDiagnosticEvent]
    var markers: [MarkerSummary]

    static let empty = ScanDiagnosticsSnapshot(
        createdAt: nil,
        markerProfile: nil,
        scanDurationSeconds: nil,
        timeToFirstMarkerSeconds: nil,
        timeToAllMarkersSeenSeconds: nil,
        timeToAllMarkersExportableSeconds: nil,
        extraTimeAfterAllMarkers100PercentSeconds: nil,
        fpsMean: nil,
        fpsMin: nil,
        framesProcessed: 0,
        framesAccepted: 0,
        framesRejectedByFocus: 0,
        framesRejectedByBlur: 0,
        framesRejectedByMotion: 0,
        framesRejectedByNormal: 0,
        framesRejectedByReprojection: 0,
        exportGateReason: nil,
        scanConfidence: nil,
        mainIssue: nil,
        focusRecoveryState: nil,
        focusRecoveryCount: 0,
        arucoLostCount: 0,
        centerFocusRecoveryCount: 0,
        distanceGuideState: nil,
        lastDistanceMm: nil,
        distanceValidPercent: nil,
        guidedStaticCaptureEnabled: false,
        guidedStages: nil,
        slowestMarkerId: nil,
        currentBlockingReason: nil,
        lastEventName: nil,
        eventsCount: 0,
        events: [],
        markers: []
    )

    struct MarkerSummary: Codable, Equatable, Identifiable {
        let markerId: Int
        var firstSeenAtSeconds: Double?
        var becameExportableAtSeconds: Double?
        var totalVisibleSeconds: Double?
        var observationsAccumulated: Int
        var finalObservationsUsed: Int?
        var qualityScore: Double?
        var normalStdDegrees: Double?
        var reprojectionError: Double?
        var exportable: Bool
        var invalidReason: String?
        var waitingReason: String?

        var id: Int {
            markerId
        }
    }

    struct GuidedStageSummary: Codable, Equatable {
        var stageName: String
        var framesAccepted: Int
        var framesRejectedByFocus: Int
        var framesRejectedByMotion: Int
        var framesRejectedByNormal: Int
        var framesRejectedByReprojection: Int
        var markersSeen: [Int]?
        var markersAccepted: [Int]?
        var normalStdDegreesMean: Double?
    }
}

struct DiagnosticsExportBundle: Codable, Equatable {
    var stlFileName: String?
    var reportFileName: String?
    var diagnosticsFileName: String?
}

protocol CrashReportingService {
    func record(error: Error, context: [String: String])
    func record(message: String, context: [String: String])
}

struct NoopCrashReportingService: CrashReportingService {
    func record(error: Error, context: [String: String]) {}
    func record(message: String, context: [String: String]) {}
}
