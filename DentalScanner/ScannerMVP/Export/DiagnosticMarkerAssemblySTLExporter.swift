import Foundation
import simd

struct DiagnosticMarkerAssemblyProvenance: Equatable, Sendable {
    let sessionIdentifier: String
    let replayPolicy: String
    let comparisonBaseMarkerId: Int

    var solidName: String {
        let safeSession = sessionIdentifier.map { character in
            character.isLetter || character.isNumber ? String(character) : "_"
        }.joined()
        return "diagnostic_\(safeSession)_\(replayPolicy)_base_\(comparisonBaseMarkerId)"
    }
}

struct DiagnosticMarkerPoseNormalizationResult {
    let baseMarkerId: Int
    let allPoses: [PoseResult]
    let filteredPoses: [PoseResult]
    let allMarkerIds: [Int]
    let filteredMarkerIds: [Int]
    let commonMarkerIds: [Int]
    let missingFromAll: [Int]
    let missingFromFiltered: [Int]
}

enum DiagnosticMarkerAssemblyError: LocalizedError, Equatable {
    case emptyPoseSet(policy: String)
    case duplicateMarkerId(policy: String, markerId: Int)
    case noCommonMarker
    case missingBaseMarker(policy: String, markerId: Int)
    case invalidPose(policy: String, markerId: Int)
    case inconsistentMarkerProfiles
    case unableToEncodeSTL

    var errorDescription: String? {
        switch self {
        case let .emptyPoseSet(policy):
            return "O replay \(policy) não produziu poses para exportar."
        case let .duplicateMarkerId(policy, markerId):
            return "O replay \(policy) produziu o marker \(markerId) mais de uma vez."
        case .noCommonMarker:
            return "ALL e FILTERED não possuem um marker comum para normalização."
        case let .missingBaseMarker(policy, markerId):
            return "O marker-base \(markerId) não está presente no replay \(policy)."
        case let .invalidPose(policy, markerId):
            return "O replay \(policy) contém pose inválida para o marker \(markerId)."
        case .inconsistentMarkerProfiles:
            return "As poses do replay não usam um único perfil de marker compatível."
        case .unableToEncodeSTL:
            return "Não foi possível codificar o STL diagnóstico."
        }
    }
}

enum DiagnosticMarkerPoseNormalizer {
    static func normalize(
        allPoses: [PoseResult],
        filteredPoses: [PoseResult]
    ) throws -> DiagnosticMarkerPoseNormalizationResult {
        let allByMarker = try posesByMarkerId(allPoses, policy: "ALL")
        let filteredByMarker = try posesByMarkerId(filteredPoses, policy: "FILTERED")
        let allMarkerIds = allByMarker.keys.sorted()
        let filteredMarkerIds = filteredByMarker.keys.sorted()
        let allMarkerIdSet = Set(allMarkerIds)
        let filteredMarkerIdSet = Set(filteredMarkerIds)
        let commonMarkerIds = allMarkerIdSet.intersection(filteredMarkerIdSet).sorted()

        guard let baseMarkerId = commonMarkerIds.first else {
            throw DiagnosticMarkerAssemblyError.noCommonMarker
        }

        return DiagnosticMarkerPoseNormalizationResult(
            baseMarkerId: baseMarkerId,
            allPoses: try rebase(
                poses: allPoses,
                to: baseMarkerId,
                policy: "ALL"
            ),
            filteredPoses: try rebase(
                poses: filteredPoses,
                to: baseMarkerId,
                policy: "FILTERED"
            ),
            allMarkerIds: allMarkerIds,
            filteredMarkerIds: filteredMarkerIds,
            commonMarkerIds: commonMarkerIds,
            missingFromAll: filteredMarkerIdSet.subtracting(allMarkerIdSet).sorted(),
            missingFromFiltered: allMarkerIdSet.subtracting(filteredMarkerIdSet).sorted()
        )
    }

    static func rebase(
        poses: [PoseResult],
        to baseMarkerId: Int,
        policy: String
    ) throws -> [PoseResult] {
        let posesByMarker = try posesByMarkerId(poses, policy: policy)
        guard let basePose = posesByMarker[baseMarkerId] else {
            throw DiagnosticMarkerAssemblyError.missingBaseMarker(
                policy: policy,
                markerId: baseMarkerId
            )
        }
        guard isValid(basePose) else {
            throw DiagnosticMarkerAssemblyError.invalidPose(
                policy: policy,
                markerId: baseMarkerId
            )
        }

        let inverseBaseRotation = simd_transpose(basePose.rotationMatrix)
        return try poses.map { pose in
            guard isValid(pose) else {
                throw DiagnosticMarkerAssemblyError.invalidPose(
                    policy: policy,
                    markerId: pose.markerId
                )
            }

            let relativeRotation: simd_double3x3
            let relativeTranslation: SIMD3<Double>
            let relativeRotationVector: SIMD3<Double>
            if pose.markerId == baseMarkerId {
                relativeRotation = matrix_identity_double3x3
                relativeTranslation = .zero
                relativeRotationVector = .zero
            } else {
                relativeRotation = inverseBaseRotation * pose.rotationMatrix
                relativeTranslation = inverseBaseRotation * (
                    pose.translationVector - basePose.translationVector
                )
                guard let rotationVector = PoseMath.rotationVector(from: relativeRotation),
                      PoseMath.isFinite(rotationVector),
                      PoseMath.isFinite(relativeTranslation)
                else {
                    throw DiagnosticMarkerAssemblyError.invalidPose(
                        policy: policy,
                        markerId: pose.markerId
                    )
                }
                relativeRotationVector = rotationVector
            }

            return PoseResult(
                markerId: pose.markerId,
                markerProfile: pose.markerProfile,
                poseSource: pose.poseSource,
                rotationVector: relativeRotationVector,
                rotationMatrix: relativeRotation,
                translationVector: relativeTranslation,
                distanceMm: simd_length(relativeTranslation),
                reprojectionError: pose.reprojectionError,
                markerAreaPixels: pose.markerAreaPixels,
                usedPointCount: pose.usedPointCount,
                detectedTopTagId: pose.detectedTopTagId,
                detectedBottomTagId: pose.detectedBottomTagId
            )
        }
    }

    private static func posesByMarkerId(
        _ poses: [PoseResult],
        policy: String
    ) throws -> [Int: PoseResult] {
        guard !poses.isEmpty else {
            throw DiagnosticMarkerAssemblyError.emptyPoseSet(policy: policy)
        }

        var result: [Int: PoseResult] = [:]
        for pose in poses {
            guard result.updateValue(pose, forKey: pose.markerId) == nil else {
                throw DiagnosticMarkerAssemblyError.duplicateMarkerId(
                    policy: policy,
                    markerId: pose.markerId
                )
            }
        }
        return result
    }

    private static func isValid(_ pose: PoseResult) -> Bool {
        guard PoseMath.isFinite(pose.rotationMatrix),
              PoseMath.isFinite(pose.translationVector)
        else {
            return false
        }

        let orthogonality = simd_transpose(pose.rotationMatrix) * pose.rotationMatrix
        for row in 0..<3 {
            for column in 0..<3 {
                let expected = row == column ? 1.0 : 0.0
                guard abs(
                    PoseMath.matrixElement(
                        orthogonality,
                        row: row,
                        column: column
                    ) - expected
                ) <= 1e-6 else {
                    return false
                }
            }
        }

        return abs(simd_determinant(pose.rotationMatrix) - 1.0) <= 1e-6
    }
}

struct DiagnosticMarkerAssemblySTLExporter {
    typealias STLGenerator = (
        _ markerProfile: MarkerProfile,
        _ poses: [PoseResult],
        _ solidName: String
    ) throws -> String

    private let generateSTL: STLGenerator

    init(generateSTL: STLGenerator? = nil) {
        self.generateSTL = generateSTL ?? { markerProfile, poses, solidName in
            let exporter = STLExporter(
                configuration: .referenceMarker(for: markerProfile)
            )
            return try exporter.exportReferenceMarkersAsSTL(
                tagPoses: poses,
                solidName: solidName
            )
        }
    }

    func makeSTLData(
        poses: [PoseResult],
        markerProfile: MarkerProfile,
        provenance: DiagnosticMarkerAssemblyProvenance
    ) throws -> Data {
        guard !poses.isEmpty else {
            throw DiagnosticMarkerAssemblyError.emptyPoseSet(
                policy: provenance.replayPolicy
            )
        }
        guard poses.allSatisfy({ $0.markerProfile == markerProfile }) else {
            throw DiagnosticMarkerAssemblyError.inconsistentMarkerProfiles
        }

        let stl = try generateSTL(markerProfile, poses, provenance.solidName)
        guard let data = stl.data(using: .utf8) else {
            throw DiagnosticMarkerAssemblyError.unableToEncodeSTL
        }
        return data
    }

    @discardableResult
    func write(
        poses: [PoseResult],
        markerProfile: MarkerProfile,
        provenance: DiagnosticMarkerAssemblyProvenance,
        to outputURL: URL
    ) throws -> Int64 {
        let data = try makeSTLData(
            poses: poses,
            markerProfile: markerProfile,
            provenance: provenance
        )
        try data.write(to: outputURL, options: .atomic)
        return Int64(data.count)
    }
}
