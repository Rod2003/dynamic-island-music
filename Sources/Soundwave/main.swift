import AppKit
import SwiftUI

let nowPlaying: NowPlaying = SpotifyNowPlaying()
let tap = AudioTap()
tap.onPlayingChange = { nowPlaying.update(playing: $0) }

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
    let hosting = NSHostingView(rootView: IslandView(nowPlaying: nowPlaying, tap: tap, notchWidth: notchWidth, height: height))
    hosting.sizingOptions = []
    panel.contentView = hosting
    panel.setFrame(NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height, width: size.width, height: size.height), display: true)
}

layout()
NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in layout() }
panel.orderFrontRegardless()
tap.start()
NSApplication.shared.run()

struct IslandView: View {
    let nowPlaying: NowPlaying
    let tap: AudioTap
    let notchWidth: CGFloat
    let height: CGFloat

    static let flare: CGFloat = 6, bottomRadius: CGFloat = 14, inset: CGFloat = 6

    var body: some View {
        let icon = height - 2 * Self.inset
        HStack(spacing: 0) {
            AsyncImage(url: nowPlaying.artworkURL) {
                $0.resizable().clipShape(RoundedRectangle(cornerRadius: icon * 185.4 / 1024, style: .continuous)).padding(icon * 100 / 1024)
            } placeholder: {
                if let icon = nowPlaying.icon { Image(nsImage: icon).resizable() }
            }
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
        .opacity(nowPlaying.isPlaying ? 1 : 0)
        .animation(.easeInOut(duration: 0.25), value: nowPlaying.isPlaying)
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
        let f = IslandView.flare, k: CGFloat = 0.45
        var flares = Path()
        for (edge, dir) in [(r.minX, CGFloat(1)), (r.maxX, -1)] {
            flares.move(to: CGPoint(x: edge, y: r.minY))
            flares.addLine(to: CGPoint(x: edge + dir * f, y: r.minY))
            flares.addLine(to: CGPoint(x: edge + dir * f, y: r.minY + f))
            flares.addCurve(to: CGPoint(x: edge, y: r.minY), control1: CGPoint(x: edge + dir * f, y: r.minY + f * k), control2: CGPoint(x: edge + dir * f * k, y: r.minY))
        }
        let body = UnevenRoundedRectangle(bottomLeadingRadius: IslandView.bottomRadius, bottomTrailingRadius: IslandView.bottomRadius, style: .continuous)
        return body.path(in: r.insetBy(dx: f, dy: 0)).union(flares)
    }
}
