// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Soundwave",
    platforms: [.macOS("14.2")],
    targets: [
        .executableTarget(
            name: "Soundwave",
            dependencies: [
                "SoundwaveAudio",
                "SoundwaveNowPlaying",
                "SoundwaveUI",
            ]),
        .target(
            name: "SoundwaveConfig"),
        .target(
            name: "SoundwaveAudio",
            dependencies: [
                "SoundwaveConfig"
            ]),
        .target(
            name: "SoundwaveNowPlaying"),
        .target(
            name: "SoundwaveUI",
            dependencies: [
                "SoundwaveConfig",
                "SoundwaveAudio",
                "SoundwaveNowPlaying",
            ]),
        .testTarget(
            name: "SoundwaveAudioTests",
            dependencies: [
                "SoundwaveAudio"
            ]),
    ]
)
