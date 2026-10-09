// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Island",
    platforms: [.macOS("14.2")], // process taps
    targets: [.executableTarget(name: "Island")]
)
