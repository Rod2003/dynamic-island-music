import Accelerate
import AppKit
import AudioToolbox

final class AudioTap {
    private let edges: [Float] = [40, 120, 300, 800, 2000, 5000, 12000]
    private let balanceRise: Float = 1.5, balanceFall: Float = 8
    private let contrast: [Float] = [2, 1.3, 1, 1, 1, 1], beatTime: Float = 0.25
    private let rangeDB: Float = 18, peakFallDB: Float = 0.06
    private let attack: Float = 0.015, release: Float = 0.06
    private let showAfter: Float = 2.5, hideAfter: Float = 2
    static let publishRate: Double = 60

    var onLevels: ([Float]) -> Void = { _ in }
    var onPlayingChange: (Bool) -> Void = { _ in }

    private let n = 2048
    private var ring = [Float](repeating: 0, count: 2048)
    private let window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: 2048, isHalfWindow: false)
    private let dft = try! vDSP.DiscreteFourierTransform(count: 2048, direction: .forward, transformType: .complexComplex, ofType: Float.self)
    private var isPlaying = false, heard: Float = 0, quiet: Float = 0
    private var lastPublish: UInt64 = 0
    private var peakDB: Float = -100
    private var bandAvg: [Float]?
    private var bandRecent: [Float]?
    private var smoothed = [Float](repeating: 0, count: 6)

    func start() {
        let desc = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        var tapID = AudioObjectID(kAudioObjectUnknown), deviceID = AudioObjectID(kAudioObjectUnknown), procID: AudioDeviceIOProcID?
        guard AudioHardwareCreateProcessTap(desc, &tapID) == noErr else { return }
        let sampleRate = Float(property(tapID, kAudioTapPropertyFormat, AudioStreamBasicDescription()).mSampleRate)
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: desc.uuid.uuidString]],
        ]
        guard AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &deviceID) == noErr,
              AudioDeviceCreateIOProcIDWithBlock(&procID, deviceID, DispatchQueue(label: "soundwave.tap", qos: .userInteractive), { [weak self] _, input, _, _, _ in
                  self?.analyze(input, sampleRate: sampleRate)
              }) == noErr else { return }
        AudioDeviceStart(deviceID, procID)
    }

    private func analyze(_ input: UnsafePointer<AudioBufferList>, sampleRate: Float) {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        guard let buffer = buffers.first, let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { return }
        let stride = max(1, Int(buffer.mNumberChannels))
        let frames = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size / stride
        let fresh = (max(0, frames - n)..<frames).map { data[$0 * stride] }
        let dt = Float(frames) / sampleRate

        let audible = vDSP.maximumMagnitude(fresh) > 1e-4
        heard = audible ? heard + dt : 0
        quiet = audible ? 0 : quiet + dt
        let playing = isPlaying ? quiet < hideAfter : heard > showAfter
        if playing != isPlaying {
            isPlaying = playing
            DispatchQueue.main.async { self.onPlayingChange(playing) }
        }
        guard playing else { return }

        ring = Array((ring + fresh).suffix(n))
        let (re, im) = dft.transform(real: vDSP.multiply(ring, window), imaginary: [Float](repeating: 0, count: n))
        let binHz = sampleRate / Float(n)
        let bandDB = (0..<smoothed.count).map { band -> Float in
            let lo = max(1, Int(edges[band] / binHz)), hi = min(n / 2, max(lo + 1, Int(edges[band + 1] / binHz)))
            let power = (vDSP.sumOfSquares(re[lo..<hi]) + vDSP.sumOfSquares(im[lo..<hi])) * 4 / Float(n * n)
            return 10 * log10(power + 1e-18)
        }
        if bandDB.max()! > -90 {
            let rise = 1 - exp(-dt / balanceRise), fall = 1 - exp(-dt / balanceFall)
            bandAvg = zip(bandAvg ?? bandDB, bandDB).map { a, x in a + (x - a) * (x > a ? rise : fall) }
        }
        let avg = bandAvg ?? bandDB, mean = avg.reduce(0, +) / Float(avg.count)
        let recent = zip(bandRecent ?? bandDB, bandDB).map { $0 + ($1 - $0) * (1 - exp(-dt / beatTime)) }
        bandRecent = recent
        peakDB = max(mean + vDSP.subtract(bandDB, avg).max()!, peakDB - peakFallDB)
        let target = (0..<avg.count).map { band -> Float in
            let db = mean + (recent[band] - avg[band]) + (bandDB[band] - recent[band]) * contrast[band]
            return min(1, max(0, (db - peakDB + rangeDB) / rangeDB))
        }
        smoothed = zip(smoothed, target).map { s, t in s + (t - s) * (1 - exp(-dt / (t > s ? attack : release))) }
        let now = DispatchTime.now().uptimeNanoseconds
        guard now - lastPublish >= UInt64(1e9 / Self.publishRate) else { return }
        lastPublish = now
        DispatchQueue.main.async { [smoothed] in self.onLevels(smoothed) }
    }

    static func audibleApp() -> NSRunningApplication? {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size)
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids)
        let bundleIDs = ids.filter { property($0, kAudioProcessPropertyIsRunningOutput, UInt32(0)) != 0 }
            .map { (property($0, kAudioProcessPropertyBundleID, "" as CFString) as String).lowercased() }
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        return bundleIDs.lazy.compactMap { id in apps.first { id.hasPrefix($0.bundleIdentifier?.lowercased() ?? "\0") } }.first
    }
}

private func property<T>(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector, _ initial: T) -> T {
    var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var value = initial, size = UInt32(MemoryLayout<T>.size)
    _ = withUnsafeMutablePointer(to: &value) { AudioObjectGetPropertyData(id, &addr, 0, nil, &size, $0) }
    return value
}
