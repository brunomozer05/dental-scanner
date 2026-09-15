import XCTest
@testable import DentalScanner

final class SafetyCriticalDefaultsTests: XCTestCase {
    func testPreAccumulationObservationGateBlockingIsDisabledByDefault() {
        let viewModel = ScannerViewModel()

        XCTAssertFalse(
            viewModel.preAccumulationObservationGateDiagnosticsForDebug.blockingEnabled
        )
    }

    func testBestFinalPoseCandidateIsNotTheNormalExportSourceByDefault() {
        let viewModel = ScannerViewModel()

        XCTAssertFalse(viewModel.debugUseBestFinalPoseCandidateForExport)
        XCTAssertFalse(viewModel.debugUsedBestFinalPoseCandidate)
    }

    func testLegacyConcatenatedMultiFramePnPIsDisabledForSingleArucoV1() {
        let viewModel = ScannerViewModel()

        XCTAssertFalse(
            viewModel.debugLegacyConcatenatedMultiFramePnPForSingleArucoV1Enabled
        )
    }
}
