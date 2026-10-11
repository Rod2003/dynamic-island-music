import AppKit
import SoundwaveAudio
import SoundwaveConfig
import SoundwaveNowPlaying
import SwiftUI

/// Click-through overlay pinned around the notch, on every space. Re-lays itself out when screens change.
public final class IslandPanel: NSPanel {
    private let nowPlaying: NowPlaying
    private let tap: AudioTap

    public init(nowPlaying: NowPlaying, tap: AudioTap) {
        self.nowPlaying = nowPlaying
        self.tap = tap
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = Constants.Island.level
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        layout()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in self?.layout() }
    }

    private func layout() {
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }),
              let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea else { return }
        let height = screen.safeAreaInsets.top, notchWidth = screen.frame.width - left.width - right.width
        let size = CGSize(width: notchWidth + 2 * (height + Constants.Island.flare), height: height)
        let hosting = NSHostingView(rootView: IslandView(nowPlaying: nowPlaying, tap: tap, notchWidth: notchWidth, height: height))
        hosting.sizingOptions = []
        contentView = hosting
        setFrame(NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height, width: size.width, height: size.height), display: true)
    }
}
