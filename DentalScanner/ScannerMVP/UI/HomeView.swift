import SwiftUI
import UIKit

struct HomeView: View {
    let onStartScanning: () -> Void
    @State private var isScanListPresented = false

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea(.all)

            VStack(spacing: 0) {
                Text("Dental Scanner")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.top, 56)

                Spacer()

                Button(action: onStartScanning) {
                    Text("Iniciar escaneamento")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 58)
                        .background(Color(red: 0.11, green: 0.11, blue: 0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 32)

                Button {
                    isScanListPresented = true
                } label: {
                    Label("Meus Scans", systemImage: "folder")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 32)
                .padding(.top, 12)

                Spacer()
            }
        }
        .supportedInterfaceOrientations(.portrait)
        .fullScreenCover(isPresented: $isScanListPresented) {
            ScanListView()
        }
    }
}
