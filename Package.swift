// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Ferro",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "Ferro",
            path: "Sources/Ferro",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("QuickLookThumbnailing"),
                .linkedFramework("ServiceManagement"),
            ]
        )
    ]
)
