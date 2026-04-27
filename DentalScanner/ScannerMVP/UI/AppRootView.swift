import SwiftUI

struct AppRootView: View {
    @State private var isScannerActive = false

    var body: some View {
        ZStack {
            if isScannerActive {
                ScannerView {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        isScannerActive = false
                    }
                }
                .transition(.opacity)
            } else {
                HomeView {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        isScannerActive = true
                    }
                }
                .transition(.opacity)
            }
        }
        .background(Color.black)
        .ignoresSafeArea(.all)
    }
}
