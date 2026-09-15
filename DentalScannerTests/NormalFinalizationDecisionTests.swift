import XCTest
@testable import DentalScanner

final class NormalFinalizationDecisionTests: XCTestCase {
    func testTimeoutDoesNotAutoExportWithoutMaturity() {
        let decision = makeDecision(
            hasStableWindow: true,
            maturityGatePassed: false,
            hitMaxWindow: true
        )

        XCTAssertFalse(decision.shouldAutoExport)
        XCTAssertNil(decision.autoExportReason)
        XCTAssertTrue(decision.shouldContinueStabilizing)
    }

    func testTimeoutDoesNotAutoExportWithoutStableWindow() {
        let decision = makeDecision(
            hasStableWindow: false,
            maturityGatePassed: true,
            hitMaxWindow: true
        )

        XCTAssertFalse(decision.shouldAutoExport)
        XCTAssertNil(decision.autoExportReason)
        XCTAssertTrue(decision.shouldContinueStabilizing)
    }

    func testStableMatureFinalizationStillAutoExports() {
        let decision = makeDecision(
            hasStableWindow: true,
            maturityGatePassed: true,
            hitMaxWindow: false
        )

        XCTAssertTrue(decision.shouldAutoExport)
        XCTAssertEqual(decision.autoExportReason, NormalFinalizationDecision.successReason)
        XCTAssertNil(decision.timeoutDiagnosticReason)
        XCTAssertFalse(decision.shouldContinueStabilizing)
    }

    func testSuccessRemainsReachableAfterTimeout() {
        let timedOut = makeDecision(
            hasStableWindow: false,
            maturityGatePassed: false,
            hitMaxWindow: true
        )
        XCTAssertTrue(timedOut.shouldContinueStabilizing)

        let recovered = makeDecision(
            hasStableWindow: true,
            maturityGatePassed: true,
            hitMaxWindow: true,
            timeoutDiagnosticAlreadyRecorded: true
        )

        XCTAssertTrue(recovered.shouldAutoExport)
        XCTAssertEqual(recovered.autoExportReason, NormalFinalizationDecision.successReason)
    }

    func testTimeoutDiagnosticIsDeterministicOneShotAndNotASuccessReason() {
        let firstDecision = makeDecision(
            hasStableWindow: false,
            maturityGatePassed: false,
            hitMaxWindow: true
        )
        let repeatedDecision = makeDecision(
            hasStableWindow: false,
            maturityGatePassed: false,
            hitMaxWindow: true,
            timeoutDiagnosticAlreadyRecorded: true
        )

        XCTAssertEqual(
            firstDecision.timeoutDiagnosticReason,
            NormalFinalizationDecision.timeoutReason
        )
        XCTAssertNotEqual(
            firstDecision.timeoutDiagnosticReason,
            NormalFinalizationDecision.successReason
        )
        XCTAssertTrue(firstDecision.shouldRecordTimeoutDiagnostic)
        XCTAssertEqual(
            repeatedDecision.timeoutDiagnosticReason,
            firstDecision.timeoutDiagnosticReason
        )
        XCTAssertFalse(repeatedDecision.shouldRecordTimeoutDiagnostic)
    }

    func testExpectedMarkerGateRemainsRequiredForAutoExport() {
        let decision = makeDecision(
            allExpectedMarkersAt100Percent: false,
            hasStableWindow: true,
            maturityGatePassed: true,
            hitMaxWindow: true
        )

        XCTAssertFalse(decision.shouldAutoExport)
        XCTAssertNil(decision.autoExportReason)
        XCTAssertNil(decision.timeoutDiagnosticReason)
        XCTAssertTrue(decision.shouldContinueStabilizing)
    }

    func testExportablePoseGateRemainsRequiredForAutoExport() {
        let decision = makeDecision(
            hasExportableTagPoses: false,
            hasStableWindow: true,
            maturityGatePassed: true,
            hitMaxWindow: true
        )

        XCTAssertFalse(decision.shouldAutoExport)
        XCTAssertNil(decision.autoExportReason)
        XCTAssertNil(decision.timeoutDiagnosticReason)
    }

    private func makeDecision(
        hasExportableTagPoses: Bool = true,
        allExpectedMarkersAt100Percent: Bool = true,
        hasStableWindow: Bool,
        maturityGatePassed: Bool,
        hitMaxWindow: Bool,
        timeoutDiagnosticAlreadyRecorded: Bool = false
    ) -> NormalFinalizationDecision {
        NormalFinalizationDecision.evaluate(
            hasExportableTagPoses: hasExportableTagPoses,
            allExpectedMarkersAt100Percent: allExpectedMarkersAt100Percent,
            hasStableWindow: hasStableWindow,
            maturityGatePassed: maturityGatePassed,
            hitMaxWindow: hitMaxWindow,
            timeoutDiagnosticAlreadyRecorded: timeoutDiagnosticAlreadyRecorded
        )
    }
}
