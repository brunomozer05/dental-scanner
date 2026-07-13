import Foundation
import simd

struct ScanSessionReplayOptions: Equatable, Sendable {
    let requireCompletedSession: Bool

    static let deterministic = ScanSessionReplayOptions(requireCompletedSession: true)
}

enum ScanSessionReplayError: Error, Equatable, LocalizedError {
    case unableToOpenFile(String)
    case lineTooLong(line: Int, maximumBytes: Int)
    case malformedJSON(line: Int)
    case unsupportedSchemaVersion(line: Int, found: Int)
    case unknownRecordType(line: Int, recordType: String)
    case headerNotFirst(line: Int)
    case duplicateHeader(line: Int)
    case frameBeforeHeader(line: Int)
    case footerBeforeHeader(line: Int)
    case duplicateFooter(line: Int)
    case recordAfterFooter(line: Int)
    case missingHeader
    case missingFooter
    case invalidHeader(line: Int, reason: String)
    case nonIncreasingFrameIndex(line: Int, previous: Int, current: Int)
    case invalidFrame(line: Int, frameIndex: Int?, reason: String)
    case invalidPose(line: Int, frameIndex: Int, markerPosition: Int, reason: String)
    case incompleteSession
    case invalidFooter(reason: String)
    case replayPassMetadataMismatch

    var errorDescription: String? {
        switch self {
        case .unableToOpenFile(let path):
            return "Unable to open session replay file: \(path)"
        case let .lineTooLong(line, maximumBytes):
            return "NDJSON line \(line) exceeds \(maximumBytes) bytes."
        case .malformedJSON(let line):
            return "Malformed JSON at NDJSON line \(line)."
        case let .unsupportedSchemaVersion(line, found):
            return "Unsupported schemaVersion \(found) at line \(line)."
        case let .unknownRecordType(line, recordType):
            return "Unknown recordType '\(recordType)' at line \(line)."
        case .headerNotFirst(let line):
            return "sessionHeader is not the first non-empty record (line \(line))."
        case .duplicateHeader(let line):
            return "Duplicate sessionHeader at line \(line)."
        case .frameBeforeHeader(let line):
            return "frameObservation appears before sessionHeader at line \(line)."
        case .footerBeforeHeader(let line):
            return "sessionFooter appears before sessionHeader at line \(line)."
        case .duplicateFooter(let line):
            return "Duplicate sessionFooter at line \(line)."
        case .recordAfterFooter(let line):
            return "A record appears after sessionFooter at line \(line)."
        case .missingHeader:
            return "Session replay file has no sessionHeader."
        case .missingFooter:
            return "Session replay file has no sessionFooter."
        case let .invalidHeader(line, reason):
            return "Invalid sessionHeader at line \(line): \(reason)"
        case let .nonIncreasingFrameIndex(line, previous, current):
            return "Non-increasing frameIndex at line \(line): \(previous) -> \(current)."
        case let .invalidFrame(line, frameIndex, reason):
            return "Invalid frameObservation at line \(line), frame \(frameIndex.map(String.init) ?? "unknown"): \(reason)"
        case let .invalidPose(line, frameIndex, markerPosition, reason):
            return "Invalid pose at line \(line), frame \(frameIndex), marker position \(markerPosition): \(reason)"
        case .incompleteSession:
            return "Deterministic replay requires sessionFooter.completed = true."
        case .invalidFooter(let reason):
            return "Invalid sessionFooter: \(reason)"
        case .replayPassMetadataMismatch:
            return "Replay A and Replay B read different session metadata."
        }
    }
}

struct ScanSessionReplayCaptureMetadata: Codable, Equatable, Sendable {
    let sessionIdentifier: String
    let schemaVersion: Int
    let captureStartedTimestamp: Double
    let deviceModelIdentifier: String
    let osVersion: String
    let cameraProfileId: String
    let cameraProfileName: String
    let markerProfile: String
    let expectedPhysicalMarkerIds: [Int]
    let featureFlags: [String: Bool]
    let appVersion: String?
    let appBuildIdentifier: String?
    let appGitCommitHash: String?
}

struct ScanSessionReplayReadSummary: Equatable, Sendable {
    let metadata: ScanSessionReplayCaptureMetadata
    let framesRead: Int
    let markerObservationsReconstructed: Int
    let firstFrameIndex: Int?
    let lastFrameIndex: Int?
    let firstTimestampSeconds: Double?
    let lastTimestampSeconds: Double?
    let footerCompleted: Bool
}

struct ScanSessionReplayFrameInput {
    let frameIndex: Int
    let timestampSeconds: Double?
    let poseResults: [PoseResult]
}

struct ScanSessionReplayMarkerComparison: Codable, Equatable, Sendable {
    let markerId: Int
    let translationDeltaMm: Double
    let rotationDeltaDegrees: Double
}

struct ScanSessionReplayDeterminismComparison: Codable, Equatable, Sendable {
    let replayAMarkerIds: [Int]
    let replayBMarkerIds: [Int]
    let missingFromReplayA: [Int]
    let missingFromReplayB: [Int]
    let markers: [ScanSessionReplayMarkerComparison]
    let comparedMarkerCount: Int
    let meanTranslationDeltaMm: Double
    let maxTranslationDeltaMm: Double
    let meanRotationDeltaDegrees: Double
    let maxRotationDeltaDegrees: Double
    let translationToleranceMm: Double
    let rotationToleranceDegrees: Double
    let replayDeterministic: Bool
}

struct ScanSessionReplayFinalPoseSummary: Codable, Equatable, Sendable {
    let markerId: Int
    let markerProfile: String
    let markerSource: String
    let markerSourceTagId: Int?
    let rotationVector: ObservationPoint3D
    let rotationMatrixRows: [ObservationPoint3D]
    let translationVector: ObservationPoint3D
    let reprojectionError: Double
    let distanceMm: Double
    let markerAreaPixels: Double
    let usedPointCount: Int
    let detectedTopTagId: Int?
    let detectedBottomTagId: Int?
}

struct ScanSessionDeterministicReplaySummary: Codable, Equatable, Sendable {
    let sessionIdentifier: String
    let schemaVersion: Int
    let appGitCommitHash: String?
    let appVersion: String?
    let appBuildIdentifier: String?
    let replayAlgorithmIdentifier: String
    let replayUsesRandomness: Bool
    let framesReplayed: Int
    let markerObservationsReconstructed: Int
    let finalMarkerIds: [Int]
    let finalPoses: [ScanSessionReplayFinalPoseSummary]
    let determinism: ScanSessionReplayDeterminismComparison
    let integrityResult: String
    let provenanceCaveats: [String]
    let liveVsReplayDirectComparison: String
}

struct ScanSessionDeterministicReplayResult {
    let summary: ScanSessionDeterministicReplaySummary
    let replayAFinalPoses: [PoseResult]
    let replayBFinalPoses: [PoseResult]
}

final class ScanSessionSchemaV1Reader {
    static let supportedSchemaVersion = ScanSessionObservationWriter.schemaVersion

    private struct Envelope: Decodable {
        let recordType: String
        let schemaVersion: Int
    }

    private struct HeaderRecord: Decodable {
        let recordType: String
        let schemaVersion: Int
        let sessionIdentifier: String
        let captureStartedTimestamp: Double
        let deviceModelIdentifier: String
        let osVersion: String
        let cameraProfileId: String
        let cameraProfileName: String
        let markerProfile: String
        let expectedPhysicalMarkerIds: [Int]
        let appVersion: String?
        let appBuildIdentifier: String?
        let appGitCommitHash: String?
        let featureFlags: [String: Bool]
    }

    private struct FrameRecord: Decodable {
        let recordType: String
        let schemaVersion: Int
        let frame: FrameObservation
    }

    private struct FooterRecord: Decodable {
        let recordType: String
        let schemaVersion: Int
        let completed: Bool
        let captureEndedTimestamp: Double
        let framesEnqueued: Int
        let framesWritten: Int
        let frameWriteFailureCount: Int
        let frameOrderViolationCount: Int
        let limitReached: Bool
        let fileSizeBytes: Int64
    }

    private let decoder: JSONDecoder
    private let maximumLineBytes: Int

    init(maximumLineBytes: Int = 8 * 1_024 * 1_024) {
        self.maximumLineBytes = max(maximumLineBytes, 1_024)
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "Infinity",
            negativeInfinity: "-Infinity",
            nan: "NaN"
        )
        self.decoder = decoder
    }

    func read(
        from fileURL: URL,
        options: ScanSessionReplayOptions = .deterministic,
        onFrame: (ScanSessionReplayFrameInput) throws -> Void
    ) throws -> ScanSessionReplayReadSummary {
        var header: HeaderRecord?
        var footer: FooterRecord?
        var nonEmptyRecordCount = 0
        var framesRead = 0
        var markerObservationsReconstructed = 0
        var firstFrameIndex: Int?
        var lastFrameIndex: Int?
        var firstTimestamp: Double?
        var lastTimestamp: Double?

        try forEachNonEmptyLine(in: fileURL) { [self] lineData, lineNumber in
            let envelope: Envelope
            do {
                envelope = try decoder.decode(Envelope.self, from: lineData)
            } catch {
                throw ScanSessionReplayError.malformedJSON(line: lineNumber)
            }

            guard envelope.schemaVersion == Self.supportedSchemaVersion else {
                throw ScanSessionReplayError.unsupportedSchemaVersion(
                    line: lineNumber,
                    found: envelope.schemaVersion
                )
            }
            if footer != nil {
                if envelope.recordType == "sessionFooter" {
                    throw ScanSessionReplayError.duplicateFooter(line: lineNumber)
                }
                throw ScanSessionReplayError.recordAfterFooter(line: lineNumber)
            }

            switch envelope.recordType {
            case "sessionHeader":
                guard header == nil else {
                    throw ScanSessionReplayError.duplicateHeader(line: lineNumber)
                }
                guard nonEmptyRecordCount == 0 else {
                    throw ScanSessionReplayError.headerNotFirst(line: lineNumber)
                }
                let decodedHeader = try decode(HeaderRecord.self, from: lineData, line: lineNumber)
                try validateHeader(decodedHeader, line: lineNumber)
                header = decodedHeader

            case "frameObservation":
                guard let header else {
                    throw ScanSessionReplayError.frameBeforeHeader(line: lineNumber)
                }
                let frameRecord = try decode(FrameRecord.self, from: lineData, line: lineNumber)
                let frame = frameRecord.frame
                if let previous = lastFrameIndex, frame.frameIndex <= previous {
                    throw ScanSessionReplayError.nonIncreasingFrameIndex(
                        line: lineNumber,
                        previous: previous,
                        current: frame.frameIndex
                    )
                }
                if let timestamp = frame.timestampSeconds {
                    guard timestamp.isFinite else {
                        throw ScanSessionReplayError.invalidFrame(
                            line: lineNumber,
                            frameIndex: frame.frameIndex,
                            reason: "timestampSeconds is non-finite"
                        )
                    }
                    firstTimestamp = firstTimestamp ?? timestamp
                    lastTimestamp = timestamp
                }
                guard frame.cameraProfileId == header.cameraProfileId,
                      frame.cameraProfileName == header.cameraProfileName
                else {
                    throw ScanSessionReplayError.invalidFrame(
                        line: lineNumber,
                        frameIndex: frame.frameIndex,
                        reason: "camera profile differs from sessionHeader"
                    )
                }

                let poseResults = try frame.markerObservations.enumerated().map {
                    try reconstructPoseResult(
                        from: $0.element,
                        headerMarkerProfile: header.markerProfile,
                        line: lineNumber,
                        frameIndex: frame.frameIndex,
                        markerPosition: $0.offset
                    )
                }
                try onFrame(
                    ScanSessionReplayFrameInput(
                        frameIndex: frame.frameIndex,
                        timestampSeconds: frame.timestampSeconds,
                        poseResults: poseResults
                    )
                )
                framesRead += 1
                markerObservationsReconstructed += poseResults.count
                firstFrameIndex = firstFrameIndex ?? frame.frameIndex
                lastFrameIndex = frame.frameIndex

            case "sessionFooter":
                guard header != nil else {
                    throw ScanSessionReplayError.footerBeforeHeader(line: lineNumber)
                }
                guard footer == nil else {
                    throw ScanSessionReplayError.duplicateFooter(line: lineNumber)
                }
                footer = try decode(FooterRecord.self, from: lineData, line: lineNumber)

            default:
                throw ScanSessionReplayError.unknownRecordType(
                    line: lineNumber,
                    recordType: envelope.recordType
                )
            }

            nonEmptyRecordCount += 1
        }

        guard let header else { throw ScanSessionReplayError.missingHeader }
        guard let footer else { throw ScanSessionReplayError.missingFooter }
        try validateFooter(
            footer,
            framesRead: framesRead,
            fileURL: fileURL,
            requireCompletedSession: options.requireCompletedSession
        )

        let metadata = ScanSessionReplayCaptureMetadata(
            sessionIdentifier: header.sessionIdentifier,
            schemaVersion: header.schemaVersion,
            captureStartedTimestamp: header.captureStartedTimestamp,
            deviceModelIdentifier: header.deviceModelIdentifier,
            osVersion: header.osVersion,
            cameraProfileId: header.cameraProfileId,
            cameraProfileName: header.cameraProfileName,
            markerProfile: header.markerProfile,
            expectedPhysicalMarkerIds: header.expectedPhysicalMarkerIds,
            featureFlags: header.featureFlags,
            appVersion: header.appVersion,
            appBuildIdentifier: header.appBuildIdentifier,
            appGitCommitHash: header.appGitCommitHash
        )
        return ScanSessionReplayReadSummary(
            metadata: metadata,
            framesRead: framesRead,
            markerObservationsReconstructed: markerObservationsReconstructed,
            firstFrameIndex: firstFrameIndex,
            lastFrameIndex: lastFrameIndex,
            firstTimestampSeconds: firstTimestamp,
            lastTimestampSeconds: lastTimestamp,
            footerCompleted: footer.completed
        )
    }

    private func decode<T: Decodable>(
        _ type: T.Type,
        from data: Data,
        line: Int
    ) throws -> T {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw ScanSessionReplayError.malformedJSON(line: line)
        }
    }

    private func validateHeader(_ header: HeaderRecord, line: Int) throws {
        guard !header.sessionIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ScanSessionReplayError.invalidHeader(
                line: line,
                reason: "sessionIdentifier is empty"
            )
        }
        guard header.captureStartedTimestamp.isFinite else {
            throw ScanSessionReplayError.invalidHeader(
                line: line,
                reason: "captureStartedTimestamp is non-finite"
            )
        }
        guard MarkerProfile(rawValue: header.markerProfile) != nil else {
            throw ScanSessionReplayError.invalidHeader(
                line: line,
                reason: "unknown markerProfile '\(header.markerProfile)'"
            )
        }
    }

    private func validateFooter(
        _ footer: FooterRecord,
        framesRead: Int,
        fileURL: URL,
        requireCompletedSession: Bool
    ) throws {
        guard footer.captureEndedTimestamp.isFinite else {
            throw ScanSessionReplayError.invalidFooter(
                reason: "captureEndedTimestamp is non-finite"
            )
        }
        guard footer.framesWritten == framesRead else {
            throw ScanSessionReplayError.invalidFooter(
                reason: "framesWritten \(footer.framesWritten) != decoded frames \(framesRead)"
            )
        }
        if requireCompletedSession {
            guard footer.completed else { throw ScanSessionReplayError.incompleteSession }
            guard footer.framesEnqueued == footer.framesWritten else {
                throw ScanSessionReplayError.invalidFooter(
                    reason: "framesEnqueued does not equal framesWritten"
                )
            }
            guard footer.frameWriteFailureCount == 0 else {
                throw ScanSessionReplayError.invalidFooter(reason: "frame write failures were recorded")
            }
            guard footer.frameOrderViolationCount == 0 else {
                throw ScanSessionReplayError.invalidFooter(reason: "frame order violations were recorded")
            }
            guard !footer.limitReached else {
                throw ScanSessionReplayError.invalidFooter(reason: "capture file limit was reached")
            }
        }

        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        } catch {
            throw ScanSessionReplayError.unableToOpenFile(fileURL.path)
        }
        if let actualSize = (attributes[.size] as? NSNumber)?.int64Value,
           actualSize != footer.fileSizeBytes {
            throw ScanSessionReplayError.invalidFooter(
                reason: "fileSizeBytes \(footer.fileSizeBytes) != actual bytes \(actualSize)"
            )
        }
    }

    private func reconstructPoseResult(
        from observation: MarkerFrameObservation,
        headerMarkerProfile: String,
        line: Int,
        frameIndex: Int,
        markerPosition: Int
    ) throws -> PoseResult {
        func invalid(_ reason: String) -> ScanSessionReplayError {
            .invalidPose(
                line: line,
                frameIndex: frameIndex,
                markerPosition: markerPosition,
                reason: reason
            )
        }

        guard let markerProfile = MarkerProfile(rawValue: observation.markerProfileId) else {
            throw invalid("unknown markerProfileId '\(observation.markerProfileId)'")
        }
        guard observation.markerProfileId == headerMarkerProfile else {
            throw invalid("markerProfileId differs from sessionHeader")
        }

        let poseSource: MarkerPoseSource
        switch observation.markerSource {
        case "singleArucoV1":
            poseSource = .singleArucoV1
        case "dualTag":
            poseSource = .dualTag
        case "singleFallback.top":
            guard let tagId = observation.markerSourceTagId else {
                throw invalid("singleFallback.top is missing markerSourceTagId")
            }
            poseSource = .singleFallback(tagId: tagId, role: .top)
        case "singleFallback.bottom":
            guard let tagId = observation.markerSourceTagId else {
                throw invalid("singleFallback.bottom is missing markerSourceTagId")
            }
            poseSource = .singleFallback(tagId: tagId, role: .bottom)
        default:
            throw invalid("unknown markerSource '\(observation.markerSource)'")
        }

        guard observation.rotationMatrixRows.count == 3 else {
            throw invalid("rotationMatrixRows must contain exactly three rows")
        }
        let rotationVector = observation.rotationVector.simdVector
        let translationVector = observation.translationVector.simdVector
        let matrixRows = observation.rotationMatrixRows.map(\.simdVector)
        let rotationMatrix = PoseMath.matrixFromRows(matrixRows[0], matrixRows[1], matrixRows[2])

        guard PoseMath.isFinite(rotationVector) else {
            throw invalid("rotationVector is non-finite")
        }
        guard PoseMath.isFinite(rotationMatrix) else {
            throw invalid("rotationMatrixRows contains non-finite values")
        }
        guard PoseMath.isFinite(translationVector) else {
            throw invalid("translationVector is non-finite")
        }
        guard let reprojectionError = observation.reprojectionError,
              reprojectionError.isFinite
        else {
            throw invalid("reprojectionError is missing or non-finite")
        }
        guard let distanceMm = observation.distanceMm, distanceMm.isFinite else {
            throw invalid("distanceMm is missing or non-finite")
        }
        guard let markerAreaPixels = observation.markerAreaPixels,
              markerAreaPixels.isFinite
        else {
            throw invalid("markerAreaPixels is missing or non-finite")
        }

        return PoseResult(
            markerId: observation.markerId,
            markerProfile: markerProfile,
            poseSource: poseSource,
            rotationVector: rotationVector,
            rotationMatrix: rotationMatrix,
            translationVector: translationVector,
            distanceMm: distanceMm,
            reprojectionError: reprojectionError,
            markerAreaPixels: markerAreaPixels,
            usedPointCount: observation.usedPointCount,
            detectedTopTagId: observation.detectedTopTagId,
            detectedBottomTagId: observation.detectedBottomTagId
        )
    }

    private func forEachNonEmptyLine(
        in fileURL: URL,
        body: (Data, Int) throws -> Void
    ) throws {
        let fileHandle: FileHandle
        do {
            fileHandle = try FileHandle(forReadingFrom: fileURL)
        } catch {
            throw ScanSessionReplayError.unableToOpenFile(fileURL.path)
        }
        defer { try? fileHandle.close() }

        var buffer = Data()
        var lineNumber = 0
        while true {
            let chunk = try fileHandle.read(upToCount: 64 * 1_024) ?? Data()
            if chunk.isEmpty { break }
            buffer.append(chunk)

            while let newlineIndex = buffer.firstIndex(of: 0x0A) {
                let line = Data(buffer[..<newlineIndex])
                buffer.removeSubrange(...newlineIndex)
                lineNumber += 1
                if line.count > maximumLineBytes {
                    throw ScanSessionReplayError.lineTooLong(
                        line: lineNumber,
                        maximumBytes: maximumLineBytes
                    )
                }
                if !Self.isWhitespaceOnly(line) {
                    try body(line, lineNumber)
                }
            }
            if buffer.count > maximumLineBytes {
                throw ScanSessionReplayError.lineTooLong(
                    line: lineNumber + 1,
                    maximumBytes: maximumLineBytes
                )
            }
        }

        if !buffer.isEmpty {
            lineNumber += 1
            if !Self.isWhitespaceOnly(buffer) {
                try body(buffer, lineNumber)
            }
        }
    }

    private static func isWhitespaceOnly(_ data: Data) -> Bool {
        data.allSatisfy { byte in
            byte == 0x20 || byte == 0x09 || byte == 0x0D
        }
    }
}

final class ScanSessionDeterministicReplayRunner {
    static let algorithmIdentifier = "MultiFramePoseAccumulator.scannerDefault.v1"
    static let translationToleranceMm = 1e-9
    static let rotationToleranceDegrees = 1e-9

    private struct ReplayPassResult {
        let readSummary: ScanSessionReplayReadSummary
        let finalPoses: [PoseResult]
    }

    private let readerFactory: () -> ScanSessionSchemaV1Reader
    private let accumulatorFactory: () -> MultiFramePoseAccumulator

    init(
        readerFactory: @escaping () -> ScanSessionSchemaV1Reader = {
            ScanSessionSchemaV1Reader()
        },
        accumulatorFactory: @escaping () -> MultiFramePoseAccumulator = {
            MultiFramePoseAccumulator()
        }
    ) {
        self.readerFactory = readerFactory
        self.accumulatorFactory = accumulatorFactory
    }

    func verifyDeterminism(
        sessionFileURL: URL,
        options: ScanSessionReplayOptions = .deterministic
    ) throws -> ScanSessionDeterministicReplayResult {
        let replayA = try replayOnce(sessionFileURL: sessionFileURL, options: options)
        let replayB = try replayOnce(sessionFileURL: sessionFileURL, options: options)
        guard replayA.readSummary == replayB.readSummary else {
            throw ScanSessionReplayError.replayPassMetadataMismatch
        }

        let comparison = Self.compare(
            replayA.finalPoses,
            replayB.finalPoses,
            translationToleranceMm: Self.translationToleranceMm,
            rotationToleranceDegrees: Self.rotationToleranceDegrees
        )
        let metadata = replayA.readSummary.metadata
        var provenanceCaveats: [String] = []
        if metadata.appGitCommitHash == nil {
            provenanceCaveats.append("capture appGitCommitHash is unavailable")
        }
        provenanceCaveats.append(
            "schema 1 does not persist the live accumulator final-state snapshot"
        )

        let finalPoses = replayA.finalPoses
            .sorted { $0.markerId < $1.markerId }
            .map(Self.finalPoseSummary)
        let summary = ScanSessionDeterministicReplaySummary(
            sessionIdentifier: metadata.sessionIdentifier,
            schemaVersion: metadata.schemaVersion,
            appGitCommitHash: metadata.appGitCommitHash,
            appVersion: metadata.appVersion,
            appBuildIdentifier: metadata.appBuildIdentifier,
            replayAlgorithmIdentifier: Self.algorithmIdentifier,
            replayUsesRandomness: false,
            framesReplayed: replayA.readSummary.framesRead,
            markerObservationsReconstructed:
                replayA.readSummary.markerObservationsReconstructed,
            finalMarkerIds: finalPoses.map(\.markerId),
            finalPoses: finalPoses,
            determinism: comparison,
            integrityResult: "valid",
            provenanceCaveats: provenanceCaveats,
            liveVsReplayDirectComparison: "unavailable"
        )
        return ScanSessionDeterministicReplayResult(
            summary: summary,
            replayAFinalPoses: replayA.finalPoses,
            replayBFinalPoses: replayB.finalPoses
        )
    }

    private func replayOnce(
        sessionFileURL: URL,
        options: ScanSessionReplayOptions
    ) throws -> ReplayPassResult {
        let reader = readerFactory()
        let accumulator = accumulatorFactory()
        var finalPoses: [PoseResult] = []
        let readSummary = try reader.read(from: sessionFileURL, options: options) { frame in
            finalPoses = accumulator.update(with: frame.poseResults)
        }
        return ReplayPassResult(readSummary: readSummary, finalPoses: finalPoses)
    }

    private static func compare(
        _ replayA: [PoseResult],
        _ replayB: [PoseResult],
        translationToleranceMm: Double,
        rotationToleranceDegrees: Double
    ) -> ScanSessionReplayDeterminismComparison {
        let posesA = Dictionary(uniqueKeysWithValues: replayA.map { ($0.markerId, $0) })
        let posesB = Dictionary(uniqueKeysWithValues: replayB.map { ($0.markerId, $0) })
        let idsA = posesA.keys.sorted()
        let idsB = posesB.keys.sorted()
        let setA = Set(idsA)
        let setB = Set(idsB)
        let commonIds = setA.intersection(setB).sorted()
        let markerComparisons = commonIds.compactMap { markerId -> ScanSessionReplayMarkerComparison? in
            guard let poseA = posesA[markerId], let poseB = posesB[markerId] else { return nil }
            return ScanSessionReplayMarkerComparison(
                markerId: markerId,
                translationDeltaMm: simd_distance(
                    poseA.translationVector,
                    poseB.translationVector
                ),
                rotationDeltaDegrees: rotationAngularDistanceDegrees(
                    poseA.rotationMatrix,
                    poseB.rotationMatrix
                )
            )
        }
        let translationDeltas = markerComparisons.map(\.translationDeltaMm)
        let rotationDeltas = markerComparisons.map(\.rotationDeltaDegrees)
        let meanTranslation = mean(translationDeltas)
        let maxTranslation = translationDeltas.max() ?? 0
        let meanRotation = mean(rotationDeltas)
        let maxRotation = rotationDeltas.max() ?? 0
        let missingFromA = setB.subtracting(setA).sorted()
        let missingFromB = setA.subtracting(setB).sorted()
        let deterministic = missingFromA.isEmpty &&
            missingFromB.isEmpty &&
            markerComparisons.allSatisfy {
                $0.translationDeltaMm.isFinite &&
                    $0.rotationDeltaDegrees.isFinite &&
                    $0.translationDeltaMm <= translationToleranceMm &&
                    $0.rotationDeltaDegrees <= rotationToleranceDegrees
            }

        return ScanSessionReplayDeterminismComparison(
            replayAMarkerIds: idsA,
            replayBMarkerIds: idsB,
            missingFromReplayA: missingFromA,
            missingFromReplayB: missingFromB,
            markers: markerComparisons,
            comparedMarkerCount: markerComparisons.count,
            meanTranslationDeltaMm: meanTranslation,
            maxTranslationDeltaMm: maxTranslation,
            meanRotationDeltaDegrees: meanRotation,
            maxRotationDeltaDegrees: maxRotation,
            translationToleranceMm: translationToleranceMm,
            rotationToleranceDegrees: rotationToleranceDegrees,
            replayDeterministic: deterministic
        )
    }

    private static func rotationAngularDistanceDegrees(
        _ lhs: simd_double3x3,
        _ rhs: simd_double3x3
    ) -> Double {
        guard PoseMath.isFinite(lhs), PoseMath.isFinite(rhs) else { return .infinity }
        if lhs.columns.0 == rhs.columns.0,
           lhs.columns.1 == rhs.columns.1,
           lhs.columns.2 == rhs.columns.2 {
            return 0
        }
        let relativeRotation = simd_transpose(lhs) * rhs
        let trace = PoseMath.matrixElement(relativeRotation, row: 0, column: 0) +
            PoseMath.matrixElement(relativeRotation, row: 1, column: 1) +
            PoseMath.matrixElement(relativeRotation, row: 2, column: 2)
        let cosine = min(max((trace - 1.0) / 2.0, -1.0), 1.0)
        let radians = acos(cosine)
        return radians.isFinite ? radians * 180.0 / Double.pi : .infinity
    }

    private static func mean(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func finalPoseSummary(_ pose: PoseResult) -> ScanSessionReplayFinalPoseSummary {
        let source: String
        let sourceTagId: Int?
        switch pose.poseSource {
        case .singleArucoV1:
            source = "singleArucoV1"
            sourceTagId = nil
        case .dualTag:
            source = "dualTag"
            sourceTagId = nil
        case let .singleFallback(tagId, role):
            source = role == .top ? "singleFallback.top" : "singleFallback.bottom"
            sourceTagId = tagId
        }
        return ScanSessionReplayFinalPoseSummary(
            markerId: pose.markerId,
            markerProfile: pose.markerProfile.rawValue,
            markerSource: source,
            markerSourceTagId: sourceTagId,
            rotationVector: ObservationPoint3D(pose.rotationVector),
            rotationMatrixRows: ObservationPoint3D.rows(of: pose.rotationMatrix),
            translationVector: ObservationPoint3D(pose.translationVector),
            reprojectionError: pose.reprojectionError,
            distanceMm: pose.distanceMm,
            markerAreaPixels: pose.markerAreaPixels,
            usedPointCount: pose.usedPointCount,
            detectedTopTagId: pose.detectedTopTagId,
            detectedBottomTagId: pose.detectedBottomTagId
        )
    }
}

private extension ObservationPoint3D {
    init(_ vector: SIMD3<Double>) {
        self.init(x: vector.x, y: vector.y, z: vector.z)
    }

    var simdVector: SIMD3<Double> {
        SIMD3(x, y, z)
    }

    static func rows(of matrix: simd_double3x3) -> [ObservationPoint3D] {
        [
            ObservationPoint3D(
                x: matrix.columns.0.x,
                y: matrix.columns.1.x,
                z: matrix.columns.2.x
            ),
            ObservationPoint3D(
                x: matrix.columns.0.y,
                y: matrix.columns.1.y,
                z: matrix.columns.2.y
            ),
            ObservationPoint3D(
                x: matrix.columns.0.z,
                y: matrix.columns.1.z,
                z: matrix.columns.2.z
            )
        ]
    }
}
