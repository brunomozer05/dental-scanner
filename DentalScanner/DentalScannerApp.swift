import SwiftUI

@main
struct DentalScannerApp: App {
    @UIApplicationDelegateAdaptor(DentalScannerAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .ignoresSafeArea(.all)
        }
    }
}
