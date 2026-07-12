import SwiftUI

struct ScanListView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var scans: [ScanItem] = []
    @State private var selectedScan: ScanItem?
    @State private var isSelectionModeActive = false
    @State private var selectedScanIDs: Set<ScanItem.ID> = []
    @State private var shareStatusText: String?

    private let storageManager = ScanStorageManager()
    private let fileManager = FileManager.default

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black
                    .ignoresSafeArea(.all)

                if scans.isEmpty {
                    emptyState
                } else {
                    List(scans) { scan in
                        Button {
                            handleScanTap(scan)
                        } label: {
                            ScanRowView(
                                scan: scan,
                                hasReport: reportURLIfAvailable(for: scan) != nil,
                                hasDiagnostics: diagnosticsURLIfAvailable(for: scan) != nil,
                                isSelectionModeActive: isSelectionModeActive,
                                isSelected: selectedScanIDs.contains(scan.id)
                            )
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            scanContextMenu(for: scan)
                        }
                        .listRowBackground(Color.black)
                        .listRowSeparatorTint(Color.white.opacity(0.08))
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            if !isSelectionModeActive {
                                scanSwipeActions(for: scan)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Meus Scans")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                    }
                    .accessibilityLabel("Fechar")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    if !scans.isEmpty {
                        Button {
                            if isSelectionModeActive {
                                exitSelectionMode()
                            } else {
                                enterSelectionMode()
                            }
                        } label: {
                            Text(isSelectionModeActive ? "Cancelar" : "Selecionar")
                                .font(.body.weight(.semibold))
                        }
                    }
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .supportedInterfaceOrientations(.portrait)
        .onAppear(perform: reloadScans)
        .safeAreaInset(edge: .bottom) {
            if !scans.isEmpty {
                bulkShareBar
            }
        }
        .fullScreenCover(item: $selectedScan) { scan in
            STLViewerView(stlFileURL: scan.fileURL)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.58))

            Text("Nenhum scan salvo")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)

            Text("Os STLs exportados aparecem aqui para abrir ou apagar depois.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.white.opacity(0.62))
                .padding(.horizontal, 36)
        }
    }

    private var bulkShareBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isSelectionModeActive {
                selectionSummary

                HStack(spacing: 10) {
                    Button {
                        selectAllScans()
                    } label: {
                        Label("Selecionar todos", systemImage: "checklist")
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)

                    Button {
                        clearSelection()
                    } label: {
                        Label("Limpar", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                    .disabled(selectedScanIDs.isEmpty)
                }

                Button {
                    shareSelectedScans()
                } label: {
                    Label("Compartilhar selecionados", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.23, green: 0.51, blue: 0.96))
                .disabled(selectedScanIDs.isEmpty)
            } else {
                allScansSummary

                Button {
                    shareAllScans()
                } label: {
                    Label("Compartilhar todos STL + Reports + Diagnostics", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.23, green: 0.51, blue: 0.96))

                Menu {
                    Button {
                        shareAllSTLs()
                    } label: {
                        Label("Compartilhar todos STLs", systemImage: "shippingbox")
                    }

                    Button {
                        shareAllReports()
                    } label: {
                        Label("Compartilhar todos Reports JSON", systemImage: "doc.text")
                    }
                    .disabled(allReportURLs.isEmpty)

                    Button {
                        shareAllDiagnostics()
                    } label: {
                        Label("Compartilhar todos Diagnostics JSON", systemImage: "waveform.path.ecg")
                    }
                    .disabled(allDiagnosticsURLs.isEmpty)
                } label: {
                    Label("Mais opcoes de lote", systemImage: "ellipsis.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.white)
            }

            if let shareStatusText {
                Text(shareStatusText)
                    .font(.caption2)
                    .foregroundStyle(Color.white.opacity(0.62))
            }
        }
        .padding(12)
        .background(Color.black.opacity(0.92))
        .overlay(
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1),
            alignment: .top
        )
    }

    private var selectionSummary: some View {
        HStack(spacing: 12) {
            Text("\(selectedScanIDs.count) scans selecionados")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)

            Spacer()

            Text("\(selectedShareURLs.count) arquivos para compartilhar")
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.7))
        }
    }

    private var allScansSummary: some View {
        HStack(spacing: 12) {
            Text("\(scans.count) scans salvos")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)

            Spacer()

            Text("\(allShareURLs.count) arquivos disponiveis")
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.7))
        }
    }

    private var selectedScans: [ScanItem] {
        scans.filter { selectedScanIDs.contains($0.id) }
    }

    private var selectedShareURLs: [URL] {
        shareURLs(for: selectedScans)
    }

    private var allShareURLs: [URL] {
        shareURLs(for: scans)
    }

    private var allSTLURLs: [URL] {
        uniqueURLs(scans.map(\.fileURL))
    }

    private var allReportURLs: [URL] {
        reportURLs(for: scans)
    }

    private var allDiagnosticsURLs: [URL] {
        diagnosticsURLs(for: scans)
    }

    private func reloadScans() {
        scans = storageManager.loadScans()

        let availableScanIDs = Set(scans.map(\.id))
        selectedScanIDs.formIntersection(availableScanIDs)

        if scans.isEmpty {
            exitSelectionMode()
        }
    }

    private func deleteScan(_ scan: ScanItem) {
        storageManager.deleteScan(scan)
        selectedScanIDs.remove(scan.id)
        reloadScans()
    }

    private func handleScanTap(_ scan: ScanItem) {
        if isSelectionModeActive {
            toggleSelection(for: scan)
        } else {
            selectedScan = scan
        }
    }

    private func enterSelectionMode() {
        isSelectionModeActive = true
        shareStatusText = nil
    }

    private func exitSelectionMode() {
        isSelectionModeActive = false
        selectedScanIDs.removeAll()
        shareStatusText = nil
    }

    private func toggleSelection(for scan: ScanItem) {
        if selectedScanIDs.contains(scan.id) {
            selectedScanIDs.remove(scan.id)
        } else {
            selectedScanIDs.insert(scan.id)
        }

        shareStatusText = nil
    }

    private func selectAllScans() {
        selectedScanIDs = Set(scans.map(\.id))
        shareStatusText = nil
    }

    private func clearSelection() {
        selectedScanIDs.removeAll()
        shareStatusText = nil
    }

    private func reportURLIfAvailable(for scan: ScanItem) -> URL? {
        if let reportURL = scan.reportURL,
           fileManager.fileExists(atPath: reportURL.path) {
            return reportURL
        }

        let inferredReportURL = scan.fileURL
            .deletingLastPathComponent()
            .appendingPathComponent("\(scan.fileURL.deletingPathExtension().lastPathComponent)_report.json")

        guard fileManager.fileExists(atPath: inferredReportURL.path) else {
            return nil
        }

        return inferredReportURL
    }

    private func diagnosticsURLIfAvailable(for scan: ScanItem) -> URL? {
        if let diagnosticsURL = scan.diagnosticsURL,
           fileManager.fileExists(atPath: diagnosticsURL.path) {
            return diagnosticsURL
        }

        let inferredDiagnosticsURL = scan.fileURL
            .deletingLastPathComponent()
            .appendingPathComponent("\(scan.fileURL.deletingPathExtension().lastPathComponent)_diagnostics.json")

        guard fileManager.fileExists(atPath: inferredDiagnosticsURL.path) else {
            return nil
        }

        return inferredDiagnosticsURL
    }

    private func sessionCaptureURLIfAvailable(for scan: ScanItem) -> URL? {
        guard let sessionCaptureURL = scan.sessionCaptureURL,
              fileManager.fileExists(atPath: sessionCaptureURL.path)
        else {
            return nil
        }

        return sessionCaptureURL
    }

    private func shareURLs(for scans: [ScanItem]) -> [URL] {
        let urls = scans.flatMap { scan -> [URL] in
            var scanURLs = [scan.fileURL]

            if let reportURL = reportURLIfAvailable(for: scan) {
                scanURLs.append(reportURL)
            }

            if let diagnosticsURL = diagnosticsURLIfAvailable(for: scan) {
                scanURLs.append(diagnosticsURL)
            }

            if let sessionCaptureURL = sessionCaptureURLIfAvailable(for: scan) {
                scanURLs.append(sessionCaptureURL)
            }

            return scanURLs
        }

        return uniqueURLs(urls)
    }

    private func reportURLs(for scans: [ScanItem]) -> [URL] {
        uniqueURLs(scans.compactMap { reportURLIfAvailable(for: $0) })
    }

    private func diagnosticsURLs(for scans: [ScanItem]) -> [URL] {
        uniqueURLs(scans.compactMap { diagnosticsURLIfAvailable(for: $0) })
    }

    private func uniqueURLs(_ urls: [URL]) -> [URL] {
        var seenPaths = Set<String>()
        var uniqueURLs: [URL] = []

        for url in urls {
            let path = url.standardizedFileURL.path

            guard seenPaths.insert(path).inserted else {
                continue
            }

            uniqueURLs.append(url)
        }

        return uniqueURLs
    }

    private func shareSelectedScans() {
        shareScanFiles(
            urls: selectedShareURLs,
            emptyMessage: "Nenhum scan selecionado",
            statusPrefix: "Compartilhando selecionados"
        )
    }

    private func shareAllScans() {
        shareScanFiles(
            urls: allShareURLs,
            emptyMessage: "Nenhum arquivo para compartilhar",
            statusPrefix: "Compartilhando todos"
        )
    }

    private func shareAllSTLs() {
        shareScanFiles(
            urls: allSTLURLs,
            emptyMessage: "Nenhum STL para compartilhar",
            statusPrefix: "Compartilhando STLs"
        )
    }

    private func shareAllReports() {
        shareScanFiles(
            urls: allReportURLs,
            emptyMessage: "Nenhum report para compartilhar",
            statusPrefix: "Compartilhando reports"
        )
    }

    private func shareAllDiagnostics() {
        shareScanFiles(
            urls: allDiagnosticsURLs,
            emptyMessage: "Nenhum diagnostics para compartilhar",
            statusPrefix: "Compartilhando diagnostics"
        )
    }

    private func shareScanFiles(
        urls: [URL],
        emptyMessage: String,
        statusPrefix: String
    ) {
        let uniqueURLs = uniqueURLs(urls)

        guard !uniqueURLs.isEmpty else {
            shareStatusText = emptyMessage
            return
        }

        shareStatusText = "\(statusPrefix): \(uniqueURLs.count) arquivos"
        shareFiles(urls: uniqueURLs)
    }

    @ViewBuilder
    private func scanContextMenu(for scan: ScanItem) -> some View {
        Button {
            selectedScan = scan
        } label: {
            Label("Abrir STL", systemImage: "cube.transparent")
        }

        if let reportURL = reportURLIfAvailable(for: scan) {
            let packageURLs = uniqueURLs(
                [scan.fileURL, reportURL] + [
                    diagnosticsURLIfAvailable(for: scan),
                    sessionCaptureURLIfAvailable(for: scan)
                ].compactMap { $0 }
            )

            Button {
                shareFiles(urls: packageURLs)
            } label: {
                Label("Compartilhar pacote diagnostico", systemImage: "doc.on.doc")
            }

            Button {
                shareFile(url: reportURL)
            } label: {
                Label("Compartilhar Report JSON", systemImage: "doc.text")
            }

            if let diagnosticsURL = diagnosticsURLIfAvailable(for: scan) {
                Button {
                    shareFile(url: diagnosticsURL)
                } label: {
                    Label("Compartilhar Diagnostics JSON", systemImage: "waveform.path.ecg")
                }
            }
        } else {
            Button {} label: {
                Label("Report indisponivel", systemImage: "doc.text")
            }
            .disabled(true)
        }

        Button {
            shareFile(url: scan.fileURL)
        } label: {
            Label("Compartilhar STL", systemImage: "square.and.arrow.up")
        }

        Button(role: .destructive) {
            deleteScan(scan)
        } label: {
            Label("Deletar", systemImage: "trash")
        }
    }

    @ViewBuilder
    private func scanSwipeActions(for scan: ScanItem) -> some View {
        Button(role: .destructive) {
            deleteScan(scan)
        } label: {
            Label("Deletar", systemImage: "trash")
        }

        if let reportURL = reportURLIfAvailable(for: scan) {
            let packageURLs = uniqueURLs(
                [scan.fileURL, reportURL] + [
                    diagnosticsURLIfAvailable(for: scan),
                    sessionCaptureURLIfAvailable(for: scan)
                ].compactMap { $0 }
            )

            Button {
                shareFiles(urls: packageURLs)
            } label: {
                Label("Pacote", systemImage: "doc.on.doc")
            }
            .tint(Color(red: 0.23, green: 0.51, blue: 0.96))

            Button {
                shareFile(url: reportURL)
            } label: {
                Label("Report", systemImage: "doc.text")
            }
            .tint(Color(red: 0.19, green: 0.66, blue: 0.44))

            if let diagnosticsURL = diagnosticsURLIfAvailable(for: scan) {
                Button {
                    shareFile(url: diagnosticsURL)
                } label: {
                    Label("Diag", systemImage: "waveform.path.ecg")
                }
                .tint(Color(red: 0.62, green: 0.46, blue: 0.95))
            }
        } else {
            Button {
                shareFile(url: scan.fileURL)
            } label: {
                Label("STL", systemImage: "square.and.arrow.up")
            }
            .tint(Color(red: 0.23, green: 0.51, blue: 0.96))
        }
    }
}

private struct ScanRowView: View {
    let scan: ScanItem
    let hasReport: Bool
    let hasDiagnostics: Bool
    let isSelectionModeActive: Bool
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            if isSelectionModeActive {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(isSelected ? Color.green : Color.white.opacity(0.52))
                    .frame(width: 24, height: 24)
            }

            Image(systemName: "shippingbox.fill")
                .font(.title3)
                .foregroundStyle(Color(red: 0.23, green: 0.51, blue: 0.96))
                .frame(width: 38, height: 38)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(scan.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .foregroundStyle(.white)

                Text(Self.dateFormatter.string(from: scan.date))
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.62))

                Text(statusText)
                    .font(.caption2)
                    .foregroundStyle(hasReport || hasDiagnostics ? Color.green.opacity(0.82) : Color.white.opacity(0.38))
            }

            Spacer()

            if !isSelectionModeActive {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.white.opacity(0.34))
            }
        }
        .padding(.vertical, 8)
    }

    private var statusText: String {
        switch (hasReport, hasDiagnostics) {
        case (true, true):
            return "Report + diagnostics disponiveis"
        case (true, false):
            return "Report JSON disponivel"
        case (false, true):
            return "Diagnostics JSON disponivel"
        case (false, false):
            return "Report indisponivel"
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
