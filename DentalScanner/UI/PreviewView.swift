import SwiftUI

struct PreviewView: View {
    @ObservedObject var viewModel: CaptureViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let mesh = viewModel.mesh {
                    GroupBox("Resumo da Malha") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Vertices: \(mesh.vertices.count)")
                            Text("Faces: \(mesh.faces.count)")
                            Text("Escala absoluta ancorada por tags ArUco no pipeline planejado.")
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
                        Text("Conclua a captura e execute a reconstrucao para visualizar a malha e o relatorio.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Preview 3D")
    }
}

