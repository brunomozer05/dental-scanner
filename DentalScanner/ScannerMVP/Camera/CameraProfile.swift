import Foundation

struct CameraProfile: Equatable, Identifiable {
    enum Identifier: String, CaseIterable {
        case defaultProfile = "default"
        case wide1x = "wide_1_0x"
        case wide15x = "wide_1_5x"
        case wide2x = "wide_2_0x"
        case wide15xConservativeFocus = "wide_1_5x_conservative_focus"
        case wide2xConservativeFocus = "wide_2_0x_conservative_focus"
    }

    let identifier: Identifier
    let name: String
    let requestedZoomFactor: Double?
    let prefersPhysicalWideCamera: Bool
    let usesConservativeFocusRecovery: Bool
    let isExperimental: Bool
    let debugNote: String?
    let tooCloseFocusRiskDistanceMm: Double?
    let preferredMinScanDistanceMm: Double?
    let preferredIdealMinScanDistanceMm: Double?
    let preferredIdealMaxScanDistanceMm: Double?
    let preferredMaxScanDistanceMm: Double?

    var id: String {
        identifier.rawValue
    }

    static let allProfiles: [CameraProfile] = [
        CameraProfile(
            identifier: .defaultProfile,
            name: "Default",
            requestedZoomFactor: nil,
            prefersPhysicalWideCamera: false,
            usesConservativeFocusRecovery: false,
            isExperimental: false,
            debugNote: "Preserves current camera behavior.",
            tooCloseFocusRiskDistanceMm: nil,
            preferredMinScanDistanceMm: nil,
            preferredIdealMinScanDistanceMm: nil,
            preferredIdealMaxScanDistanceMm: nil,
            preferredMaxScanDistanceMm: nil
        ),
        CameraProfile(
            identifier: .wide1x,
            name: "Wide 1.0x",
            requestedZoomFactor: 1.0,
            prefersPhysicalWideCamera: true,
            usesConservativeFocusRecovery: false,
            isExperimental: false,
            debugNote: "Physical wide camera, no digital zoom.",
            tooCloseFocusRiskDistanceMm: nil,
            preferredMinScanDistanceMm: nil,
            preferredIdealMinScanDistanceMm: nil,
            preferredIdealMaxScanDistanceMm: nil,
            preferredMaxScanDistanceMm: nil
        ),
        CameraProfile(
            identifier: .wide15x,
            name: "Wide 1.5x",
            requestedZoomFactor: 1.5,
            prefersPhysicalWideCamera: true,
            usesConservativeFocusRecovery: false,
            isExperimental: false,
            debugNote: "Recommended initial profile for iPhone 16 family.",
            tooCloseFocusRiskDistanceMm: 125,
            preferredMinScanDistanceMm: 130,
            preferredIdealMinScanDistanceMm: 150,
            preferredIdealMaxScanDistanceMm: 180,
            preferredMaxScanDistanceMm: 220
        ),
        CameraProfile(
            identifier: .wide2x,
            name: "Wide 2.0x",
            requestedZoomFactor: 2.0,
            prefersPhysicalWideCamera: true,
            usesConservativeFocusRecovery: false,
            isExperimental: true,
            debugNote: "Experimental; not recommended for iPhone 16 initial tests.",
            tooCloseFocusRiskDistanceMm: nil,
            preferredMinScanDistanceMm: nil,
            preferredIdealMinScanDistanceMm: nil,
            preferredIdealMaxScanDistanceMm: nil,
            preferredMaxScanDistanceMm: nil
        ),
        CameraProfile(
            identifier: .wide15xConservativeFocus,
            name: "Wide 1.5x Conservative Focus",
            requestedZoomFactor: 1.5,
            prefersPhysicalWideCamera: true,
            usesConservativeFocusRecovery: true,
            isExperimental: false,
            debugNote: "iPhone 16 wide 1.5x with slower focus recovery.",
            tooCloseFocusRiskDistanceMm: 125,
            preferredMinScanDistanceMm: 130,
            preferredIdealMinScanDistanceMm: 150,
            preferredIdealMaxScanDistanceMm: 180,
            preferredMaxScanDistanceMm: 220
        ),
        CameraProfile(
            identifier: .wide2xConservativeFocus,
            name: "Wide 2.0x Conservative Focus",
            requestedZoomFactor: 2.0,
            prefersPhysicalWideCamera: true,
            usesConservativeFocusRecovery: true,
            isExperimental: true,
            debugNote: "Experimental; not recommended for iPhone 16 initial tests.",
            tooCloseFocusRiskDistanceMm: nil,
            preferredMinScanDistanceMm: nil,
            preferredIdealMinScanDistanceMm: nil,
            preferredIdealMaxScanDistanceMm: nil,
            preferredMaxScanDistanceMm: nil
        )
    ]

    static let defaultProfile = allProfiles[0]

    static func profile(for identifier: Identifier) -> CameraProfile {
        allProfiles.first { $0.identifier == identifier } ?? defaultProfile
    }

    static func profile(for id: String) -> CameraProfile? {
        guard let identifier = Identifier(rawValue: id) else {
            return nil
        }

        return profile(for: identifier)
    }
}
