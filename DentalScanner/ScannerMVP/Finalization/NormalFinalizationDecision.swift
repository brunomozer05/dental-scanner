struct NormalFinalizationDecision: Equatable {
    static let successReason = "maturity_gate_passed"
    static let timeoutReason = "max_seconds_reached_without_success"

    let autoExportReason: String?
    let timeoutDiagnosticReason: String?
    let shouldRecordTimeoutDiagnostic: Bool

    var shouldAutoExport: Bool {
        autoExportReason != nil
    }

    var shouldContinueStabilizing: Bool {
        !shouldAutoExport
    }

    static func evaluate(
        hasExportableTagPoses: Bool,
        allExpectedMarkersAt100Percent: Bool,
        hasStableWindow: Bool,
        maturityGatePassed: Bool,
        hitMaxWindow: Bool,
        timeoutDiagnosticAlreadyRecorded: Bool
    ) -> NormalFinalizationDecision {
        let canAutoExport = hasExportableTagPoses &&
            allExpectedMarkersAt100Percent &&
            hasStableWindow &&
            maturityGatePassed

        if canAutoExport {
            return NormalFinalizationDecision(
                autoExportReason: successReason,
                timeoutDiagnosticReason: nil,
                shouldRecordTimeoutDiagnostic: false
            )
        }

        let timedOutWithoutSuccess = hasExportableTagPoses &&
            allExpectedMarkersAt100Percent &&
            hitMaxWindow
        return NormalFinalizationDecision(
            autoExportReason: nil,
            timeoutDiagnosticReason: timedOutWithoutSuccess ? timeoutReason : nil,
            shouldRecordTimeoutDiagnostic:
                timedOutWithoutSuccess && !timeoutDiagnosticAlreadyRecorded
        )
    }
}
