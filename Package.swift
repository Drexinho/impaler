// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Impaler",
    platforms: [.macOS(.v14)],
    targets: [.executableTarget(name: "Impaler", path: "Sources/Impaler")],
    swiftLanguageVersions: [.v5]
)
