import SwiftUI

@Observable final class NowPlaying {
    var isPlaying = false
    var icon: NSImage?
    var artworkURL: URL?
    private var appID: String?

    init() {
        DistributedNotificationCenter.default().addObserver(forName: .init("com.spotify.client.PlaybackStateChanged"), object: nil, queue: .main) { [weak self] note in
            if note.userInfo?["Player State"] as? String != "Stopped" { self?.refreshArtwork() }
        }
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refreshApp() }
    }

    func update(playing: Bool) {
        isPlaying = playing
        refreshApp()
    }

    private func refreshApp() {
        guard isPlaying else { return }
        let app = AudioTap.audibleApp()
        guard app?.bundleIdentifier != appID else { return }
        icon = app?.icon
        appID = app?.bundleIdentifier
        refreshArtwork()
    }

    private func refreshArtwork() {
        guard appID == "com.spotify.client" else { artworkURL = nil; return }
        artworkURL = NSAppleScript(source: "tell application \"Spotify\" to artwork url of current track")?.executeAndReturnError(nil).stringValue.flatMap(URL.init(string:))
    }
}
