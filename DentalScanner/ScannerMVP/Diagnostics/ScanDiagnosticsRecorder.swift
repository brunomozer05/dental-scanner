import Foundation

final class ScanDiagnosticsRecorder {
    private struct MarkerState {
        var firstSeenAt: Double?
        var lastSeenAt: Double?
        var totalVisibleSeconds: Double = 0
        var becameExportableAt: Double?
        var observationsAccumulated: Int = 0
        var finalObservationsUsed: Int?
        var qualityScore: Double?
        var normalStdDegrees: Double?
        var reprojectionError: Double?
        var exportable: Bool = false
        var invalidReason: String?
        var waitingReason: String?
    }

    private let maxEvents: Int
    private var events: [ScanDiagnosticEvent] = []
    private var markerStates: [Int: MarkerState] = [:]
    private var scanStartedAt: Double?
    private var createdAt: String?
    private var markerProfile: String?
    private var allMarkersSeenAt: Double?
    private var allMarkersExportableAt: Double?
    private var firstMarkerSeenAt: Double?
    private var fpsSum: Double = 0
    private var fpsSampleCount: Int = 0
    private var fpsMinValue: Double?
    private var distanceSampleCount: Int = 0
    private var distanceValidSampleCount: Int = 0
    private var lastDistanceState: String?
    private var lastFocusStable: Bool?
    private var didRecordFPSDrop = false
    private(set) var lastSnapshot: ScanDiagnosticsSnapshot = .empty

    init(maxEvents: Int = 500) {
        self.maxEvents = max(10, maxEvents)
    }

    func startScan(
        markerProfile: String,
        expectedMarkerIds: [Int],
        timestamp: Double,
        createdAt: String
    ) {
        events = []
        markerStates = [:]
        scanStartedAt = sanitizedTimestamp(timestamp)
        self.createdAt = createdAt
        self.markerProfile = markerProfile
        allMarkersSeenAt = nil
        allMarkersExportableAt = nil
        firstMarkerSeenAt = nil
        fpsSum = 0
        fpsSampleCount = 0
        fpsMinValue = nil
        distanceSampleCount = 0
        distanceValidSampleCount = 0
        lastDistanceState = nil
        lastFocusStable = nil
        didRecordFPSDrop = false
        lastSnapshot = .empty

        for markerId in expectedMarkerIds {
            markerStates[markerId] = MarkerState()
        }

        record(
            name: "scan_started",
            timestamp: timestamp,
            metadata: ["markerProfile": markerProfile]
        )
    }

    func record(
        name: String,
        timestamp: Double,
        markerId: Int? = nil,
        message: String? = nil,
        metadata: [String: String]? = nil
    ) {
        let event = ScanDiagnosticEvent(
            name: name,
            timestampSeconds: relativeTime(from: timestamp),
            markerId: markerId,
            message: message,
            metadata: metadata
        )
        events.append(event)
        if events.count > maxEvents {
            events.removeFirst(events.count - maxEvents)
        }
    }

    func recordFrame(
        timestamp: Double,
        fps: Double,
        accepted: Bool,
        rejectedByFocus: Bool,
        rejectedByBlur: Bool,
        rejectedByMotion: Bool,
        rejectedByNormal: Bool,
        rejectedByReprojection: Bool
    ) {
        if fps.isFinite, fps > 0 {
            fpsSum += fps
            fpsSampleCount += 1
            fpsMinValue = min(fpsMinValue ?? fps, fps)
            if fps < 15.0, !didRecordFPSDrop {
                record(name: "fps_drop_detected", timestamp: timestamp, message: String(format: "%.1f fps", fps))
                didRecordFPSDrop = true
            }
        }

        var snapshot = lastSnapshot
        snapshot.framesProcessed += 1
        if accepted {
            snapshot.framesAccepted += 1
        }
        if rejectedByFocus {
            snapshot.framesRejectedByFocus += 1
        }
        if rejectedByBlur {
            snapshot.framesRejectedByBlur += 1
        }
        if rejectedByMotion {
            snapshot.framesRejectedByMotion += 1
        }
        if rejectedByNormal {
            snapshot.framesRejectedByNormal += 1
        }
        if rejectedByReprojection {
            snapshot.framesRejectedByReprojection += 1
        }
        lastSnapshot = snapshot
    }

    func recordFocusState(isStable: Bool, timestamp: Double) {
        guard lastFocusStable != isStable else {
            return
        }

        if let lastFocusStable {
            record(
                name: isStable ? "focus_recovered" : "focus_lost",
                timestamp: timestamp,
                message: lastFocusStable ? "focus changed" : nil
            )
        }
        lastFocusStable = isStable
    }

    func recordDistanceState(
        state: String,
        distanceMm: Double?,
        isReliable: Bool,
        timestamp: Double
    ) {
        distanceSampleCount += 1
        if isReliable {
            distanceValidSampleCount += 1
        }

        guard lastDistanceState != state else {
            return
        }

        record(
            name: "distance_state_changed",
            timestamp: timestamp,
            message: state,
            metadata: distanceMm.flatMap { $0.isFinite ? ["distanceMm": String(format: "%.1f", $0)] : nil }
        )
        lastDistanceState = state
    }

    func recordMarkersSeen(
        markerIds: [Int],
        timestamp: Double,
        expectedMarkerIds: [Int]
    ) {
        let relativeTimestamp = relativeTime(from: timestamp)
        for markerId in markerIds {
            var state = markerStates[markerId] ?? MarkerState()
            if state.firstSeenAt == nil {
                state.firstSeenAt = relativeTimestamp
                if firstMarkerSeenAt == nil {
                    firstMarkerSeenAt = relativeTimestamp
                    record(name: "marker_seen", timestamp: timestamp, markerId: markerId)
                } else {
                    record(name: "marker_seen", timestamp: timestamp, markerId: markerId)
                }
            }
            if let lastSeenAt = state.lastSeenAt,
               relativeTimestamp > lastSeenAt {
                state.totalVisibleSeconds += min(relativeTimestamp - lastSeenAt, 1.0)
            }
            state.lastSeenAt = relativeTimestamp
            markerStates[markerId] = state
        }

        if allMarkersSeenAt == nil {
            let expectedSet = Set(expectedMarkerIds)
            if !expectedSet.isEmpty,
               expectedSet.allSatisfy({ markerStates[$0]?.firstSeenAt != nil }) {
                allMarkersSeenAt = relativeTimestamp
            }
        }
    }

    func updateMarkerSummaries(
        validations: [ExportableMarkerValidation],
        diagnosticsByMarkerId: [Int: FinalPoseObservationSelectionDiagnostics],
        timestamp: Double,
        expectedMarkerIds: [Int]
    ) {
        let relativeTimestamp = relativeTime(from: timestamp)
        let previousExportableIds = Set(markerStates.compactMap { $0.value.exportable ? $0.key : nil })

        for validation in validations {
            var state = markerStates[validation.markerId] ?? MarkerState()
            state.observationsAccumulated = validation.accumulatedObservationCount
            state.finalObservationsUsed = validation.finalObservationsUsed
            state.exportable = validation.isExportable
            state.invalidReason = validation.isExportable ? nil : validation.reason
            state.waitingReason = validation.isExportable ? nil : validation.reason

            if validation.isExportable, state.becameExportableAt == nil {
                state.becameExportableAt = relativeTimestamp
                record(name: "marker_exportable", timestamp: timestamp, markerId: validation.markerId)
            } else if !validation.isExportable,
                      let reason = validation.reason,
                      !reason.isEmpty {
                record(name: "marker_invalid", timestamp: timestamp, markerId: validation.markerId, message: reason)
            }

            if let diagnostics = diagnosticsByMarkerId[validation.markerId] {
                state.finalObservationsUsed = diagnostics.selectedObservationCount
                state.qualityScore = diagnostics.finalAverageQualityScore
                state.normalStdDegrees = diagnostics.finalNormalStdDevDegrees
                state.reprojectionError = diagnostics.finalAverageReprojectionError
            }
            markerStates[validation.markerId] = state
        }

        let exportableIds = Set(markerStates.compactMap { $0.value.exportable ? $0.key : nil })
        let expectedSet = Set(expectedMarkerIds)
        if allMarkersExportableAt == nil,
           !expectedSet.isEmpty,
           expectedSet.allSatisfy({ exportableIds.contains($0) }) {
            allMarkersExportableAt = relativeTimestamp
        }

        for lostMarkerId in previousExportableIds.subtracting(exportableIds) {
            record(name: "marker_lost", timestamp: timestamp, markerId: lostMarkerId)
        }
    }

    func makeSnapshot(
        timestamp: Double,
        markerProfile: String,
        exportGateReason: String?,
        scanConfidence: String?,
        mainIssue: String?,
        focusRecoveryState: String?,
        focusRecoveryCount: Int,
        arucoLostCount: Int,
        centerFocusRecoveryCount: Int,
        distanceGuideState: String?,
        lastDistanceMm: Double?,
        currentBlockingReason: String?,
        guidedStaticCaptureEnabled: Bool,
        guidedStages: [ScanDiagnosticsSnapshot.GuidedStageSummary]?
    ) -> ScanDiagnosticsSnapshot {
        let currentRelativeTime = relativeTime(from: timestamp)
        let slowestMarkerId = markerStates
            .filter { $0.value.becameExportableAt != nil || $0.value.firstSeenAt != nil }
            .max { lhs, rhs in
                let lhsTime = lhs.value.becameExportableAt ?? currentRelativeTime
                let rhsTime = rhs.value.becameExportableAt ?? currentRelativeTime
                return lhsTime < rhsTime
            }?
            .key

        let distanceValidPercent = distanceSampleCount > 0
            ? Double(distanceValidSampleCount) / Double(distanceSampleCount) * 100.0
            : nil

        let markerSummaries = markerStates
            .keys
            .sorted()
            .map { markerId in
                let state = markerStates[markerId] ?? MarkerState()
                return ScanDiagnosticsSnapshot.MarkerSummary(
                    markerId: markerId,
                    firstSeenAtSeconds: finite(state.firstSeenAt),
                    becameExportableAtSeconds: finite(state.becameExportableAt),
                    totalVisibleSeconds: finite(state.totalVisibleSeconds),
                    observationsAccumulated: state.observationsAccumulated,
                    finalObservationsUsed: state.finalObservationsUsed,
                    qualityScore: finite(state.qualityScore),
                    normalStdDegrees: finite(state.normalStdDegrees),
                    reprojectionError: finite(state.reprojectionError),
                    exportable: state.exportable,
                    invalidReason: state.invalidReason,
                    waitingReason: state.waitingReason
                )
            }

        let snapshot = ScanDiagnosticsSnapshot(
            createdAt: createdAt,
            markerProfile: markerProfile,
            scanDurationSeconds: finite(currentRelativeTime),
            timeToFirstMarkerSeconds: finite(firstMarkerSeenAt),
            timeToAllMarkersSeenSeconds: finite(allMarkersSeenAt),
            timeToAllMarkersExportableSeconds: finite(allMarkersExportableAt),
            extraTimeAfterAllMarkers100PercentSeconds: extraTimeAfterAllMarkersExportable(
                currentRelativeTime: currentRelativeTime
            ),
            fpsMean: fpsSampleCount > 0 ? finite(fpsSum / Double(fpsSampleCount)) : nil,
            fpsMin: finite(fpsMinValue),
            framesProcessed: lastSnapshot.framesProcessed,
            framesAccepted: lastSnapshot.framesAccepted,
            framesRejectedByFocus: lastSnapshot.framesRejectedByFocus,
            framesRejectedByBlur: lastSnapshot.framesRejectedByBlur,
            framesRejectedByMotion: lastSnapshot.framesRejectedByMotion,
            framesRejectedByNormal: lastSnapshot.framesRejectedByNormal,
            framesRejectedByReprojection: lastSnapshot.framesRejectedByReprojection,
            exportGateReason: exportGateReason,
            scanConfidence: scanConfidence,
            mainIssue: mainIssue,
            focusRecoveryState: focusRecoveryState,
            focusRecoveryCount: focusRecoveryCount,
            arucoLostCount: arucoLostCount,
            centerFocusRecoveryCount: centerFocusRecoveryCount,
            distanceGuideState: distanceGuideState,
            lastDistanceMm: finite(lastDistanceMm),
            distanceValidPercent: finite(distanceValidPercent),
            guidedStaticCaptureEnabled: guidedStaticCaptureEnabled,
            guidedStages: guidedStages,
            slowestMarkerId: slowestMarkerId,
            currentBlockingReason: currentBlockingReason,
            lastEventName: events.last?.name,
            eventsCount: events.count,
            events: events,
            markers: markerSummaries
        )
        lastSnapshot = snapshot
        return snapshot
    }

    private func extraTimeAfterAllMarkersExportable(currentRelativeTime: Double) -> Double? {
        guard let allMarkersExportableAt else {
            return nil
        }

        return finite(max(currentRelativeTime - allMarkersExportableAt, 0.0))
    }

    private func sanitizedTimestamp(_ timestamp: Double) -> Double {
        timestamp.isFinite ? timestamp : Date().timeIntervalSinceReferenceDate
    }

    private func relativeTime(from timestamp: Double) -> Double {
        let safeTimestamp = sanitizedTimestamp(timestamp)
        guard let scanStartedAt else {
            return 0
        }

        return max(safeTimestamp - scanStartedAt, 0.0)
    }

    private func finite(_ value: Double?) -> Double? {
        guard let value, value.isFinite else {
            return nil
        }

        return value
    }
}
