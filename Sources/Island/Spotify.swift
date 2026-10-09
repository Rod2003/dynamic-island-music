import SwiftUI

@Observable final class Spotify {
    var isPlaying = false
    var artworkURL: URL?

    private let onPlayingChange: (Bool) -> Void

    init(onPlayingChange: @escaping (Bool) -> Void) {
        self.onPlayingChange = onPlayingChange
        DistributedNotificationCenter.default().addObserver(
            forName: .init("com.spotify.client.PlaybackStateChanged"), object: nil, queue: .main
        ) { [weak self] note in self?.refresh(state: note.userInfo?["Player State"] as? String) }
    }

    func refresh(state: String? = nil) {
        let output = state == "Stopped" ? "" : NSAppleScript(source: """
            if application "Spotify" is running then
                tell application "Spotify" to return (player state as string) & linefeed & (artwork url of current track)
            end if
            return ""
            """)?.executeAndReturnError(nil).stringValue ?? ""
        let parts = output.components(separatedBy: "\n")
        let playing = parts[0] == "playing"
        artworkURL = parts.count > 1 ? URL(string: parts[1]) : nil
        if playing != isPlaying { isPlaying = playing; onPlayingChange(playing) }
    }
}
