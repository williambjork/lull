// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LullCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "LullCore", targets: ["LullCore"])
    ],
    targets: [
        .target(name: "LullCore"),
        // Assertion harness. The domain logic is verified by running this
        // executable (`swift run LullCoreVerify`) because XCTest / Swift Testing
        // are not always present in a Command Line Tools-only toolchain.
        .executableTarget(name: "LullCoreVerify", dependencies: ["LullCore"])
    ],
    swiftLanguageModes: [.v6]
)
