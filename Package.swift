// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WIP",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "WIP", targets: ["WIP"])],
    targets: [.executableTarget(name: "WIP")]
)
