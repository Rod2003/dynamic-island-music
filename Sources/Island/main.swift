import AppKit
import SwiftUI

let tap = AudioTap()
let spotify = Spotify { playing in playing ? tap.start() : tap.stop() }

let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
panel.isOpaque = false
panel.backgroundColor = .clear
panel.hasShadow = false
panel.ignoresMouseEvents = true
panel.level = .mainMenu + 3
panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

func layout() {
    guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }),
          let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea else { return }
    let height = screen.safeAreaInsets.top, notchWidth = screen.frame.width - left.width - right.width
    let size = CGSize(width: notchWidth + 2 * (height + IslandView.flare), height: height)
    let hosting = NSHostingView(rootView: IslandView(spotify: spotify, tap: tap, notchWidth: notchWidth, height: height))
    hosting.sizingOptions = []
    panel.contentView = hosting
    panel.setFrame(NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height, width: size.width, height: size.height), display: true)
}

layout()
NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in layout() }
panel.orderFrontRegardless()
spotify.refresh()
NSApplication.shared.run()

struct IslandView: View {
    let spotify: Spotify
    let tap: AudioTap
    let notchWidth: CGFloat
    let height: CGFloat

    static let flare: CGFloat = 6, bottomRadius: CGFloat = 14, inset: CGFloat = 5

    var body: some View {
        HStack(spacing: 0) {
            AsyncImage(url: spotify.artworkURL) { $0.resizable() } placeholder: { Color.gray.opacity(0.3) }
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .padding(Self.inset)
                .frame(width: height)
            Spacer().frame(width: notchWidth)
            Bars(tap: tap)
                .padding(Self.inset)
                .frame(width: height)
        }
        .padding(.horizontal, Self.flare)
        .frame(height: height)
        .background(.black, in: NotchShape())
        .opacity(spotify.isPlaying ? 1 : 0)
        .animation(.easeInOut(duration: 0.25), value: spotify.isPlaying)
    }
}

struct Bars: NSViewRepresentable {
    let tap: AudioTap
    func makeNSView(context: Context) -> BarsView { let view = BarsView(); tap.onLevels = { [weak view] in view?.set($0) }; return view }
    func updateNSView(_ view: BarsView, context: Context) {}
}

final class BarsView: NSView {
    private let bars = (0..<6).map { _ in CALayer() }

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
            animation.duration = 1.2 / AudioTap.publishRate
            bar.add(animation, forKey: "height")
        }
        CATransaction.commit()
    }
}

struct NotchShape: Shape {
    func path(in r: CGRect) -> Path {
        let f = IslandView.flare, b = IslandView.bottomRadius
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addArc(tangent1End: CGPoint(x: r.minX + f, y: r.minY), tangent2End: CGPoint(x: r.minX + f, y: r.maxY), radius: f)
        p.addArc(tangent1End: CGPoint(x: r.minX + f, y: r.maxY), tangent2End: CGPoint(x: r.maxX, y: r.maxY), radius: b)
        p.addArc(tangent1End: CGPoint(x: r.maxX - f, y: r.maxY), tangent2End: CGPoint(x: r.maxX - f, y: r.minY), radius: b)
        p.addArc(tangent1End: CGPoint(x: r.maxX - f, y: r.minY), tangent2End: CGPoint(x: r.maxX, y: r.minY), radius: f)
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        return p
    }
}
