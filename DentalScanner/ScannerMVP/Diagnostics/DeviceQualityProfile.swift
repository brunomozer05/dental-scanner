import Foundation

enum DeviceQualityClass: String, Codable {
    case iPhone
    case iPhonePro
    case iPad
    case unknown
}

struct DeviceQualityProfile: Codable, Equatable {
    let qualityClass: DeviceQualityClass
    let profileName: String

    let minDistanceMm: Double?
    let idealMinDistanceMm: Double?
    let idealMaxDistanceMm: Double?
    let maxDistanceMm: Double?
    let tooCloseFocusRiskDistanceMm: Double?

    let focusVarianceThreshold: Double?
    let overlayScale: Double?

    let frameMaskVerticalBorderPercent: Double?
    let frameMaskHorizontalBorderPercent: Double?

    let minAngularSeparationDeg: Double?
    let targetAngularStdDeg: Double?

    let minValidFramesPerMarker: Int?
    let targetOptimizationFrames: Int?

    let recommendedCameraProfileId: String?
    let recommendedCameraProfileName: String?

    let isKnown: Bool
    let warning: String?
    let notes: String?
}

enum DeviceQualityProfileResolver {
    static func profile(
        deviceModelIdentifier: String,
        deviceMarketingName: String?
    ) -> DeviceQualityProfile {
        let identifier = deviceModelIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let marketingName = deviceMarketingName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let recommendedCameraProfile = recommendedCameraProfile(for: identifier)

        if identifier.hasPrefix("iPad") {
            return iPadProfile(recommendedCameraProfile: recommendedCameraProfile)
        }

        if marketingName?.localizedCaseInsensitiveContains("Pro") == true {
            return iPhoneProProfile(recommendedCameraProfile: recommendedCameraProfile)
        }

        if identifier.hasPrefix("iPhone") {
            return iPhoneProfile(
                identifier: identifier,
                recommendedCameraProfile: recommendedCameraProfile
            )
        }

        return unknownProfile()
    }

    private static func recommendedCameraProfile(for identifier: String) -> CameraProfile? {
        identifier.hasPrefix("iPhone17,") ? CameraProfile.profile(for: .wide15x) : nil
    }

    private static func iPhoneProfile(
        identifier: String,
        recommendedCameraProfile: CameraProfile?
    ) -> DeviceQualityProfile {
        let isIPhone16Family = identifier.hasPrefix("iPhone17,")

        return DeviceQualityProfile(
            qualityClass: .iPhone,
            profileName: "iPhone",
            minDistanceMm: 100,
            idealMinDistanceMm: isIPhone16Family ? 150 : nil,
            idealMaxDistanceMm: isIPhone16Family ? 180 : nil,
            maxDistanceMm: 220,
            tooCloseFocusRiskDistanceMm: isIPhone16Family ? 125 : nil,
            focusVarianceThreshold: 70,
            overlayScale: 1.4,
            frameMaskVerticalBorderPercent: 0.275,
            frameMaskHorizontalBorderPercent: 0.225,
            minAngularSeparationDeg: 1.5,
            targetAngularStdDeg: 4.5,
            minValidFramesPerMarker: 65,
            targetOptimizationFrames: 300,
            recommendedCameraProfileId: recommendedCameraProfile?.id,
            recommendedCameraProfileName: recommendedCameraProfile?.name,
            isKnown: true,
            warning: nil,
            notes: isIPhone16Family
                ? "iPhone 16 family: testar wide fisica 1.5x em 150-180 mm."
                : "Perfil amplo para iPhone."
        )
    }

    private static func iPhoneProProfile(
        recommendedCameraProfile: CameraProfile?
    ) -> DeviceQualityProfile {
        DeviceQualityProfile(
            qualityClass: .iPhonePro,
            profileName: "iPhonePro",
            minDistanceMm: 80,
            idealMinDistanceMm: nil,
            idealMaxDistanceMm: nil,
            maxDistanceMm: 150,
            tooCloseFocusRiskDistanceMm: nil,
            focusVarianceThreshold: 150,
            overlayScale: 1.65,
            frameMaskVerticalBorderPercent: 0.275,
            frameMaskHorizontalBorderPercent: 0.3,
            minAngularSeparationDeg: 1.5,
            targetAngularStdDeg: 4.5,
            minValidFramesPerMarker: 65,
            targetOptimizationFrames: 300,
            recommendedCameraProfileId: recommendedCameraProfile?.id,
            recommendedCameraProfileName: recommendedCameraProfile?.name,
            isKnown: true,
            warning: nil,
            notes: "Perfil iPhone Pro separado para testes; nao assumir comportamento igual ao iPhone normal."
        )
    }

    private static func iPadProfile(
        recommendedCameraProfile: CameraProfile?
    ) -> DeviceQualityProfile {
        DeviceQualityProfile(
            qualityClass: .iPad,
            profileName: "iPad",
            minDistanceMm: 85,
            idealMinDistanceMm: nil,
            idealMaxDistanceMm: nil,
            maxDistanceMm: 185,
            tooCloseFocusRiskDistanceMm: nil,
            focusVarianceThreshold: 70,
            overlayScale: 1.0,
            frameMaskVerticalBorderPercent: 0.125,
            frameMaskHorizontalBorderPercent: 0.2,
            minAngularSeparationDeg: 1.5,
            targetAngularStdDeg: 4.5,
            minValidFramesPerMarker: 65,
            targetOptimizationFrames: 300,
            recommendedCameraProfileId: recommendedCameraProfile?.id,
            recommendedCameraProfileName: recommendedCameraProfile?.name,
            isKnown: true,
            warning: nil,
            notes: "Perfil amplo para iPad."
        )
    }

    private static func unknownProfile() -> DeviceQualityProfile {
        DeviceQualityProfile(
            qualityClass: .unknown,
            profileName: "Unknown",
            minDistanceMm: nil,
            idealMinDistanceMm: nil,
            idealMaxDistanceMm: nil,
            maxDistanceMm: nil,
            tooCloseFocusRiskDistanceMm: nil,
            focusVarianceThreshold: nil,
            overlayScale: nil,
            frameMaskVerticalBorderPercent: 0.25,
            frameMaskHorizontalBorderPercent: 0.25,
            minAngularSeparationDeg: 1.5,
            targetAngularStdDeg: 4.5,
            minValidFramesPerMarker: nil,
            targetOptimizationFrames: nil,
            recommendedCameraProfileId: nil,
            recommendedCameraProfileName: nil,
            isKnown: false,
            warning: "Dispositivo nao calibrado - resultados podem variar",
            notes: "Fallback seguro; diagnostics apenas."
        )
    }
}
