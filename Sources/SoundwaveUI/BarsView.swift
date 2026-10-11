import AppKit
import SoundwaveAudio
import SoundwaveConfig
import SwiftUI

struct Bars: NSViewRepresentable {
    let tap: AudioTap
    func makeNSView(context: Context) -> BarsView { let view = BarsView(); tap.onLevels = { [weak view] in view?.set($0) }; return view }
    func updateNSView(_ view: BarsView, context: Context) {}
}

final class BarsView: NSView {
    private let bars = (0..<Constants.Analyzer.bands).map { _ in CALayer() }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for bar in bars {
            bar.backgroundColor = .white
            bar.cornerRadius = 1
            bar.bounds = CGRect(x: 0, y: 0, width: 2, height: 3)
            layer?.addSublayer(bar)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    func set(_ levels: [Float]) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (i, (bar, level)) in zip(bars, levels).enumerated() {
            bar.position = CGPoint(x: (CGFloat(i) + 0.5) * bounds.width / CGFloat(bars.count), y: bounds.midY)
            let from = bar.presentation()?.bounds.height ?? bar.bounds.height
            let to = max(3, CGFloat(level) * bounds.height)
            bar.bounds.size.height = to
            let animation = CABasicAnimation(keyPath: "bounds.size.height")
            animation.fromValue = from
            animation.toValue = to
            animation.duration = 1.2 / Constants.Analyzer.publishRate
            bar.add(animation, forKey: "height")
        }
        CATransaction.commit()
    }
}
