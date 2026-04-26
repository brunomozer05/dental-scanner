import SwiftUI

@main
struct DentalScannerApp: App {
    var body: some Scene {
        WindowGroup {
            ScannerView()
                .ignoresSafeArea(.all)
        }
    }
}
