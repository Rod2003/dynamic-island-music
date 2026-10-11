import AppKit
import Observation

@Observable public class NowPlaying {
    public private(set) var isPlaying = false
    public private(set) var icon: NSImage?
    public internal(set) var artworkURL: URL?
    public private(set) var appID: String?
    private var outputting: [String] = []

    public init() {}

    public func update(playing: Bool) {
        isPlaying = playing
        refresh()
    }

    /// Bundle IDs of processes currently outputting audio, pushed by `AudioOutputMonitor`.
    public func update(outputting bundleIDs: [String]) {
        outputting = bundleIDs
        refresh()
    }

    func artwork(for appID: String?) -> URL? { nil }

    private func refresh() {
        guard isPlaying else { return }
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        // Helper processes (e.g. com.google.Chrome.helper) match their app by bundle ID prefix.
        let app = outputting.lazy.compactMap { id in apps.first { id.lowercased().hasPrefix($0.bundleIdentifier?.lowercased() ?? "\0") } }.first
        guard app?.bundleIdentifier != appID else { return }
        icon = app?.icon
        appID = app?.bundleIdentifier
        artworkURL = artwork(for: appID)
    }
}
