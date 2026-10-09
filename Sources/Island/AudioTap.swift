import Accelerate
import AppKit
import AudioToolbox

final class AudioTap {
    private let edges: [Float] = [40, 120, 300, 800, 2000, 5000, 12000]
    private let balanceRise: Float = 1.5, balanceFall: Float = 8
    private let contrast: [Float] = [2, 1.3, 1, 1, 1, 1], beatTime: Float = 0.25
    private let rangeDB: Float = 18, peakFallDB: Float = 0.06
    private let attack: Float = 0.015, release: Float = 0.06
    static let publishRate: Double = 60

    var onLevels: ([Float]) -> Void = { _ in }

    private var active = false
    private var tapped = AudioObjectID(kAudioObjectUnknown)
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var deviceID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?

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
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main) { [weak self] _, _ in
            if self?.active == true { self?.rebuild() }
        }
    }

    func start() { active = true; rebuild() }
    func stop() { active = false; teardown() }

    private func rebuild() {
        guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").first?.processIdentifier else { return }
        let spotify = get(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyTranslatePIDToProcessObject, AudioObjectID(kAudioObjectUnknown), pid: pid)
        guard spotify != kAudioObjectUnknown, spotify != tapped else { return }
        teardown()
        tapped = spotify
        let desc = CATapDescription(stereoMixdownOfProcesses: [spotify])
        guard AudioHardwareCreateProcessTap(desc, &tapID) == noErr else { return }
        let sampleRate = Float(get(tapID, kAudioTapPropertyFormat, AudioStreamBasicDescription()).mSampleRate)
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: desc.uuid.uuidString]],
        ]
        guard AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &deviceID) == noErr,
              AudioDeviceCreateIOProcIDWithBlock(&procID, deviceID, DispatchQueue(label: "island.tap", qos: .userInteractive), { [weak self] _, input, _, _, _ in
                  self?.analyze(input, sampleRate: sampleRate)
              }) == noErr else { return }
        AudioDeviceStart(deviceID, procID)
    }

    private func teardown() {
        if let procID { AudioDeviceStop(deviceID, procID); AudioDeviceDestroyIOProcID(deviceID, procID) }
        if deviceID != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(deviceID) }
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
        procID = nil; deviceID = AudioObjectID(kAudioObjectUnknown); tapID = AudioObjectID(kAudioObjectUnknown); tapped = AudioObjectID(kAudioObjectUnknown)
    }

    private func analyze(_ input: UnsafePointer<AudioBufferList>, sampleRate: Float) {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        guard let buffer = buffers.first, let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { return }
        let stride = max(1, Int(buffer.mNumberChannels))
        let frames = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size / stride
        ring = Array((ring + (max(0, frames - n)..<frames).map { data[$0 * stride] }).suffix(n))

        let (re, im) = dft.transform(real: vDSP.multiply(ring, window), imaginary: [Float](repeating: 0, count: n))
        let binHz = sampleRate / Float(n)
        let bandDB = (0..<smoothed.count).map { band -> Float in
            let lo = max(1, Int(edges[band] / binHz)), hi = min(n / 2, max(lo + 1, Int(edges[band + 1] / binHz)))
            let power = (vDSP.sumOfSquares(re[lo..<hi]) + vDSP.sumOfSquares(im[lo..<hi])) * 4 / Float(n * n)
            return 10 * log10(power + 1e-18)
        }
        let dt = Float(frames) / sampleRate
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

    private func get<T>(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector, _ initial: T, pid: pid_t = 0) -> T {
        var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value = initial, size = UInt32(MemoryLayout<T>.size), pid = pid
        let pidSize = UInt32(pid == 0 ? 0 : MemoryLayout<pid_t>.size)
        _ = withUnsafeMutablePointer(to: &value) { AudioObjectGetPropertyData(id, &addr, pidSize, &pid, &size, $0) }
        return value
    }
}
