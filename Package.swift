// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Kopi",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Kopi", targets: ["Kopi"])],
    targets: [
        .target(name: "KopiKit", linkerSettings: [.linkedLibrary("sqlite3")]),
        .executableTarget(
            name: "Kopi",
            dependencies: ["KopiKit"],
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("Quartz"),
            ]
        ),
        .testTarget(name: "KopiKitTests", dependencies: ["KopiKit"]),
    ]
)
