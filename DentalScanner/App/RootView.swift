import SwiftUI

struct RootView: View {
    @StateObject private var viewModel = CaptureViewModel()

    var body: some View {
        TabView {
            NavigationStack {
                CaptureView(viewModel: viewModel)
            }
            .tabItem {
                Label("Captura", systemImage: "camera.viewfinder")
            }

            NavigationStack {
                PreviewView(viewModel: viewModel)
            }
            .tabItem {
                Label("Preview", systemImage: "cube.transparent")
            }
        }
    }
}

