// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DDLReminder",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "DDLReminder", targets: ["DDLReminder"])],
    targets: [
        .target(name: "DeadlineCore"),
        .executableTarget(name: "DDLReminder", dependencies: ["DeadlineCore"]),
        .testTarget(name: "DeadlineCoreTests", dependencies: ["DeadlineCore"])
    ]
)
