// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FundScopeCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "FundScopeCore", targets: ["FundScopeCore"]),
    ],
    dependencies: [
        // Only third-party dependency: unzipping .xlsx files (docs/02-tech-stack.md).
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", exact: "0.9.20"),
    ],
    targets: [
        .target(name: "FundScopeCore", dependencies: ["ZIPFoundation"]),
        .testTarget(name: "FundScopeCoreTests", dependencies: ["FundScopeCore"], resources: [.copy("Fixtures")]),
    ]
)
