import CoreAudio
import Foundation

/// Pushes the bundle IDs of processes currently outputting audio (empty when nothing plays), most recently started first.
/// Driven by Core Audio property listeners on the main queue, no polling.
public final class AudioOutputMonitor {
    public var onChange: ([String]) -> Void = { _ in }

    private let system = AudioObjectID(kAudioObjectSystemObject)
    private var listened = Set<AudioObjectID>()
    private var outputting: [String] = []

    public init() {}

    public func start() {
        listen(system, kAudioHardwarePropertyProcessObjectList, on: .main) { [weak self] in self?.refresh() }
        refresh()
    }

    private func refresh() {
        let processes = objectList(system, kAudioHardwarePropertyProcessObjectList)
        for id in processes where listened.insert(id).inserted {
            listen(id, kAudioProcessPropertyIsRunningOutput, on: .main) { [weak self] in self?.refresh() }
        }
        listened.formIntersection(processes)
        let current = processes
            .filter { property($0, kAudioProcessPropertyIsRunningOutput, UInt32(0)) != 0 }
            .map { property($0, kAudioProcessPropertyBundleID, "" as CFString) as String }
        // Newest first: process-list order would let an app that opened its stream earlier (e.g. a browser) win the icon.
        // ponytail: an already-open stream that starts making sound keeps its old rank; per-process taps if that matters.
        let now = current.filter { !outputting.contains($0) } + outputting.filter { current.contains($0) }
        guard now != outputting else { return }
        outputting = now
        onChange(now)
    }
}
