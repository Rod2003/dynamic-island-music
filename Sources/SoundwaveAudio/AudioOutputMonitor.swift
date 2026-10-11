import CoreAudio
import Foundation

/// Pushes the bundle IDs of processes currently outputting audio (empty when nothing plays).
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
        let now = processes
            .filter { property($0, kAudioProcessPropertyIsRunningOutput, UInt32(0)) != 0 }
            .map { property($0, kAudioProcessPropertyBundleID, "" as CFString) as String }
        guard now != outputting else { return }
        outputting = now
        onChange(now)
    }
}
