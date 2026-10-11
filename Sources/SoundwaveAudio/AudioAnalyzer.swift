import Accelerate
import Dispatch
import SoundwaveConfig

/// Detects sustained playback and turns it into per-band levels (0...1). Feed it from one queue.
public struct AudioAnalyzer {
    private typealias C = Constants.Analyzer

    public private(set) var isPlaying = false

    /// FFT window in samples. At 48kHz: ~43ms of audio, ~23Hz per bin.
    private static let fftSize = 2048
    private let sampleRate: Float
    private let window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: Self.fftSize, isHalfWindow: false)
    private let dft = try! vDSP.DiscreteFourierTransform(count: Self.fftSize, direction: .forward, transformType: .complexComplex, ofType: Float.self)
    // Reused every buffer so the hot path doesn't allocate fftSize-sized arrays.
    private var ring = [Float](repeating: 0, count: Self.fftSize)
    private var windowed = [Float](repeating: 0, count: Self.fftSize)
    private let zeros = [Float](repeating: 0, count: Self.fftSize)
    private var re = [Float](repeating: 0, count: Self.fftSize)
    private var im = [Float](repeating: 0, count: Self.fftSize)
    private var heard: Float = 0, quiet: Float = 0
    private var lastPublish: UInt64 = 0
    private var peakDB: Float = -100
    private var bandAvg: [Float]?
    private var bandRecent: [Float]?
    private var smoothed = [Float](repeating: 0, count: C.bands)

    public init(sampleRate: Float) {
        self.sampleRate = sampleRate
    }

    /// Feeds one mono buffer. Returns levels when a frame is due (at most `publishRate` per second, only while playing).
    public mutating func process(_ samples: UnsafeBufferPointer<Float>) -> [Float]? {
        let fresh = UnsafeBufferPointer(rebasing: samples.suffix(Self.fftSize))
        let dt = Float(samples.count) / sampleRate

        let audible = vDSP.maximumMagnitude(fresh) > 1e-4
        heard = audible ? heard + dt : 0
        quiet = audible ? 0 : quiet + dt
        isPlaying = isPlaying ? quiet < C.hideAfter : heard > C.showAfter
        guard isPlaying else { return nil }

        ring.removeFirst(fresh.count)
        ring.append(contentsOf: fresh)
        vDSP.multiply(ring, window, result: &windowed)
        dft.transform(inputReal: windowed, inputImaginary: zeros, outputReal: &re, outputImaginary: &im)
        let binHz = sampleRate / Float(Self.fftSize)
        // ponytail: the per-band math below still allocates a few 6-element arrays per buffer; preallocate them too if a profile ever shows it.
        let bandDB = (0..<smoothed.count).map { band -> Float in
            let lo = max(1, Int(C.edges[band] / binHz)), hi = min(Self.fftSize / 2, max(lo + 1, Int(C.edges[band + 1] / binHz)))
            let power = (vDSP.sumOfSquares(re[lo..<hi]) + vDSP.sumOfSquares(im[lo..<hi])) * 4 / Float(Self.fftSize * Self.fftSize)
            return 10 * log10(power + 1e-18)
        }
        if bandDB.max()! > -90 {
            let rise = 1 - exp(-dt / C.balanceRise), fall = 1 - exp(-dt / C.balanceFall)
            bandAvg = zip(bandAvg ?? bandDB, bandDB).map { a, x in a + (x - a) * (x > a ? rise : fall) }
        }
        let avg = bandAvg ?? bandDB, mean = vDSP.mean(avg)
        let recent = vDSP.linearInterpolate(bandRecent ?? bandDB, bandDB, using: 1 - exp(-dt / C.beatTime))
        bandRecent = recent
        peakDB = max(mean + vDSP.maximum(vDSP.subtract(bandDB, avg)), peakDB - C.peakFallDB)
        let target = vDSP.clip((0..<avg.count).map { band -> Float in
            let db = mean + (recent[band] - avg[band]) + (bandDB[band] - recent[band]) * C.contrast[band]
            return (db - peakDB + C.rangeDB) / C.rangeDB
        }, to: 0...1)
        smoothed = zip(smoothed, target).map { s, t in s + (t - s) * (1 - exp(-dt / (t > s ? C.attack : C.release))) }
        let now = DispatchTime.now().uptimeNanoseconds
        guard now - lastPublish >= UInt64(1e9 / C.publishRate) else { return nil }
        lastPublish = now
        return smoothed
    }
}
