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
        Target(
            name: "DentalScanner",
            destinations: Destinations.iOS,
            product: Product.app,
            bundleId: "com.dentalscanner.mvp",
            deploymentTargets: DeploymentTargets.iOS("17.0"),
            infoPlist: InfoPlist.file(path: "DentalScanner/Info.plist"),
            sources: [
                "DentalScanner/**/*.swift"
            ],
            resources: []
        )
    ]
)
