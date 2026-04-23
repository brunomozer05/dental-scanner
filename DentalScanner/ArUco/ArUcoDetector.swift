import CoreVideo
import Foundation
import simd

public struct ArUcoDetectorConfiguration: Equatable {
    public var dictionary: ArUcoDictionary
    public var physicalSizeMillimeters: Double
    public var expectedTagRange: ClosedRange<Int>
    public var enableSubpixelRefinement: Bool

    public init(
        dictionary: ArUcoDictionary = .fourByFour50,
        physicalSizeMillimeters: Double = 8,
        expectedTagRange: ClosedRange<Int> = 4...8,
        enableSubpixelRefinement: Bool = true
    ) {
        self.dictionary = dictionary
        self.physicalSizeMillimeters = physicalSizeMillimeters
        self.expectedTagRange = expectedTagRange
        self.enableSubpixelRefinement = enableSubpixelRefinement
    }
}

public protocol ArUcoDetectingBackend {
    func detectMarkers(
        in frame: CVPixelBuffer,
        configuration: ArUcoDetectorConfiguration,
        intrinsics: CameraIntrinsics?
    ) -> [DetectedMarker]
}

public struct NullArUcoBackend: ArUcoDetectingBackend {
    public init() {}

    public func detectMarkers(
        in frame: CVPixelBuffer,
        configuration: ArUcoDetectorConfiguration,
        intrinsics: CameraIntrinsics?
    ) -> [DetectedMarker] {
        []
    }
}

public final class ArUcoDetector {
    public let configuration: ArUcoDetectorConfiguration
    private let backend: any ArUcoDetectingBackend

    public init(
        configuration: ArUcoDetectorConfiguration = ArUcoDetectorConfiguration(),
        backend: any ArUcoDetectingBackend = NullArUcoBackend()
    ) {
        self.configuration = configuration
        self.backend = backend
    }

    public func detectMarkers(
        in frame: CVPixelBuffer,
        intrinsics: CameraIntrinsics? = nil
    ) -> [DetectedMarker] {
        backend.detectMarkers(in: frame, configuration: configuration, intrinsics: intrinsics)
    }

    public func markerObjectPoints() -> [SIMD3<Float>] {
        let halfSize = Float(configuration.physicalSizeMillimeters / 2)
        return [
            SIMD3<Float>(-halfSize, halfSize, 0),
            SIMD3<Float>(halfSize, halfSize, 0),
            SIMD3<Float>(halfSize, -halfSize, 0),
            SIMD3<Float>(-halfSize, -halfSize, 0)
        ]
    }

    public func minimumVisibleMarkerCount() -> Int {
        configuration.expectedTagRange.lowerBound
    }
}

