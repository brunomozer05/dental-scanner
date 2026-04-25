import ProjectDescription

let project = Project(
    name: "DentalScanner",
    organizationName: "Dental Scanner",
    options: .options(
        automaticSchemesOptions: .enabled()
    ),
    settings: .settings(
        base: [
            "MARKETING_VERSION": "0.1.0",
            "CURRENT_PROJECT_VERSION": "1",
            "SWIFT_VERSION": "5.0"
        ]
    ),
    targets: [
        .target(
            name: "DentalScanner",
            destinations: .iOS,
            product: .app,
            bundleId: "com.dentalscanner.mvp",
            deploymentTargets: .iOS("17.0"),
            infoPlist: .file(path: "DentalScanner/Info.plist"),
            sources: [
                "DentalScanner/**/*.swift"
            ],
            resources: []
        )
    ]
)
