import Accelerate
import AudioToolbox

/// Taps Spotify's output with a Core Audio process tap and turns it into bar levels (0...1).
final class AudioTap {
    // Knobs (times in seconds):
    // - `edges`: band edges in Hz, one bar per pair, low to high.
    // - `balanceRise`/`balanceFall`: evens out each band's long-term level so every bar shows something on any
    //   song. Fast rise so bass dropping in after an intro isn't pinned at the top; slow fall so breakdowns dip.
    // - `contrast`: boosts each band's beats (swings faster than `beatTime`); bass swings least, so gets most.
    // - `rangeDB`: the 0...1 span below the loudest recent band, which sinks `peakFallDB` per callback (~5 dB/s).
    // - `attack`/`release`: how fast bars rise/fall; smaller = snappier.
    private let edges: [Float] = [40, 120, 300, 800, 2000, 5000, 12000]
    private let balanceRise: Float = 1.5, balanceFall: Float = 8
    private let contrast: [Float] = [2, 1.3, 1, 1, 1, 1], beatTime: Float = 0.25
    private let rangeDB: Float = 18, peakFallDB: Float = 0.06
    private let attack: Float = 0.015, release: Float = 0.06
    /// Buffers arrive ~86/s; publishing 60/s halves CPU, and Core Animation interpolates in between.
    static let publishRate: Double = 60

    /// Called on main with one level per bar, low to high frequency, left to right.
    var onLevels: ([Float]) -> Void = { _ in }

    private var active = false
    private var key = "" // what the current tap was built for
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var deviceID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?

    // Analysis state, only touched on `queue`.
    private let queue = DispatchQueue(label: "island.tap", qos: .userInteractive)
    // 2048 samples = ~21 Hz per bin at 44.1k, fine enough to split kick/808 range from the rest.
    private let n = 2048
    private var ring = [Float](repeating: 0, count: 2048)
    private let window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: 2048, isHalfWindow: false)
    private let dft = try! vDSP.DiscreteFourierTransform(count: 2048, direction: .forward, transformType: .complexComplex, ofType: Float.self)
    private var lastPublish: UInt64 = 0
    private var peakDB: Float = -100
    private var bandAvg: [Float]?
    private var bandRecent: [Float]?
    private var smoothed = [Float](repeating: 0, count: 6)

    init() {
        // Spotify (or its helpers) can register with Core Audio after the play event; rebuild when the list changes.
        var addr = address(kAudioHardwarePropertyProcessObjectList)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main) { [weak self] _, _ in
            if self?.active == true { self?.rebuild() }
        }
    }

    func start() { active = true; rebuild() }
    func stop() { active = false; teardown() }

    private func rebuild() {
        let procs = processObjects(bundlePrefix: "com.spotify.client")
        let output = get(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultSystemOutputDevice, AudioObjectID(0))
        let outputUID = get(output, kAudioDevicePropertyDeviceUID, "" as CFString) as String
        let newKey = "\(procs)|\(outputUID)"
        guard !procs.isEmpty, newKey != key else { return }
        teardown()
        key = newKey

        let desc = CATapDescription(stereoMixdownOfProcesses: procs)
        desc.muteBehavior = .unmuted
        desc.isPrivate = true
        guard ok(AudioHardwareCreateProcessTap(desc, &tapID), "create tap") else { return }
        let sampleRate = Float(get(tapID, kAudioTapPropertyFormat, AudioStreamBasicDescription()).mSampleRate)

        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Island Tap",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true, kAudioSubTapUIDKey: desc.uuid.uuidString]],
        ]
        guard ok(AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &deviceID), "create aggregate") else { return }
        guard ok(AudioDeviceCreateIOProcIDWithBlock(&procID, deviceID, queue) { [weak self] _, input, _, _, _ in
            self?.analyze(input, sampleRate: sampleRate)
        }, "create io proc") else { return }
        _ = ok(AudioDeviceStart(deviceID, procID), "start device")
    }

    private func teardown() {
        if let procID { AudioDeviceStop(deviceID, procID); AudioDeviceDestroyIOProcID(deviceID, procID) }
        if deviceID != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(deviceID) }
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
        procID = nil; deviceID = AudioObjectID(kAudioObjectUnknown); tapID = AudioObjectID(kAudioObjectUnknown); key = ""
    }

    private func analyze(_ input: UnsafePointer<AudioBufferList>, sampleRate: Float) {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        guard let buffer = buffers.first, let data = buffer.mData else { return }
        // ponytail: left channel only, a mono mixdown wouldn't change the picture much
        let stride = max(1, Int(buffer.mNumberChannels)) // non-interleaved buffers report 1
        let frames = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size / stride
        let samples = data.assumingMemoryBound(to: Float.self)
        ring = Array((ring + (max(0, frames - n)..<frames).map { samples[$0 * stride] }).suffix(n))

        let (re, im) = dft.transform(real: vDSP.multiply(ring, window), imaginary: [Float](repeating: 0, count: n))
        let binHz = sampleRate / Float(n)
        let bandDB = (0..<smoothed.count).map { band -> Float in
            let lo = max(1, Int(edges[band] / binHz)), hi = min(n / 2, max(lo + 1, Int(edges[band + 1] / binHz)))
            // Total band energy, not the loudest bin: wide treble bands otherwise flicker more than bass.
            let power = (vDSP.sumOfSquares(re[lo..<hi]) + vDSP.sumOfSquares(im[lo..<hi])) * 4 / Float(n * n)
            return 10 * log10(power + 1e-18)
        }
        let dt = Float(frames) / sampleRate
        if bandDB.max()! > -90 { // skip silence so gaps between songs don't drag the averages down
            let rise = 1 - exp(-dt / balanceRise), fall = 1 - exp(-dt / balanceFall)
            bandAvg = zip(bandAvg ?? bandDB, bandDB).map { a, x in a + (x - a) * (x > a ? rise : fall) }
        }
        let avg = bandAvg ?? bandDB, mean = avg.reduce(0, +) / Float(avg.count)
        let recent = zip(bandRecent ?? bandDB, bandDB).map { $0 + ($1 - $0) * (1 - exp(-dt / beatTime)) }
        bandRecent = recent
        // Loudness scale follows the un-boosted levels, so a contrast-boosted bass hit can't duck the other bars.
        peakDB = max(mean + vDSP.subtract(bandDB, avg).max()!, peakDB - peakFallDB)
        let target = (0..<avg.count).map { band -> Float in
            let db = mean + (recent[band] - avg[band]) + (bandDB[band] - recent[band]) * contrast[band]
            return min(1, max(0, (db - peakDB + rangeDB) / rangeDB))
        }
        smoothed = zip(smoothed, target).map { s, t in s + (t - s) * (1 - exp(-dt / (t > s ? attack : release))) }
        let now = DispatchTime.now().uptimeNanoseconds
        guard now - lastPublish >= UInt64(1e9 / Self.publishRate) else { return }
        lastPublish = now
        let levels = smoothed
        DispatchQueue.main.async { self.onLevels(levels) }
    }

    private func processObjects(bundlePrefix: String) -> [AudioObjectID] {
        var addr = address(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size)
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids)
        return ids.filter { (get($0, kAudioProcessPropertyBundleID, "" as CFString) as String).hasPrefix(bundlePrefix) }
    }

    private func get<T>(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector, _ initial: T) -> T {
        var addr = address(selector)
        var value = initial
        var size = UInt32(MemoryLayout<T>.size)
        _ = withUnsafeMutablePointer(to: &value) { AudioObjectGetPropertyData(id, &addr, 0, nil, &size, $0) }
        return value
    }

    private func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    private func ok(_ status: OSStatus, _ what: String) -> Bool {
        if status != noErr { NSLog("Island: \(what) failed (\(status))") }
        return status == noErr
    }
}
