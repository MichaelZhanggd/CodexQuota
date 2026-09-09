// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CodexQuota",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "CodexQuota", targets: ["CodexQuota"])],
    targets: [
        .target(name: "QuotaCore"),
        .executableTarget(name: "CodexQuota", dependencies: ["QuotaCore"]),
        .testTarget(name: "QuotaCoreTests", dependencies: ["QuotaCore"])
    ]
)
