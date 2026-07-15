import Foundation

enum ScanSessionReplaySummaryExporter {
    static func outputURL(forScanFileURL scanFileURL: URL) -> URL {
        let baseName = scanFileURL.deletingPathExtension().lastPathComponent
        return scanFileURL
            .deletingLastPathComponent()
            .appendingPathComponent("\(baseName)_replay_summary.json")
    }

    static func encode(_ summary: ScanSessionDeterministicReplaySummary) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(summary)
    }

    static func preAccumulationGateABOutputURL(forScanFileURL scanFileURL: URL) -> URL {
        let baseName = scanFileURL.deletingPathExtension().lastPathComponent
        return scanFileURL
            .deletingLastPathComponent()
            .appendingPathComponent("\(baseName)_pregate_ab_replay_summary.json")
    }

    static func encode(
        _ summary: ScanSessionPreAccumulationGateABReplaySummary
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(summary)
    }

    @discardableResult
    static func write(
        _ summary: ScanSessionDeterministicReplaySummary,
        forScanFileURL scanFileURL: URL
    ) throws -> URL {
        let outputURL = outputURL(forScanFileURL: scanFileURL)
        try encode(summary).write(to: outputURL, options: .atomic)
        return outputURL
    }

    @discardableResult
    static func write(
        _ summary: ScanSessionPreAccumulationGateABReplaySummary,
        forScanFileURL scanFileURL: URL
    ) throws -> URL {
        let outputURL = preAccumulationGateABOutputURL(forScanFileURL: scanFileURL)
        try encode(summary).write(to: outputURL, options: .atomic)
        return outputURL
    }
}
