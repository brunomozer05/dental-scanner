import SceneKit
import SwiftUI
import UIKit
import simd

struct STLViewerView: View {
    let stlFileURL: URL

    @Environment(\.dismiss) private var dismiss
    @State private var scene: SCNScene?
    @State private var pointOfView: SCNNode?
    @State private var modelNode: SCNNode?
    @State private var baseModelOrientation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 0, 1))
    @State private var rotationX: Float = 0
    @State private var rotationY: Float = 0
    @State private var rotationZ: Float = 0
    @State private var loadErrorMessage: String?
    @State private var isShareSheetPresented = false

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea(.all)

            if let scene {
                SceneView(
                    scene: scene,
                    pointOfView: pointOfView,
                    options: [.allowsCameraControl]
                )
                .ignoresSafeArea(.all)
            } else {
                Text(loadErrorMessage ?? "Carregando STL")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.68))
            }

            VStack {
                HStack {
                    Text(stlFileURL.lastPathComponent)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .foregroundStyle(.white)

                    Spacer()

                    Button {
                        isShareSheetPresented = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(Color(red: 0.11, green: 0.11, blue: 0.12).opacity(0.9))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Exportar STL")

                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(Color(red: 0.11, green: 0.11, blue: 0.12).opacity(0.9))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Fechar visualizador")
                }
                .padding(14)

                Spacer()
            }

            if scene != nil {
                VStack {
                    Spacer()

                    HStack {
                        Spacer()

                        rotationDebugOverlay
                            .frame(width: 320)
                            .padding(14)
                    }
                }
            }
        }
        .background(Color.black)
        .supportedInterfaceOrientations(.landscape)
        .onAppear(perform: loadScene)
        .onChange(of: rotationX) { _, _ in
            applyDebugRotation()
        }
        .onChange(of: rotationY) { _, _ in
            applyDebugRotation()
        }
        .onChange(of: rotationZ) { _, _ in
            applyDebugRotation()
        }
        .sheet(isPresented: $isShareSheetPresented) {
            ActivityView(activityItems: [stlFileURL])
                .presentationDetents([.medium, .large])
        }
    }

    private var rotationDebugOverlay: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Ajuste Rotacao")
                    .font(.caption.weight(.semibold))

                Spacer()

                Button {
                    rotationX = 0
                    rotationY = 0
                    rotationZ = 0
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Resetar rotacao")
            }

            rotationSlider(title: "X", value: $rotationX)
            rotationSlider(title: "Y", value: $rotationY)
            rotationSlider(title: "Z", value: $rotationZ)
        }
        .padding(12)
        .foregroundStyle(.white)
        .background(Color.black.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func rotationSlider(title: String, value: Binding<Float>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))

                Spacer()

                Text(String(format: "%.2f rad", value.wrappedValue))
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.white.opacity(0.68))
            }

            Slider(value: value, in: -Float.pi...Float.pi)
                .tint(.white)
        }
    }

    private func loadScene() {
        do {
            let loadedScene = try STLSceneLoader.makeScene(from: stlFileURL)
            scene = loadedScene.scene
            pointOfView = loadedScene.cameraNode
            modelNode = loadedScene.modelNode
            let loadedModelOrientation = loadedScene.modelNode.simdOrientation
            baseModelOrientation = loadedModelOrientation
            loadErrorMessage = nil
            applyDebugRotation(to: loadedScene.modelNode, baseOrientation: loadedModelOrientation)
        } catch {
            scene = nil
            pointOfView = nil
            modelNode = nil
            baseModelOrientation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 0, 1))
            loadErrorMessage = error.localizedDescription
        }
    }

    private func applyDebugRotation() {
        guard let modelNode else {
            return
        }

        applyDebugRotation(to: modelNode, baseOrientation: baseModelOrientation)
    }

    private func applyDebugRotation(to node: SCNNode, baseOrientation rotation: simd_quatf) {
        let correctionX = simd_quatf(angle: rotationX, axis: SIMD3<Float>(1, 0, 0))
        let correctionY = simd_quatf(angle: rotationY, axis: SIMD3<Float>(0, 1, 0))
        let correctionZ = simd_quatf(angle: rotationZ, axis: SIMD3<Float>(0, 0, 1))
        let correction = correctionZ * correctionY * correctionX

        node.simdOrientation = rotation * correction
    }
}

private enum STLSceneLoader {
    enum LoaderError: LocalizedError {
        case emptyGeometry

        var errorDescription: String? {
            switch self {
            case .emptyGeometry:
                return "Nao foi possivel carregar a geometria do STL."
            }
        }
    }

    struct LoadedScene {
        let scene: SCNScene
        let cameraNode: SCNNode
        let modelNode: SCNNode
    }

    static func makeScene(from fileURL: URL) throws -> LoadedScene {
        let geometry = try makeGeometry(from: fileURL)
        let modelRootNode = SCNNode()
        modelRootNode.name = "STLViewerModelRoot"

        let modelNode = SCNNode(geometry: geometry)
        let scene = SCNScene()

        let bounds = modelNode.boundingBox
        let center = SCNVector3(
            (bounds.min.x + bounds.max.x) / 2,
            (bounds.min.y + bounds.max.y) / 2,
            (bounds.min.z + bounds.max.z) / 2
        )
        let extent = max(
            max(bounds.max.x - bounds.min.x, bounds.max.y - bounds.min.y),
            bounds.max.z - bounds.min.z
        )
        let cameraDistance = max(extent * 2.8, 45)

        modelNode.position = SCNVector3(-center.x, -center.y, -center.z)
        modelRootNode.addChildNode(modelNode)
        scene.rootNode.addChildNode(modelRootNode)

        let ambientLight = SCNLight()
        ambientLight.type = .ambient
        ambientLight.intensity = 340
        ambientLight.color = UIColor(white: 0.82, alpha: 1)

        let ambientNode = SCNNode()
        ambientNode.light = ambientLight
        scene.rootNode.addChildNode(ambientNode)

        let keyLight = SCNLight()
        keyLight.type = .omni
        keyLight.intensity = 820
        keyLight.color = UIColor.white

        let keyLightNode = SCNNode()
        keyLightNode.light = keyLight
        keyLightNode.position = SCNVector3(cameraDistance * 0.7, cameraDistance, cameraDistance)
        scene.rootNode.addChildNode(keyLightNode)

        let camera = SCNCamera()
        camera.zNear = 0.1
        camera.zFar = Double(cameraDistance * 10)
        camera.fieldOfView = 45

        let cameraNode = SCNNode()
        cameraNode.name = "STLViewerCamera"
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0, cameraDistance)
        scene.rootNode.addChildNode(cameraNode)

        scene.background.contents = UIColor.black

        return LoadedScene(scene: scene, cameraNode: cameraNode, modelNode: modelRootNode)
    }

    private static func makeGeometry(from fileURL: URL) throws -> SCNGeometry {
        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        var pendingTriangleVertices: [SCNVector3] = []
        var vertices: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var indices: [Int32] = []

        for line in contents.components(separatedBy: .newlines) {
            let parts = line.split(whereSeparator: \.isWhitespace)
            guard parts.count >= 4, parts[0] == "vertex",
                  let x = Float(String(parts[1])),
                  let y = Float(String(parts[2])),
                  let z = Float(String(parts[3]))
            else {
                continue
            }

            pendingTriangleVertices.append(SCNVector3(x, y, z))

            guard pendingTriangleVertices.count == 3 else {
                continue
            }

            let triangleNormal = makeNormal(
                a: pendingTriangleVertices[0],
                b: pendingTriangleVertices[1],
                c: pendingTriangleVertices[2]
            )

            for vertex in pendingTriangleVertices {
                vertices.append(vertex)
                normals.append(triangleNormal)
                indices.append(Int32(vertices.count - 1))
            }

            pendingTriangleVertices.removeAll(keepingCapacity: true)
        }

        guard !vertices.isEmpty else {
            throw LoaderError.emptyGeometry
        }

        let geometry = SCNGeometry(
            sources: [
                SCNGeometrySource(vertices: vertices),
                SCNGeometrySource(normals: normals)
            ],
            elements: [
                SCNGeometryElement(indices: indices, primitiveType: .triangles)
            ]
        )

        let material = SCNMaterial()
        material.diffuse.contents = UIColor(white: 0.82, alpha: 1)
        material.specular.contents = UIColor(white: 0.28, alpha: 1)
        material.isDoubleSided = true
        geometry.materials = [material]

        return geometry
    }

    private static func makeNormal(a: SCNVector3, b: SCNVector3, c: SCNVector3) -> SCNVector3 {
        let u = SCNVector3(b.x - a.x, b.y - a.y, b.z - a.z)
        let v = SCNVector3(c.x - a.x, c.y - a.y, c.z - a.z)
        let cross = SCNVector3(
            u.y * v.z - u.z * v.y,
            u.z * v.x - u.x * v.z,
            u.x * v.y - u.y * v.x
        )
        let length = sqrt(cross.x * cross.x + cross.y * cross.y + cross.z * cross.z)

        guard length > Float.ulpOfOne else {
            return SCNVector3(0, 1, 0)
        }

        return SCNVector3(
            cross.x / length,
            cross.y / length,
            cross.z / length
        )
    }
}
