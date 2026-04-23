import SwiftUI

@MainActor
struct RootView: View {
    @StateObject private var viewModel = CaptureViewModel()

    var body: some View {
        TabView {
            NavigationView {
                CaptureView(viewModel: viewModel)
            }
            .navigationViewStyle(.stack)
            .tabItem {
                Label("Captura", systemImage: "camera.viewfinder")
            }

            NavigationView {
                PreviewView(viewModel: viewModel)
            }
            .navigationViewStyle(.stack)
            .tabItem {
                Label("Preview", systemImage: "cube.transparent")
            }
        }
    }
}
