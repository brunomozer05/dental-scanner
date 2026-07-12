import Foundation

struct ScanItem: Identifiable, Codable {
    let id: UUID
    var name: String
    let date: Date
    let fileURL: URL
    let reportURL: URL?
    let diagnosticsURL: URL?
    let sessionCaptureURL: URL?

    init(
        id: UUID,
        name: String,
        date: Date,
        fileURL: URL,
        reportURL: URL? = nil,
        diagnosticsURL: URL? = nil,
        sessionCaptureURL: URL? = nil
    ) {
        self.id = id
        self.name = name
        self.date = date
        self.fileURL = fileURL
        self.reportURL = reportURL
        self.diagnosticsURL = diagnosticsURL
        self.sessionCaptureURL = sessionCaptureURL
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case date
        case fileURL
        case reportURL
        case diagnosticsURL
        case sessionCaptureURL
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        date = try container.decode(Date.self, forKey: .date)
        fileURL = try container.decode(URL.self, forKey: .fileURL)
        reportURL = try container.decodeIfPresent(URL.self, forKey: .reportURL)
        diagnosticsURL = try container.decodeIfPresent(URL.self, forKey: .diagnosticsURL)
        sessionCaptureURL = try container.decodeIfPresent(URL.self, forKey: .sessionCaptureURL)
    }
}

final class ScanStorageManager {
    enum StorageError: LocalizedError {
        case documentsDirectoryUnavailable
        case unableToEncodeSTL

        var errorDescription: String? {
            switch self {
            case .documentsDirectoryUnavailable:
                return "Nao foi possivel acessar a pasta Documents."
            case .unableToEncodeSTL:
                return "Nao foi possivel codificar o STL."
            }
        }
    }

    private let userDefaults: UserDefaults
    private let fileManager: FileManager
    private let storageKey = "DentalScanner.savedScans"

    init(
        userDefaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) {
        self.userDefaults = userDefaults
        self.fileManager = fileManager
    }

    @discardableResult
    func saveScan(
        stlData: Data,
        name: String,
        technicalReport: ScanTechnicalReport? = nil,
        diagnostics: ScanDiagnosticsSnapshot? = nil,
        sessionCaptureURL: URL? = nil
    ) throws -> ScanItem {
        let documentsURL = try documentsDirectoryURL()
        let fileURL = uniqueFileURL(
            in: documentsURL,
            requestedFileName: normalizedSTLFileName(from: name)
        )

        try stlData.write(to: fileURL, options: .atomic)
        let diagnosticsURL = try saveDiagnosticsIfNeeded(
            diagnostics,
            forSTLFileURL: fileURL
        )
        let reportURL = try saveTechnicalReportIfNeeded(
            technicalReport,
            forSTLFileURL: fileURL,
            diagnosticsURL: diagnosticsURL
        )

        let scan = ScanItem(
            id: UUID(),
            name: fileURL.lastPathComponent,
            date: Date(),
            fileURL: fileURL,
            reportURL: reportURL,
            diagnosticsURL: diagnosticsURL,
            sessionCaptureURL: sessionCaptureURL
        )
        var scans = loadScans()
        scans.insert(scan, at: 0)
        persist(scans)

        return scan
    }

    func loadScans() -> [ScanItem] {
        guard let data = userDefaults.data(forKey: storageKey),
              let scans = try? JSONDecoder().decode([ScanItem].self, from: data)
        else {
            return []
        }

        return scans
            .filter { fileManager.fileExists(atPath: $0.fileURL.path) }
            .sorted { $0.date > $1.date }
    }

    func deleteScan(_ scan: ScanItem) {
        if fileManager.fileExists(atPath: scan.fileURL.path) {
            try? fileManager.removeItem(at: scan.fileURL)
        }

        if let reportURL = scan.reportURL,
           fileManager.fileExists(atPath: reportURL.path) {
            try? fileManager.removeItem(at: reportURL)
        }

        if let diagnosticsURL = scan.diagnosticsURL,
           fileManager.fileExists(atPath: diagnosticsURL.path) {
            try? fileManager.removeItem(at: diagnosticsURL)
        }

        if let sessionCaptureURL = scan.sessionCaptureURL,
           fileManager.fileExists(atPath: sessionCaptureURL.path) {
            try? fileManager.removeItem(at: sessionCaptureURL)
        }

        let scans = loadScans().filter { $0.id != scan.id }
        persist(scans)
    }

    static func automaticScanFileName(date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm"

        return "Scan_\(formatter.string(from: date)).stl"
    }

    func makeSessionObservationCaptureFileURL(date: Date = Date()) throws -> URL {
        let documentsURL = try documentsDirectoryURL()
        let scanBaseName = Self.automaticScanFileName(date: date)
            .replacingOccurrences(of: ".stl", with: "")
        return uniqueFileURL(
            in: documentsURL,
            requestedFileName: "\(scanBaseName)_session.ndjson"
        )
    }

    private func documentsDirectoryURL() throws -> URL {
        guard let documentsURL = fileManager.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else {
            throw StorageError.documentsDirectoryUnavailable
        }

        return documentsURL
    }

    private func persist(_ scans: [ScanItem]) {
        guard let data = try? JSONEncoder().encode(scans) else {
            return
        }

        userDefaults.set(data, forKey: storageKey)
    }

    private func normalizedSTLFileName(from name: String) -> String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackName = Self.automaticScanFileName()
        let rawFileName = trimmedName.isEmpty ? fallbackName : trimmedName
        let safeFileName = rawFileName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")

        if safeFileName.lowercased().hasSuffix(".stl") {
            return safeFileName
        }

        return "\(safeFileName).stl"
    }

    private func saveTechnicalReportIfNeeded(
        _ report: ScanTechnicalReport?,
        forSTLFileURL stlFileURL: URL,
        diagnosticsURL: URL?
    ) throws -> URL? {
        guard var report else {
            return nil
        }

        report.stlFileName = stlFileURL.lastPathComponent
        report.diagnosticsFileName = diagnosticsURL?.lastPathComponent
        let reportFileName = "\(stlFileURL.deletingPathExtension().lastPathComponent)_report.json"
        let reportURL = stlFileURL
            .deletingLastPathComponent()
            .appendingPathComponent(reportFileName)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let reportData = try encoder.encode(report)
        try reportData.write(to: reportURL, options: .atomic)

        return reportURL
    }

    private func saveDiagnosticsIfNeeded(
        _ diagnostics: ScanDiagnosticsSnapshot?,
        forSTLFileURL stlFileURL: URL
    ) throws -> URL? {
        guard let diagnostics else {
            return nil
        }

        let diagnosticsFileName = "\(stlFileURL.deletingPathExtension().lastPathComponent)_diagnostics.json"
        let diagnosticsURL = stlFileURL
            .deletingLastPathComponent()
            .appendingPathComponent(diagnosticsFileName)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let diagnosticsData = try encoder.encode(diagnostics)
        try diagnosticsData.write(to: diagnosticsURL, options: .atomic)

        return diagnosticsURL
    }

    private func uniqueFileURL(
        in directoryURL: URL,
        requestedFileName: String
    ) -> URL {
        let requestedURL = directoryURL.appendingPathComponent(requestedFileName)
        guard fileManager.fileExists(atPath: requestedURL.path) else {
            return requestedURL
        }

        let baseName = requestedURL.deletingPathExtension().lastPathComponent
        let pathExtension = requestedURL.pathExtension

        for index in 1...999 {
            let fileName = "\(baseName)-\(index).\(pathExtension)"
            let candidateURL = directoryURL.appendingPathComponent(fileName)

            if !fileManager.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
        }

        return directoryURL.appendingPathComponent("\(baseName)-\(UUID().uuidString).\(pathExtension)")
    }
}
