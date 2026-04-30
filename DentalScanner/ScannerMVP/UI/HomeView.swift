import SwiftUI
import UIKit

struct HomeView: View {
    let onStartScanning: () -> Void
    @State private var isScanListPresented = false

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea(.all)

            VStack(alignment: .leading, spacing: 28) {
                header

                Spacer(minLength: 18)

                statusCard

                VStack(spacing: 12) {
                    Button(action: onStartScanning) {
                        Label("Iniciar Escaneamento", systemImage: "viewfinder")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 66)
                            .background(Color(red: 0.23, green: 0.51, blue: 0.96))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button {
                        isScanListPresented = true
                    } label: {
                        Label("Meus Scans", systemImage: "folder")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(Color.white.opacity(0.08))
                            .overlay {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 72)
            .padding(.bottom, 34)
        }
        .supportedInterfaceOrientations(.portrait)
        .fullScreenCover(isPresented: $isScanListPresented) {
            ScanListView()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Dental Scanner")
                .font(.system(size: 38, weight: .bold, design: .default))
                .foregroundStyle(.white)

            Text("Escaneamento preciso de implantes")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.white.opacity(0.62))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Status")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)

                Spacer()

                Circle()
                    .fill(Color(red: 0.23, green: 0.51, blue: 0.96))
                    .frame(width: 8, height: 8)
            }

            HStack(spacing: 12) {
                statusItem(title: "Ultimo scan", value: "--")
                statusItem(title: "Qualidade", value: "--")
                statusItem(title: "Erro medio", value: "--")
            }
        }
        .padding(18)
        .background(Color(red: 0.10, green: 0.10, blue: 0.11))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
    }

    private func statusItem(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.48))
                .lineLimit(1)

            Text(value)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
