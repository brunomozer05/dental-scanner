import ProjectDescription
import Foundation

private enum OpenCV {
    static let xcframeworkPath = "ThirdParty/OpenCV/opencv2.xcframework"

    static var dependencies: [TargetDependency] {
        let hasXCFramework = FileManager.default.fileExists(atPath: xcframeworkPath)

        guard hasXCFramework else {
            return systemDependencies
        }

        return [
            .xcframework(path: .relativeToRoot(xcframeworkPath), status: .required)
        ] + systemDependencies
    }

    static let systemDependencies: [TargetDependency] = [
        .sdk(name: "Accelerate", type: .framework, status: .required),
        .sdk(name: "AVFoundation", type: .framework, status: .required),
        .sdk(name: "CoreGraphics", type: .framework, status: .required),
        .sdk(name: "CoreMedia", type: .framework, status: .required),
        .sdk(name: "CoreVideo", type: .framework, status: .required),
        .sdk(name: "UIKit", type: .framework, status: .required),
        .sdk(name: "c++", type: .library, status: .required)
    ]

    static let headerSearchPaths: SettingValue = .array([
        "$(inherited)",
        "$(SRCROOT)/ThirdParty/OpenCV/opencv2.xcframework/**"
    ])
    static let frameworkSearchPaths: SettingValue = .array([
        "$(inherited)",
        "$(SRCROOT)/ThirdParty/OpenCV"
    ])
}

let project = Project(
    name: "DentalScanner",
    organizationName: "Dental Scanner",
    options: .options(
        automaticSchemesOptions: .enabled()
    ),
    settings: .settings(
        base: [
            "MARKETING_VERSION": .string("0.1.0"),
            "CURRENT_PROJECT_VERSION": .string("1"),
            "SWIFT_VERSION": .string("5.0"),
            "SWIFT_OBJC_BRIDGING_HEADER": .string("DentalScanner/DentalScanner-Bridging-Header.h"),
            "CLANG_CXX_LANGUAGE_STANDARD": .string("gnu++17"),
            "CLANG_CXX_LIBRARY": .string("libc++"),
            "GCC_ENABLE_CPP_EXCEPTIONS": .string("YES"),
            "HEADER_SEARCH_PATHS": OpenCV.headerSearchPaths,
            "FRAMEWORK_SEARCH_PATHS": OpenCV.frameworkSearchPaths,
            "LD_RUNPATH_SEARCH_PATHS": .array([
                "$(inherited)",
                "@executable_path/Frameworks"
            ])
        ]
    ),
    targets: [
        Target(
            name: "DentalScanner",
            destinations: Destinations.iOS,
            product: Product.app,
            bundleId: "com.dentalscanner.mvp",
            deploymentTargets: DeploymentTargets.iOS("17.0"),
            infoPlist: InfoPlist.file(path: "DentalScanner/Info.plist"),
            sources: [
                "DentalScanner/**/*.swift",
                "DentalScanner/**/*.mm"
            ],
            resources: [],
            dependencies: OpenCV.dependencies
        )
    ]
)
