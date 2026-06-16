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

    var id: String {
        identifier.rawValue
    }

    static let allProfiles: [CameraProfile] = [
        CameraProfile(
            identifier: .defaultProfile,
            name: "Default",
            requestedZoomFactor: nil,
            prefersPhysicalWideCamera: false,
            usesConservativeFocusRecovery: false
        ),
        CameraProfile(
            identifier: .wide1x,
            name: "Wide 1.0x",
            requestedZoomFactor: 1.0,
            prefersPhysicalWideCamera: true,
            usesConservativeFocusRecovery: false
        ),
        CameraProfile(
            identifier: .wide15x,
            name: "Wide 1.5x",
            requestedZoomFactor: 1.5,
            prefersPhysicalWideCamera: true,
            usesConservativeFocusRecovery: false
        ),
        CameraProfile(
            identifier: .wide2x,
            name: "Wide 2.0x",
            requestedZoomFactor: 2.0,
            prefersPhysicalWideCamera: true,
            usesConservativeFocusRecovery: false
        ),
        CameraProfile(
            identifier: .wide15xConservativeFocus,
            name: "Wide 1.5x Conservative Focus",
            requestedZoomFactor: 1.5,
            prefersPhysicalWideCamera: true,
            usesConservativeFocusRecovery: true
        ),
        CameraProfile(
            identifier: .wide2xConservativeFocus,
            name: "Wide 2.0x Conservative Focus",
            requestedZoomFactor: 2.0,
            prefersPhysicalWideCamera: true,
            usesConservativeFocusRecovery: true
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
