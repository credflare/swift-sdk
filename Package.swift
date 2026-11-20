// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CredflareSDK",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "CredflareSDK", targets: ["CredflareSDK"])],
    targets: [
        .target(name: "CredflareSDK", resources: [.process("Resources")]),
        .testTarget(name: "CredflareSDKTests", dependencies: ["CredflareSDK"], resources: [.copy("Fixtures"), .copy("ContractServer.mjs")])
    ]
)
