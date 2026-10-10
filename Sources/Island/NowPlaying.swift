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
    }

    func update(playing: Bool) {
        isPlaying = playing
        guard playing else { return }
        let app = AudioTap.audibleApp()
        icon = app?.icon
        appID = app?.bundleIdentifier
        refreshArtwork()
    }

    private func refreshArtwork() {
        guard appID == "com.spotify.client" else { artworkURL = nil; return }
        artworkURL = NSAppleScript(source: "tell application \"Spotify\" to artwork url of current track")?.executeAndReturnError(nil).stringValue.flatMap(URL.init(string:))
    }
}
