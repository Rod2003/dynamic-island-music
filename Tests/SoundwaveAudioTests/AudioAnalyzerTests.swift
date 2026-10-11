import Foundation
import Testing
@testable import SoundwaveAudio

@Test func playingNeedsSustainedAudioAndClearsAfterSilence() {
    var analyzer = AudioAnalyzer(sampleRate: 48000)
    let tone = (0..<4800).map { Float(sin(Double($0) * 2 * .pi * 440 / 48000) * 0.5) } // 100ms
    let silence = [Float](repeating: 0, count: 4800)
    func feed(_ samples: [Float]) -> [Float]? { samples.withUnsafeBufferPointer { analyzer.process($0) } }

    for _ in 0..<20 { #expect(feed(tone) == nil) }
    #expect(!analyzer.isPlaying)

    var levels: [Float]?
    for _ in 0..<10 { levels = feed(tone) ?? levels }
    #expect(analyzer.isPlaying)
    #expect(levels?.count == 6 && levels!.allSatisfy { (0...1).contains($0) })

    for _ in 0..<15 { _ = feed(silence) }
    #expect(analyzer.isPlaying)
    for _ in 0..<10 { _ = feed(silence) }
    #expect(!analyzer.isPlaying)
}
