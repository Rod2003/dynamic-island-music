import SoundwaveConfig
import SwiftUI

struct NotchShape: Shape {
    func path(in r: CGRect) -> Path {
        let f = Constants.Island.flare, k: CGFloat = 0.45
        var flares = Path()
        for (edge, dir) in [(r.minX, CGFloat(1)), (r.maxX, -1)] {
            flares.move(to: CGPoint(x: edge, y: r.minY))
            flares.addLine(to: CGPoint(x: edge + dir * f, y: r.minY))
            flares.addLine(to: CGPoint(x: edge + dir * f, y: r.minY + f))
            flares.addCurve(to: CGPoint(x: edge, y: r.minY), control1: CGPoint(x: edge + dir * f, y: r.minY + f * k), control2: CGPoint(x: edge + dir * f * k, y: r.minY))
        }
        let body = UnevenRoundedRectangle(bottomLeadingRadius: Constants.Island.bottomRadius, bottomTrailingRadius: Constants.Island.bottomRadius, style: .continuous)
        return body.path(in: r.insetBy(dx: f, dy: 0)).union(flares)
    }
}
