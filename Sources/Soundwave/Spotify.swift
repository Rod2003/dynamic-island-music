import AppKit

final class SpotifyNowPlaying: NowPlaying {
    override init() {
        super.init()
        DistributedNotificationCenter.default().addObserver(forName: .init("com.spotify.client.PlaybackStateChanged"), object: nil, queue: .main) { [weak self] note in
            guard let self, note.userInfo?["Player State"] as? String != "Stopped" else { return }
            artworkURL = artwork(for: appID)
        }
    }

    override func artwork(for appID: String?) -> URL? {
        guard appID == "com.spotify.client" else { return nil }
        return NSAppleScript(source: "tell application \"Spotify\" to artwork url of current track")?.executeAndReturnError(nil).stringValue.flatMap(URL.init(string:))
    }
}
