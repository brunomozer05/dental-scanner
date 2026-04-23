import XCTest
@testable import DentalScannerKit

final class TagValidatorTests: XCTestCase {
    func testValidatorRejectsInsufficientVisibleTags() {
        let validator = TagValidator(configuration: TagValidatorConfiguration(minimumVisibleTags: 4))
        let result = validator.validate(makeMarkers(count: 3))

        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.issues.contains(where: { $0.contains("Poucas tags visiveis") }))
    }

    func testValidatorAcceptsStableMarkerSet() {
        let validator = TagValidator()
        let result = validator.validate(makeMarkers(count: 4))

        XCTAssertTrue(result.isValid)
        XCTAssertEqual(result.visibleTags, 4)
    }

    private func makeMarkers(count: Int) -> [DetectedMarker] {
        (0..<count).map { index in
            let x = CGFloat(index * 20)
            return DetectedMarker(
                id: index,
                dictionary: .fourByFour50,
                physicalSizeMillimeters: 8,
                corners: [
                    CGPoint(x: x, y: 0),
                    CGPoint(x: x + 10, y: 0),
                    CGPoint(x: x + 10, y: 10),
                    CGPoint(x: x, y: 10)
                ],
                pose: PoseTransform(translation: SIMD3<Float>(Float(index), Float(index), 20)),
                confidence: 0.95
            )
        }
    }
}

