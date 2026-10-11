import SwiftUI

@Observable class NowPlaying {
    var isPlaying = false
    var icon: NSImage?
    var artworkURL: URL?
    private(set) var appID: String?

    init() {
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func update(playing: Bool) {
        isPlaying = playing
        refresh()
    }

    func artwork(for appID: String?) -> URL? { nil }

    private func refresh() {
        guard isPlaying else { return }
        let app = AudioTap.audibleApp()
        guard app?.bundleIdentifier != appID else { return }
        icon = app?.icon
        appID = app?.bundleIdentifier
        artworkURL = artwork(for: appID)
    }
}
