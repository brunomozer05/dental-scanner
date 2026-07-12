import Foundation

struct ScanSessionObservationHeader: Sendable {
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

struct ScanSessionObservationCaptureSnapshot: Equatable, Sendable {
    let enabled: Bool
    let schemaVersion: Int
    let active: Bool
    let completed: Bool
    let framesEnqueued: Int
    let framesWritten: Int
    let frameWriteFailureCount: Int
    let frameOrderViolationCount: Int
    let limitReached: Bool
    let fileSizeBytes: Int64
    let lastEnqueuedFrameIndex: Int?
    let lastWrittenFrameIndex: Int?
    let fileAvailable: Bool
    let filename: String?

    static func inactive(enabled: Bool, schemaVersion: Int) -> Self {
        Self(
            enabled: enabled,
            schemaVersion: schemaVersion,
            active: false,
            completed: false,
            framesEnqueued: 0,
            framesWritten: 0,
            frameWriteFailureCount: 0,
            frameOrderViolationCount: 0,
            limitReached: false,
            fileSizeBytes: 0,
            lastEnqueuedFrameIndex: nil,
            lastWrittenFrameIndex: nil,
            fileAvailable: false,
            filename: nil
        )
    }
}

final class ScanSessionObservationWriter {
    static let schemaVersion = 1
    static let defaultMaximumFileSizeBytes: Int64 = 128 * 1_024 * 1_024

    private enum RecordType: String, Codable {
        case sessionHeader
        case frameObservation
        case sessionFooter
    }

    private struct HeaderRecord: Codable {
        let recordType: RecordType
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

    private struct FrameRecord: Codable {
        let recordType: RecordType
        let schemaVersion: Int
        let frame: FrameObservation
    }

    private struct FooterRecord: Codable {
        let recordType: RecordType
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

    private let writerQueue = DispatchQueue(
        label: "DentalScanner.ScanSessionObservationWriter",
        qos: .utility
    )
    private let stateLock = NSLock()
    private let enabled: Bool
    private let maximumFileSizeBytes: Int64
    private let maximumPendingFrameWrites: Int
    private let footerReserveBytes: Int64 = 4_096
    private let synchronizeIntervalFrames = 60
    private let encoder: JSONEncoder

    private var currentToken: UUID?
    private var acceptingFrames = false
    private var pendingFrameWrites = 0
    private var acceptedFramesEnqueued = 0
    private var acceptedFrameOrderViolationCount = 0
    private var lastAcceptedFrameIndex: Int?
    private var publicSnapshot: ScanSessionObservationCaptureSnapshot

    // The following state is confined to writerQueue.
    private var writerToken: UUID?
    private var fileHandle: FileHandle?
    private var fileURL: URL?
    private var framesEnqueued = 0
    private var framesWritten = 0
    private var frameWriteFailureCount = 0
    private var frameOrderViolationCount = 0
    private var limitReached = false
    private var fileSizeBytes: Int64 = 0
    private var lastEnqueuedFrameIndex: Int?
    private var lastWrittenFrameIndex: Int?
    private var integrityFailed = false

    init(
        enabled: Bool,
        maximumFileSizeBytes: Int64 = ScanSessionObservationWriter.defaultMaximumFileSizeBytes,
        maximumPendingFrameWrites: Int = 240
    ) {
        self.enabled = enabled
        self.maximumFileSizeBytes = max(maximumFileSizeBytes, 16_384)
        self.maximumPendingFrameWrites = max(maximumPendingFrameWrites, 1)
        self.publicSnapshot = .inactive(
            enabled: enabled,
            schemaVersion: Self.schemaVersion
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: "Infinity",
            negativeInfinity: "-Infinity",
            nan: "NaN"
        )
        self.encoder = encoder
    }

    func startSession(
        header: ScanSessionObservationHeader,
        fileURL: URL
    ) {
        guard enabled else { return }

        let token = UUID()
        stateLock.lock()
        currentToken = token
        acceptingFrames = true
        pendingFrameWrites = 0
        acceptedFramesEnqueued = 0
        acceptedFrameOrderViolationCount = 0
        lastAcceptedFrameIndex = nil
        publicSnapshot = ScanSessionObservationCaptureSnapshot(
            enabled: true,
            schemaVersion: Self.schemaVersion,
            active: true,
            completed: false,
            framesEnqueued: 0,
            framesWritten: 0,
            frameWriteFailureCount: 0,
            frameOrderViolationCount: 0,
            limitReached: false,
            fileSizeBytes: 0,
            lastEnqueuedFrameIndex: nil,
            lastWrittenFrameIndex: nil,
            fileAvailable: false,
            filename: fileURL.lastPathComponent
        )
        writerQueue.async { [weak self] in
            self?.startSessionOnWriterQueue(token: token, header: header, fileURL: fileURL)
        }
        stateLock.unlock()
    }

    func enqueue(_ observation: FrameObservation) {
        guard enabled else { return }

        stateLock.lock()
        guard let token = currentToken, acceptingFrames else {
            stateLock.unlock()
            return
        }
        guard pendingFrameWrites < maximumPendingFrameWrites else {
            acceptingFrames = false
            publicSnapshot = replacingSnapshot(
                publicSnapshot,
                active: true,
                completed: false,
                frameWriteFailureCount: publicSnapshot.frameWriteFailureCount + 1
            )
            writerQueue.async { [weak self] in
                self?.markOperationalFailureOnWriterQueue(token: token)
            }
            stateLock.unlock()
            return
        }

        let orderViolation = lastAcceptedFrameIndex.map {
            observation.frameIndex <= $0
        } ?? false
        pendingFrameWrites += 1
        acceptedFramesEnqueued += 1
        acceptedFrameOrderViolationCount += orderViolation ? 1 : 0
        lastAcceptedFrameIndex = observation.frameIndex
        publicSnapshot = replacingSnapshot(
            publicSnapshot,
            framesEnqueued: acceptedFramesEnqueued,
            frameOrderViolationCount: acceptedFrameOrderViolationCount,
            lastEnqueuedFrameIndex: observation.frameIndex
        )
        writerQueue.async { [weak self] in
            self?.writeFrameOnWriterQueue(
                observation,
                token: token,
                orderViolation: orderViolation
            )
        }
        stateLock.unlock()
    }

    func finalizeSession(
        completed: Bool,
        captureEndedTimestamp: Double,
        completion: ((ScanSessionObservationCaptureSnapshot) -> Void)? = nil
    ) {
        guard enabled else {
            completion?(.inactive(enabled: false, schemaVersion: Self.schemaVersion))
            return
        }

        stateLock.lock()
        let token = currentToken
        acceptingFrames = false
        guard let token else {
            stateLock.unlock()
            completion?(snapshot())
            return
        }

        writerQueue.async { [weak self] in
            guard let self else { return }
            let finalSnapshot = self.finalizeOnWriterQueue(
                token: token,
                requestedCompleted: completed,
                captureEndedTimestamp: captureEndedTimestamp
            )
            completion?(finalSnapshot)
        }
        stateLock.unlock()
    }

    func snapshot() -> ScanSessionObservationCaptureSnapshot {
        stateLock.lock()
        defer { stateLock.unlock() }
        return publicSnapshot
    }

    func recordSessionStartFailure() {
        guard enabled else { return }
        stateLock.lock()
        currentToken = nil
        acceptingFrames = false
        pendingFrameWrites = 0
        acceptedFramesEnqueued = 0
        acceptedFrameOrderViolationCount = 0
        lastAcceptedFrameIndex = nil
        publicSnapshot = ScanSessionObservationCaptureSnapshot(
            enabled: true,
            schemaVersion: Self.schemaVersion,
            active: false,
            completed: false,
            framesEnqueued: 0,
            framesWritten: 0,
            frameWriteFailureCount: 1,
            frameOrderViolationCount: 0,
            limitReached: false,
            fileSizeBytes: 0,
            lastEnqueuedFrameIndex: nil,
            lastWrittenFrameIndex: nil,
            fileAvailable: false,
            filename: nil
        )
        stateLock.unlock()
    }

    private func startSessionOnWriterQueue(
        token: UUID,
        header: ScanSessionObservationHeader,
        fileURL: URL
    ) {
        if writerToken != nil {
            _ = finalizeCurrentWriterState(
                requestedCompleted: false,
                captureEndedTimestamp: header.captureStartedTimestamp
            )
        }

        resetWriterState(token: token, fileURL: fileURL)

        do {
            let directoryURL = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            guard FileManager.default.createFile(atPath: fileURL.path, contents: nil) else {
                throw CocoaError(.fileWriteUnknown)
            }
            fileHandle = try FileHandle(forWritingTo: fileURL)
            let record = HeaderRecord(
                recordType: .sessionHeader,
                schemaVersion: Self.schemaVersion,
                sessionIdentifier: header.sessionIdentifier,
                captureStartedTimestamp: header.captureStartedTimestamp,
                deviceModelIdentifier: header.deviceModelIdentifier,
                osVersion: header.osVersion,
                cameraProfileId: header.cameraProfileId,
                cameraProfileName: header.cameraProfileName,
                markerProfile: header.markerProfile,
                expectedPhysicalMarkerIds: header.expectedPhysicalMarkerIds,
                appVersion: header.appVersion,
                appBuildIdentifier: header.appBuildIdentifier,
                appGitCommitHash: header.appGitCommitHash,
                featureFlags: header.featureFlags
            )
            try appendRecordLine(record)
            publishWriterSnapshot(active: true, completed: false)
        } catch {
            recordWriteFailure()
            closeFileHandle()
            stopAcceptingFrames(token: token)
            publishWriterSnapshot(active: false, completed: false)
        }
    }

    private func writeFrameOnWriterQueue(
        _ observation: FrameObservation,
        token: UUID,
        orderViolation: Bool
    ) {
        defer { decrementPendingFrameWrite(token: token) }
        guard writerToken == token else { return }
        framesEnqueued += 1
        lastEnqueuedFrameIndex = observation.frameIndex
        if orderViolation {
            frameOrderViolationCount += 1
            integrityFailed = true
        }
        guard fileHandle != nil, !integrityFailed else {
            publishWriterSnapshot(active: fileHandle != nil, completed: false)
            return
        }

        do {
            let record = FrameRecord(
                recordType: .frameObservation,
                schemaVersion: Self.schemaVersion,
                frame: observation
            )
            let line = try encodedLine(record)
            guard fileSizeBytes + Int64(line.count) <= maximumFileSizeBytes - footerReserveBytes else {
                limitReached = true
                integrityFailed = true
                stopAcceptingFrames(token: token)
                publishWriterSnapshot(active: true, completed: false)
                return
            }

            try fileHandle?.write(contentsOf: line)
            fileSizeBytes += Int64(line.count)
            framesWritten += 1
            lastWrittenFrameIndex = observation.frameIndex
            if framesWritten.isMultiple(of: synchronizeIntervalFrames) {
                try fileHandle?.synchronize()
            }
            publishWriterSnapshot(active: true, completed: false)
        } catch {
            recordWriteFailure()
            stopAcceptingFrames(token: token)
            publishWriterSnapshot(active: true, completed: false)
        }
    }

    private func finalizeOnWriterQueue(
        token: UUID,
        requestedCompleted: Bool,
        captureEndedTimestamp: Double
    ) -> ScanSessionObservationCaptureSnapshot {
        guard writerToken == token else {
            return snapshot()
        }
        return finalizeCurrentWriterState(
            requestedCompleted: requestedCompleted,
            captureEndedTimestamp: captureEndedTimestamp
        )
    }

    private func finalizeCurrentWriterState(
        requestedCompleted: Bool,
        captureEndedTimestamp: Double
    ) -> ScanSessionObservationCaptureSnapshot {
        guard writerToken != nil else { return snapshot() }

        if fileHandle != nil {
            do {
                try fileHandle?.synchronize()
            } catch {
                recordWriteFailure()
            }

            let completeBeforeFooter = requestedCompleted &&
                !integrityFailed &&
                frameWriteFailureCount == 0 &&
                frameOrderViolationCount == 0 &&
                !limitReached &&
                framesEnqueued == framesWritten

            do {
                let footerLine = try encodedFooterLine(
                    completed: completeBeforeFooter,
                    captureEndedTimestamp: captureEndedTimestamp
                )
                guard fileSizeBytes + Int64(footerLine.count) <= maximumFileSizeBytes else {
                    throw CocoaError(.fileWriteOutOfSpace)
                }
                try fileHandle?.write(contentsOf: footerLine)
                fileSizeBytes += Int64(footerLine.count)
                try fileHandle?.synchronize()
            } catch {
                recordWriteFailure()
            }
        }

        closeFileHandle()
        let completed = requestedCompleted &&
            !integrityFailed &&
            frameWriteFailureCount == 0 &&
            frameOrderViolationCount == 0 &&
            !limitReached &&
            framesEnqueued == framesWritten
        let finalSnapshot = publishWriterSnapshot(active: false, completed: completed)
        writerToken = nil
        fileURL = nil
        return finalSnapshot
    }

    private func encodedFooterLine(
        completed: Bool,
        captureEndedTimestamp: Double
    ) throws -> Data {
        var finalSize = fileSizeBytes
        var line = Data()
        for _ in 0..<4 {
            let record = FooterRecord(
                recordType: .sessionFooter,
                schemaVersion: Self.schemaVersion,
                completed: completed,
                captureEndedTimestamp: captureEndedTimestamp,
                framesEnqueued: framesEnqueued,
                framesWritten: framesWritten,
                frameWriteFailureCount: frameWriteFailureCount,
                frameOrderViolationCount: frameOrderViolationCount,
                limitReached: limitReached,
                fileSizeBytes: finalSize
            )
            line = try encodedLine(record)
            let nextSize = fileSizeBytes + Int64(line.count)
            if nextSize == finalSize { break }
            finalSize = nextSize
        }
        return line
    }

    private func appendRecordLine<T: Encodable>(_ record: T) throws {
        let line = try encodedLine(record)
        guard fileSizeBytes + Int64(line.count) <= maximumFileSizeBytes - footerReserveBytes else {
            throw CocoaError(.fileWriteOutOfSpace)
        }
        try fileHandle?.write(contentsOf: line)
        fileSizeBytes += Int64(line.count)
    }

    private func encodedLine<T: Encodable>(_ record: T) throws -> Data {
        var data = try encoder.encode(record)
        data.append(0x0A)
        return data
    }

    private func resetWriterState(token: UUID, fileURL: URL) {
        writerToken = token
        self.fileURL = fileURL
        fileHandle = nil
        framesEnqueued = 0
        framesWritten = 0
        frameWriteFailureCount = 0
        frameOrderViolationCount = 0
        limitReached = false
        fileSizeBytes = 0
        lastEnqueuedFrameIndex = nil
        lastWrittenFrameIndex = nil
        integrityFailed = false
    }

    private func recordWriteFailure() {
        frameWriteFailureCount += 1
        integrityFailed = true
    }

    private func markOperationalFailureOnWriterQueue(token: UUID) {
        guard writerToken == token else { return }
        recordWriteFailure()
        publishWriterSnapshot(active: true, completed: false)
    }

    private func stopAcceptingFrames(token: UUID) {
        stateLock.lock()
        if currentToken == token {
            acceptingFrames = false
        }
        stateLock.unlock()
    }

    private func decrementPendingFrameWrite(token: UUID) {
        stateLock.lock()
        if currentToken == token {
            pendingFrameWrites = max(pendingFrameWrites - 1, 0)
        }
        stateLock.unlock()
    }

    private func closeFileHandle() {
        if let fileHandle {
            do {
                try fileHandle.close()
            } catch {
                recordWriteFailure()
            }
        }
        fileHandle = nil
    }

    @discardableResult
    private func publishWriterSnapshot(
        active: Bool,
        completed: Bool
    ) -> ScanSessionObservationCaptureSnapshot {
        let filename = fileURL?.lastPathComponent
        let fileAvailable = fileURL.map {
            FileManager.default.fileExists(atPath: $0.path)
        } ?? false
        let writerSnapshot = ScanSessionObservationCaptureSnapshot(
            enabled: enabled,
            schemaVersion: Self.schemaVersion,
            active: active,
            completed: completed,
            framesEnqueued: framesEnqueued,
            framesWritten: framesWritten,
            frameWriteFailureCount: frameWriteFailureCount,
            frameOrderViolationCount: frameOrderViolationCount,
            limitReached: limitReached,
            fileSizeBytes: fileSizeBytes,
            lastEnqueuedFrameIndex: lastEnqueuedFrameIndex,
            lastWrittenFrameIndex: lastWrittenFrameIndex,
            fileAvailable: fileAvailable,
            filename: filename
        )

        stateLock.lock()
        if currentToken == writerToken {
            publicSnapshot = ScanSessionObservationCaptureSnapshot(
                enabled: writerSnapshot.enabled,
                schemaVersion: writerSnapshot.schemaVersion,
                active: writerSnapshot.active,
                completed: writerSnapshot.completed,
                framesEnqueued: acceptedFramesEnqueued,
                framesWritten: writerSnapshot.framesWritten,
                frameWriteFailureCount: writerSnapshot.frameWriteFailureCount,
                frameOrderViolationCount: acceptedFrameOrderViolationCount,
                limitReached: writerSnapshot.limitReached,
                fileSizeBytes: writerSnapshot.fileSizeBytes,
                lastEnqueuedFrameIndex: lastAcceptedFrameIndex,
                lastWrittenFrameIndex: writerSnapshot.lastWrittenFrameIndex,
                fileAvailable: writerSnapshot.fileAvailable,
                filename: writerSnapshot.filename
            )
        }
        let result = currentToken == writerToken ? publicSnapshot : writerSnapshot
        stateLock.unlock()
        return result
    }

    private func replacingSnapshot(
        _ source: ScanSessionObservationCaptureSnapshot,
        active: Bool? = nil,
        completed: Bool? = nil,
        framesEnqueued: Int? = nil,
        frameWriteFailureCount: Int? = nil,
        frameOrderViolationCount: Int? = nil,
        lastEnqueuedFrameIndex: Int? = nil
    ) -> ScanSessionObservationCaptureSnapshot {
        ScanSessionObservationCaptureSnapshot(
            enabled: source.enabled,
            schemaVersion: source.schemaVersion,
            active: active ?? source.active,
            completed: completed ?? source.completed,
            framesEnqueued: framesEnqueued ?? source.framesEnqueued,
            framesWritten: source.framesWritten,
            frameWriteFailureCount: frameWriteFailureCount ?? source.frameWriteFailureCount,
            frameOrderViolationCount: frameOrderViolationCount ?? source.frameOrderViolationCount,
            limitReached: source.limitReached,
            fileSizeBytes: source.fileSizeBytes,
            lastEnqueuedFrameIndex: lastEnqueuedFrameIndex ?? source.lastEnqueuedFrameIndex,
            lastWrittenFrameIndex: source.lastWrittenFrameIndex,
            fileAvailable: source.fileAvailable,
            filename: source.filename
        )
    }
}
