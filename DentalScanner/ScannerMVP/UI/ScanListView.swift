import SwiftUI

struct ScanListView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var scans: [ScanItem] = []
    @State private var selectedScan: ScanItem?

    private let storageManager = ScanStorageManager()

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
                            selectedScan = scan
                        } label: {
                            ScanRowView(scan: scan)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.black)
                        .listRowSeparatorTint(Color.white.opacity(0.08))
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                deleteScan(scan)
                            } label: {
                                Label("Deletar", systemImage: "trash")
                            }

                            Button {
                                shareFile(url: scan.fileURL)
                            } label: {
                                Label("Compartilhar", systemImage: "square.and.arrow.up")
                            }
                            .tint(Color(red: 0.23, green: 0.51, blue: 0.96))
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
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .supportedInterfaceOrientations(.portrait)
        .onAppear(perform: reloadScans)
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

    private func reloadScans() {
        scans = storageManager.loadScans()
    }

    private func deleteScan(_ scan: ScanItem) {
        storageManager.deleteScan(scan)
        reloadScans()
    }
}

private struct ScanRowView: View {
    let scan: ScanItem

    var body: some View {
        HStack(spacing: 12) {
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
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.white.opacity(0.34))
        }
        .padding(.vertical, 8)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
