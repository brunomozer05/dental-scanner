import Foundation

struct ScanItem: Identifiable, Codable {
    let id: UUID
    var name: String
    let date: Date
    let fileURL: URL
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
    func saveScan(stlData: Data, name: String) throws -> ScanItem {
        let documentsURL = try documentsDirectoryURL()
        let fileURL = uniqueFileURL(
            in: documentsURL,
            requestedFileName: normalizedSTLFileName(from: name)
        )

        try stlData.write(to: fileURL, options: .atomic)

        let scan = ScanItem(
            id: UUID(),
            name: fileURL.lastPathComponent,
            date: Date(),
            fileURL: fileURL
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

        let scans = loadScans().filter { $0.id != scan.id }
        persist(scans)
    }

    static func automaticScanFileName(date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm"

        return "Scan_\(formatter.string(from: date)).stl"
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
