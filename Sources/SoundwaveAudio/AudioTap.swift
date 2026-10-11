import AudioToolbox
import Foundation
import SoundwaveConfig

/// Global system-audio tap. The tap and its aggregate device live for the app's lifetime; the IOProc only runs while active.
public final class AudioTap {
    public var onLevels: ([Float]) -> Void = { _ in }
    public var onPlayingChange: (Bool) -> Void = { _ in }

    private let queue = DispatchQueue(label: "soundwave.tap", qos: .userInteractive)
    private let sampleRate: Float
    private var analyzer: AudioAnalyzer // only touched on `queue`
    private var deviceID = AudioObjectID(kAudioObjectUnknown), procID: AudioDeviceIOProcID?
    private var isRunning = false, pendingStop: DispatchWorkItem?

    public init() {
        let desc = CATapDescription(monoGlobalTapButExcludeProcesses: [])
        desc.isPrivate = true
        var tapID = AudioObjectID(kAudioObjectUnknown)
        let created = AudioHardwareCreateProcessTap(desc, &tapID) == noErr
        sampleRate = created ? Float(property(tapID, kAudioTapPropertyFormat, AudioStreamBasicDescription()).mSampleRate) : 48000
        analyzer = AudioAnalyzer(sampleRate: sampleRate)
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: desc.uuid.uuidString]],
        ]
        guard created, AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &deviceID) == noErr,
              AudioDeviceCreateIOProcIDWithBlock(&procID, deviceID, queue, { [weak self] _, input, _, _, _ in
                  self?.process(input)
              }) == noErr else { procID = nil; return }
    }

    /// Call on main. Starts IO right away; stops it after `Constants.Tap.stopDelay` unless re-activated first.
    public func setActive(_ active: Bool) {
        pendingStop?.cancel()
        pendingStop = nil
        if active { return start() }
        guard isRunning else { return }
        let stop = DispatchWorkItem { [weak self] in self?.stop() }
        pendingStop = stop
        DispatchQueue.main.asyncAfter(deadline: .now() + Constants.Tap.stopDelay, execute: stop)
    }

    private func start() {
        guard !isRunning, let procID else { return }
        isRunning = AudioDeviceStart(deviceID, procID) == noErr
    }

    private func stop() {
        guard isRunning, let procID else { return }
        AudioDeviceStop(deviceID, procID)
        isRunning = false
        // Queued ahead of any buffers from the next start, so it always begins fresh.
        queue.async { [self] in
            if analyzer.isPlaying { DispatchQueue.main.async { self.onPlayingChange(false) } }
            analyzer = AudioAnalyzer(sampleRate: sampleRate)
        }
    }

    private func process(_ input: UnsafePointer<AudioBufferList>) {
        // Mono tap: one buffer, one channel.
        let buffer = input.pointee.mBuffers
        guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { return }
        let wasPlaying = analyzer.isPlaying
        let levels = analyzer.process(UnsafeBufferPointer(start: data, count: Int(buffer.mDataByteSize) / MemoryLayout<Float>.size))
        let playing = analyzer.isPlaying
        if playing != wasPlaying { DispatchQueue.main.async { self.onPlayingChange(playing) } }
        if let levels { DispatchQueue.main.async { self.onLevels(levels) } }
    }
}
