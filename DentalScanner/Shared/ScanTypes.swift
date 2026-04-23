import CoreGraphics
import Foundation
import simd

public enum ScanStage: String, CaseIterable, Codable {
    case idle
    case calibrating
    case capturing
    case processing
    case preview
    case export
}

public enum ArUcoDictionary: String, CaseIterable, Codable {
    case fourByFour50 = "4x4_50"
    case fourByFour100 = "4x4_100"
}

public struct CameraIntrinsics: Equatable, Codable {
    public var fx: Double
    public var fy: Double
    public var cx: Double
    public var cy: Double
    public var distortionCoefficients: [Double]
    public var reprojectionErrorPixels: Double

    public init(
        fx: Double,
        fy: Double,
        cx: Double,
        cy: Double,
        distortionCoefficients: [Double],
        reprojectionErrorPixels: Double
    ) {
        self.fx = fx
        self.fy = fy
        self.cx = cx
        self.cy = cy
        self.distortionCoefficients = distortionCoefficients
        self.reprojectionErrorPixels = reprojectionErrorPixels
    }
}

public struct CalibrationSample: Identifiable, Equatable, Codable {
    public var id: UUID
    public var assetName: String
    public var detectedCorners: Int
    public var reprojectionErrorPixels: Double

    public init(
        id: UUID = UUID(),
        assetName: String,
        detectedCorners: Int,
        reprojectionErrorPixels: Double
    ) {
        self.id = id
        self.assetName = assetName
        self.detectedCorners = detectedCorners
        self.reprojectionErrorPixels = reprojectionErrorPixels
    }
}

public struct PoseTransform: Equatable {
    public var rotationEuler: SIMD3<Float>
    public var translation: SIMD3<Float>

    public init(
        rotationEuler: SIMD3<Float> = .zero,
        translation: SIMD3<Float> = .zero
    ) {
        self.rotationEuler = rotationEuler
        self.translation = translation
    }
}

public struct DetectedMarker: Identifiable, Equatable {
    public var id: Int
    public var dictionary: ArUcoDictionary
    public var physicalSizeMillimeters: Double
    public var corners: [CGPoint]
    public var pose: PoseTransform?
    public var confidence: Float

    public init(
        id: Int,
        dictionary: ArUcoDictionary,
        physicalSizeMillimeters: Double,
        corners: [CGPoint],
        pose: PoseTransform? = nil,
        confidence: Float
    ) {
        self.id = id
        self.dictionary = dictionary
        self.physicalSizeMillimeters = physicalSizeMillimeters
        self.corners = corners
        self.pose = pose
        self.confidence = confidence
    }
}

public struct FrameQualityMetrics: Equatable {
    public var sharpnessScore: Double
    public var lightingMean: Double
    public var lightingDeviation: Double
    public var motionBlurScore: Double
    public var overlapEstimate: Double
    public var detectedTagCount: Int
    public var tagsStable: Bool

    public init(
        sharpnessScore: Double,
        lightingMean: Double,
        lightingDeviation: Double,
        motionBlurScore: Double,
        overlapEstimate: Double,
        detectedTagCount: Int,
        tagsStable: Bool
    ) {
        self.sharpnessScore = sharpnessScore
        self.lightingMean = lightingMean
        self.lightingDeviation = lightingDeviation
        self.motionBlurScore = motionBlurScore
        self.overlapEstimate = overlapEstimate
        self.detectedTagCount = detectedTagCount
        self.tagsStable = tagsStable
    }
}

public struct CaptureFrame: Identifiable, Equatable {
    public var id: UUID
    public var index: Int
    public var timestamp: Date
    public var bucket: Int
    public var metrics: FrameQualityMetrics
    public var markers: [DetectedMarker]
    public var relativePose: PoseTransform?

    public init(
        id: UUID = UUID(),
        index: Int,
        timestamp: Date = Date(),
        bucket: Int,
        metrics: FrameQualityMetrics,
        markers: [DetectedMarker],
        relativePose: PoseTransform? = nil
    ) {
        self.id = id
        self.index = index
        self.timestamp = timestamp
        self.bucket = bucket
        self.metrics = metrics
        self.markers = markers
        self.relativePose = relativePose
    }
}

public struct SparsePoint: Equatable {
    public var position: SIMD3<Float>
    public var confidence: Float

    public init(position: SIMD3<Float>, confidence: Float) {
        self.position = position
        self.confidence = confidence
    }
}

public struct DensePoint: Equatable {
    public var position: SIMD3<Float>
    public var normal: SIMD3<Float>
    public var confidence: Float

    public init(position: SIMD3<Float>, normal: SIMD3<Float>, confidence: Float) {
        self.position = position
        self.normal = normal
        self.confidence = confidence
    }
}

public struct Mesh3D: Equatable {
    public var vertices: [SIMD3<Float>]
    public var faces: [SIMD3<Int>]

    public init(vertices: [SIMD3<Float>], faces: [SIMD3<Int>]) {
        self.vertices = vertices
        self.faces = faces
    }
}

public struct ReconstructionState: Equatable {
    public var sparsePoints: [SparsePoint]
    public var densePoints: [DensePoint]
    public var anchorMarkers: [DetectedMarker]
    public var scaleMillimetersPerUnit: Double
    public var processedFrameCount: Int
    public var scaleAnchored: Bool

    public init(
        sparsePoints: [SparsePoint] = [],
        densePoints: [DensePoint] = [],
        anchorMarkers: [DetectedMarker] = [],
        scaleMillimetersPerUnit: Double = 1.0,
        processedFrameCount: Int = 0,
        scaleAnchored: Bool = false
    ) {
        self.sparsePoints = sparsePoints
        self.densePoints = densePoints
        self.anchorMarkers = anchorMarkers
        self.scaleMillimetersPerUnit = scaleMillimetersPerUnit
        self.processedFrameCount = processedFrameCount
        self.scaleAnchored = scaleAnchored
    }
}

public struct AccuracyReport: Equatable {
    public var rmsErrorMicrometers: Double
    public var maxErrorMicrometers: Double
    public var meanErrorMicrometers: Double
    public var pointsWithinTolerancePercent: Double

    public init(
        rmsErrorMicrometers: Double,
        maxErrorMicrometers: Double,
        meanErrorMicrometers: Double,
        pointsWithinTolerancePercent: Double
    ) {
        self.rmsErrorMicrometers = rmsErrorMicrometers
        self.maxErrorMicrometers = maxErrorMicrometers
        self.meanErrorMicrometers = meanErrorMicrometers
        self.pointsWithinTolerancePercent = pointsWithinTolerancePercent
    }
}

public struct TagValidationResult: Equatable {
    public var isValid: Bool
    public var issues: [String]
    public var visibleTags: Int
    public var meanEdgeLengthPixels: Double

    public init(
        isValid: Bool,
        issues: [String],
        visibleTags: Int,
        meanEdgeLengthPixels: Double
    ) {
        self.isValid = isValid
        self.issues = issues
        self.visibleTags = visibleTags
        self.meanEdgeLengthPixels = meanEdgeLengthPixels
    }
}

public struct CaptureGuidance: Equatable {
    public var coverageMap: [Bool]
    public var qualityScore: Float
    public var tagVisibility: [Int: Bool]
    public var recommendations: [String]
    public var validFrameCount: Int

    public init(
        coverageMap: [Bool],
        qualityScore: Float,
        tagVisibility: [Int: Bool],
        recommendations: [String],
        validFrameCount: Int
    ) {
        self.coverageMap = coverageMap
        self.qualityScore = qualityScore
        self.tagVisibility = tagVisibility
        self.recommendations = recommendations
        self.validFrameCount = validFrameCount
    }

    public static func empty(bucketCount: Int = 18) -> CaptureGuidance {
        CaptureGuidance(
            coverageMap: Array(repeating: false, count: bucketCount),
            qualityScore: 0,
            tagVisibility: [:],
            recommendations: [
                "Calibre a camera antes da primeira sessao clinica.",
                "Mantenha 4 ou mais tags ArUco visiveis.",
                "Capture 15-30 poses com 70-80% de sobreposicao."
            ],
            validFrameCount: 0
        )
    }
}

public struct ScanSessionState: Equatable {
    public var stage: ScanStage
    public var calibration: CameraIntrinsics?
    public var frames: [CaptureFrame]
    public var guidance: CaptureGuidance
    public var reconstruction: ReconstructionState?
    public var mesh: Mesh3D?

    public init(
        stage: ScanStage = .idle,
        calibration: CameraIntrinsics? = nil,
        frames: [CaptureFrame] = [],
        guidance: CaptureGuidance = .empty(),
        reconstruction: ReconstructionState? = nil,
        mesh: Mesh3D? = nil
    ) {
        self.stage = stage
        self.calibration = calibration
        self.frames = frames
        self.guidance = guidance
        self.reconstruction = reconstruction
        self.mesh = mesh
    }
}

