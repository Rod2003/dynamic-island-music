import AppKit
import SoundwaveAudio
import SoundwaveNowPlaying
import SoundwaveUI

let nowPlaying: NowPlaying = SpotifyNowPlaying()
let tap = AudioTap()
let monitor = AudioOutputMonitor()
tap.onPlayingChange = { nowPlaying.update(playing: $0) }
monitor.onChange = { bundleIDs in
    tap.setActive(!bundleIDs.isEmpty)
    nowPlaying.update(outputting: bundleIDs)
}

let panel = IslandPanel(nowPlaying: nowPlaying, tap: tap)
panel.orderFrontRegardless()
monitor.start()
NSApplication.shared.run()
