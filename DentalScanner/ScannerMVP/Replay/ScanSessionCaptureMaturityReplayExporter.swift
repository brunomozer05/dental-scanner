import Foundation

enum ScanSessionCaptureMaturityReplayExporterError: Error, LocalizedError {
    case outputCollidesWithSourceArtifact

    var errorDescription: String? {
        "Capture maturity replay output collides with a protected source artifact."
    }
}

enum ScanSessionCaptureMaturityReplayExporter {
    static func outputURL(forScanFileURL scanFileURL: URL) -> URL {
        let baseName = scanFileURL.deletingPathExtension().lastPathComponent
        return scanFileURL
            .deletingLastPathComponent()
            .appendingPathComponent(
                "\(baseName)_capture_maturity_replay.json"
            )
    }

    static func encode(
        _ summary: CaptureMaturityReplaySummary
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(summary)
    }

    @discardableResult
    static func write(
        _ summary: CaptureMaturityReplaySummary,
        forScanFileURL scanFileURL: URL,
        protectedSourceURLs: [URL] = []
    ) throws -> URL {
        let outputURL = outputURL(forScanFileURL: scanFileURL)
        let protectedPaths = Set(
            ([scanFileURL] + protectedSourceURLs).map {
                $0.standardizedFileURL.path
            }
        )
        guard !protectedPaths.contains(outputURL.standardizedFileURL.path)
        else {
            throw ScanSessionCaptureMaturityReplayExporterError
                .outputCollidesWithSourceArtifact
        }
        try encode(summary).write(to: outputURL, options: .atomic)
        return outputURL
    }
}
