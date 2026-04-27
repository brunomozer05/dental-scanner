import SwiftUI
import UIKit

final class AppOrientationController {
    static let shared = AppOrientationController()

    private let defaultSupportedOrientations: UIInterfaceOrientationMask = .allButUpsideDown
    private var orientationStack: [(id: UUID, orientations: UIInterfaceOrientationMask)] = []

    var supportedOrientations: UIInterfaceOrientationMask {
        orientationStack.last?.orientations ?? defaultSupportedOrientations
    }

    private init() {}

    @discardableResult
    func push(_ orientations: UIInterfaceOrientationMask) -> UUID {
        let id = UUID()
        orientationStack.append((id: id, orientations: orientations))
        applyCurrentOrientations()
        return id
    }

    func pop(_ id: UUID) {
        orientationStack.removeAll { $0.id == id }
        applyCurrentOrientations()
    }

    private func applyCurrentOrientations() {
        DispatchQueue.main.async {
            if #available(iOS 16.0, *) {
                UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }
                    .filter { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive }
                    .forEach { windowScene in
                        windowScene.requestGeometryUpdate(
                            .iOS(interfaceOrientations: self.supportedOrientations)
                        ) { error in
                            print("Erro ao atualizar orientacao da tela: \(error)")
                        }
                    }
            }

            UIViewController.attemptRotationToDeviceOrientation()
        }
    }
}

final class DentalScannerAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        AppOrientationController.shared.supportedOrientations
    }
}

private struct SupportedInterfaceOrientationsModifier: ViewModifier {
    let orientations: UIInterfaceOrientationMask
    @State private var orientationRequestId: UUID?

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard orientationRequestId == nil else {
                    return
                }

                orientationRequestId = AppOrientationController.shared.push(orientations)
            }
            .onDisappear {
                guard let orientationRequestId else {
                    return
                }

                AppOrientationController.shared.pop(orientationRequestId)
                self.orientationRequestId = nil
            }
    }
}

extension View {
    func supportedInterfaceOrientations(_ orientations: UIInterfaceOrientationMask) -> some View {
        modifier(SupportedInterfaceOrientationsModifier(orientations: orientations))
    }
}
