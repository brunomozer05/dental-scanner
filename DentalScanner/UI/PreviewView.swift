import SwiftUI

struct PreviewView: View {
    @ObservedObject var viewModel: CaptureViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let mesh = viewModel.mesh {
                    GroupBox("Resumo do STL") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Vertices: \(mesh.vertices.count)")
                            Text("Faces: \(mesh.faces.count)")
                            Text("O STL representa os volumes e poses estimadas das tags ArUco detectadas.")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    GroupBox("Relatorio") {
                        Text(viewModel.reportText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                } else {
                    GroupBox("Preview indisponivel") {
                        Text("Conclua a captura e gere o STL das tags para visualizar a malha e o relatorio.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Preview STL")
    }
}
